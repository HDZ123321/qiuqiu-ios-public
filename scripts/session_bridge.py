"""Opt-in app-owned session boundary. Never query native global session listing."""
import hmac
import re
from urllib.parse import quote
from aiohttp import web, ClientTimeout, ClientError

ROUTE = re.compile(r'/v1/app/sessions(?:/([A-Za-z0-9_-]{1,200})(/messages)?)?\Z')
SAFE = re.compile(r'[A-Za-z0-9_-]{1,200}\Z')
HEADERS = {'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'}

def page_int(request, name, default, maximum):
    values = request.query.getall(name, [])
    if not values: return default
    if len(values) != 1 or not re.fullmatch(r'[0-9]{1,9}', values[0]):
        raise web.HTTPBadRequest(text='Invalid pagination')
    value = int(values[0])
    if value > maximum or (name == 'limit' and value < 1):
        raise web.HTTPBadRequest(text='Invalid pagination')
    return value

def item(row):
    return {'session_id': row[0], 'created_seq': row[1], 'run_count': row[2], 'history': 'explicit_fetch'}

async def handle(request):
    match = ROUTE.fullmatch(request.path)
    if not request.app.get('sessions_enabled', False) or not match or request.method != 'GET':
        raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization',''), 'Bearer '+request.app['app_key']):
        raise web.HTTPUnauthorized(headers={'WWW-Authenticate':'Bearer'})
    sid, messages = match.groups()
    allowed = {'limit','offset'} if messages else ({'limit','before'} if not sid else set())
    if set(request.query) - allowed: raise web.HTTPNotFound()
    registry = request.app['registry']
    # Derive ownership ONLY from durable Runs admitted through this restricted proxy.
    # Stable creation ordering: new runs in an existing session never move pages.
    base = 'SELECT session, MIN(created_seq), COUNT(*) FROM runs WHERE session IS NOT NULL AND session != ? GROUP BY session'
    rows = registry.db.execute(base, ('',)).fetchall()
    rows = [r for r in rows if isinstance(r[0], str) and SAFE.fullmatch(r[0]) and r[1] is not None]
    if sid:
        row = next((r for r in rows if r[0] == sid), None)
        if row is None: raise web.HTTPNotFound()
        if not messages: return web.json_response(item(row), headers=HEADERS)
        limit = page_int(request, 'limit', 50, 100)
        offset = page_int(request, 'offset', 0, 1000000)
        # Only exact owned ID; native handler may resolve compression children. Reject
        # any returned ID not independently present in this app registry (fail closed).
        url = request.app.get('session_native_base','http://127.0.0.1:8642')+'/api/sessions/'+quote(sid, safe='')+'/messages'
        try:
            async with request.app['client'].get(url, params={'limit':str(limit),'offset':str(offset),'order':'oldest'}, headers={'Authorization':'Bearer '+request.app['native_key']}, allow_redirects=False, timeout=ClientTimeout(total=20)) as response:
                if response.status in (404,405,501):
                    return web.json_response({'session_id':sid,'history':'unavailable','items':[],'next_offset':None}, headers=HEADERS)
                if response.status != 200: raise web.HTTPBadGateway(text='Session history unavailable; retry later')
                chunks = bytearray()
                async for chunk in response.content.iter_chunked(65536):
                    chunks.extend(chunk)
                    if len(chunks)>2*1024*1024: raise web.HTTPBadGateway(text='History page exceeds safe limit')
                data = bytes(chunks)
                import json
                payload = json.loads(data)
        except (ClientError, TimeoutError, ValueError):
            raise web.HTTPBadGateway(text='Session history unavailable; retry later')
        if not isinstance(payload, dict): raise web.HTTPBadGateway(text='Invalid history page')
        if payload.get('session_id') != sid:
            # Never grant ownership via a native global resolver.
            return web.json_response({'session_id':sid,'history':'unavailable','items':[],'next_offset':None}, headers=HEADERS)
        raw = payload.get('data')
        if not isinstance(raw,list) or len(raw)>limit: raise web.HTTPBadGateway()
        output = []
        for message in raw:
            if not isinstance(message,dict): raise web.HTTPBadGateway()
            # No tool arguments/results, reasoning, system prompt or metadata export.
            if message.get('role') not in ('user','assistant'): continue
            content, mid = message.get('content'), message.get('id')
            if not isinstance(content,str) or not content or not isinstance(mid,(str,int)) or isinstance(mid,bool): continue
            if message.get('session_id',sid) != sid: raise web.HTTPBadGateway()
            output.append({'id':str(mid),'role':message['role'],'content':content})
        return web.json_response({'session_id':sid,'history':'stored_text','items':output,'next_offset':offset+len(raw) if len(raw)==limit else None}, headers=HEADERS)
    limit = page_int(request, 'limit', 50, 100)
    before = page_int(request, 'before', None, 1000000000)
    rows = sorted((r for r in rows if before is None or r[1]<before), key=lambda r:r[1], reverse=True)
    selected = rows[:limit]
    return web.json_response({'items':[item(r) for r in selected], 'next_cursor':selected[-1][1] if len(rows)>limit else None}, headers=HEADERS)
