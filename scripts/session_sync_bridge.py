"""Explicit app-owned session sync/refresh. Adds active-turn detection and incremental
history polling on top of the existing read-only app/sessions boundary. No inference is
scheduled by sync; the lease row is read from the operator-selected profile DB (read-only)."""
import asyncio
import hmac
import json
import logging
import re
import sqlite3
import time
from urllib.parse import quote
from aiohttp import web, ClientTimeout
from session_bridge import page_int, HEADERS, SAFE, native_json, clean_user_title, titled_item

logger = logging.getLogger(__name__)

ROUTE = re.compile(r'/v1/app/sessions/sync(?:/([A-Za-z0-9_-]{1,200}))?\Z')

def _turn_lease_active(path, session_id):
    """True iff the profile DB holds an unexpired session_turn_lease for this
    conversation lineage (compression root walk mirrors the native key walk)."""
    try:
        db = sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True, timeout=5)
        try:
            db.execute('PRAGMA query_only=ON')
            # Same marker binding as native lease root; excludes explicit forks.
            db.row_factory = sqlite3.Row
            from profile_session_bridge import fork
            current=session_id; seen={current}
            while True:
                value=db.execute('SELECT * FROM sessions WHERE id=?',(current,)).fetchone()
                if value is None: return None
                row=dict(value); parent=row.get('parent_session_id')
                if not parent or parent in seen or fork(row): break
                parent_row=db.execute('SELECT end_reason FROM sessions WHERE id=?',(parent,)).fetchone()
                if not parent_row or parent_row[0]!='compression': break
                seen.add(parent); current=parent
            lease = db.execute(
                'SELECT expires_at FROM session_turn_leases WHERE conversation_id=?', (current,)).fetchone()
            return bool(lease and float(lease[0]) > time.time())
        finally:
            db.close()
    except (sqlite3.Error, TypeError, ValueError):
        return None  # Unknown is not permission to send.

def _registry_run_state(registry, session_id):
    """Latest run this app boundary created for the session, for honest local-vs-server
    status projection. Terminal flags come from the app's own registry only."""
    row = registry.db.execute(
        'SELECT id FROM runs WHERE session=? ORDER BY created_seq DESC LIMIT 1', (session_id,)).fetchone()
    return row[0] if row else None

async def sync_item(request, session_id):
    registry = request.app['registry']
    row = registry.db.execute(
        'SELECT session, MIN(created_seq), COUNT(*) FROM runs WHERE session=? GROUP BY session',
        (session_id,)).fetchone()
    if row is None and not registry.adopted(session_id):
        raise web.HTTPNotFound()
    if row is None: row = (session_id, 0, 0)
    result = {'session_id': session_id, 'created_seq': row[1], 'run_count': row[2],
              'history': 'explicit_fetch', 'channel_active': False, 'last_checked': int(time.time()),
              'server_state': 'unknown'}
    native = await native_json(request, session_id)
    if isinstance(native, dict) and native.get('session', {}).get('id') == session_id:
        title = native['session'].get('title')
        if isinstance(title, str) and title.strip():
            result.update(title=' '.join(title.split())[:200], title_source='native')
    # Native writer hold (any channel incl. WeChat mid-turn) -> busy, never conflicted.
    db_path = request.app.get('profile_sessions_db')
    lease = await asyncio.to_thread(_turn_lease_active, db_path, session_id) if db_path else None
    result['channel_active'] = lease is True
    result['lease_state'] = 'unknown' if lease is None else 'busy' if lease else 'idle'
    run_id = _registry_run_state(registry, session_id)
    if run_id and 'client' in request.app:
        try:
            base = request.app.get('session_native_base', 'http://127.0.0.1:8642')
            async with request.app['client'].get(
                    base + '/v1/runs/' + quote(run_id, safe=''),
                    headers={'Authorization': 'Bearer ' + request.app['native_key']},
                    allow_redirects=False, timeout=ClientTimeout(total=8)) as response:
                if response.status == 200:
                    snapshot = json.loads(await response.read())
                    status = snapshot.get('status')
                    if isinstance(status, str):
                        result['server_state'] = status
                        registry.remember(run_id, snapshot.get('session_id') or session_id)
        except Exception as exc:
            logger.warning("run state poll failed: %r", exc)  # client shows stale, not fake live.
    result['can_continue'] = lease is False
    return result

async def handle(request):
    match = ROUTE.fullmatch(request.path)
    if not request.app.get('sessions_enabled', False) or not match or request.method != 'GET':
        raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization', ''), 'Bearer ' + request.app['app_key']):
        raise web.HTTPUnauthorized(headers={'WWW-Authenticate': 'Bearer'})
    if set(request.query): raise web.HTTPNotFound()
    (session_id,) = match.groups()
    item = await sync_item(request, session_id)
    return web.json_response(item, headers=HEADERS)
