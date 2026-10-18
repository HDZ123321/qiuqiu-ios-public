"""Explicit default-profile, read-only conversation browsing. Never grants Runs ownership."""
import asyncio
import hmac
import re
import sqlite3
from pathlib import Path
from aiohttp import web
from session_bridge import page_int, HEADERS, clean_user_title

ROUTE = re.compile(r'/v1/profile/sessions(?:/([A-Za-z0-9_-]{1,200})(/messages)?)?\Z')
# Internal lifecycle rows are not conversation text. Keep their session records visible.
VISIBLE = "role IN ('user','assistant') AND COALESCE(_compressed_summary,0)=0 AND COALESCE(display_kind,'') NOT IN ('hidden','internal_notification','async_delegation_complete','process_complete','model_switch')"
SCOPE = "(profile_name = 'default' OR profile_name IS NULL OR profile_name = '')"

def connect(path):
    db = sqlite3.connect(Path(path).resolve().as_uri()+'?mode=ro', uri=True, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA query_only=ON')
    return db

def metadata(db, row, registry_owned):
    sid=row['id']; title=row['title']; title_source='native'
    if not isinstance(title,str) or not title.strip():
        title=None; title_source=None
        if row['source'] in ('cron','subagent','tool'): return {'session_id':sid,'created_seq':row['seq'],'run_count':registry_owned.get(sid,0),'history':'unavailable','title':None,'title_source':None,'source':row['source'],'archived':bool(row['archived']),'hidden':bool(row['hidden']),'parent_session_id':row['parent_session_id'],'can_continue':False}
        for message in db.execute('SELECT content FROM messages WHERE session_id=? AND role=\'user\' AND '+VISIBLE+' ORDER BY id LIMIT 100',(sid,)):
            title=clean_user_title(message[0])
            if title: title_source='first_user'; break
    return {'session_id':sid,'created_seq':row['seq'],'run_count':registry_owned.get(sid,0),'history':'explicit_fetch',
            'title':' '.join(title.split())[:200] if title else None,'title_source':title_source,
            'source':row['source'] or 'unknown','archived':bool(row['archived']),'hidden':bool(row['hidden']),
            'parent_session_id':row['parent_session_id'],'can_continue':sid in registry_owned}

def read(path,sid,messages,limit,cursor,owned):
    with connect(path) as db:
        db.execute('BEGIN')
        if sid:
            row=db.execute('SELECT rowid AS seq,id,source,title,archived,hidden,parent_session_id FROM sessions WHERE '+SCOPE+' AND id=?',(sid,)).fetchone()
            if row is None: raise web.HTTPNotFound()
            if not messages: return metadata(db,row,owned)
            if row['source'] in ('cron','subagent','tool'):
                return {'session_id':sid,'history':'unavailable','items':[],'total':0,'next_offset':None}
            # Exact segment only: no compression resolver may silently change provenance.
            total=db.execute('SELECT COUNT(*) FROM messages WHERE session_id=? AND '+VISIBLE,(sid,)).fetchone()[0]
            rows=db.execute('SELECT id,role,content FROM messages WHERE session_id=? AND '+VISIBLE+' ORDER BY id LIMIT ? OFFSET ?',(sid,limit+1,cursor or 0)).fetchall()
            output=[{'id':str(m['id']),'role':m['role'],'content':m['content']} for m in rows[:limit] if isinstance(m['content'],str) and m['content']]
            return {'session_id':sid,'history':'stored_text','items':output,'total':total,'next_offset':(cursor or 0)+limit if len(rows)>limit else None}
        total=db.execute('SELECT COUNT(*) FROM sessions WHERE '+SCOPE).fetchone()[0]
        query='SELECT rowid AS seq,id,source,title,archived,hidden,parent_session_id FROM sessions WHERE '+SCOPE
        params=[]
        if cursor is not None: query+=' AND rowid < ?'; params.append(cursor)
        rows=db.execute(query+' ORDER BY rowid DESC LIMIT ?',params+[limit+1]).fetchall()
        selected=rows[:limit]; more=len(rows)>limit
        return {'items':[metadata(db,r,owned) for r in selected],'total':total,'has_more':more,'next_cursor':selected[-1]['seq'] if more else None,'scope':'default_profile_read_only'}

async def handle(request):
    match=ROUTE.fullmatch(request.path)
    if not match or request.method!='GET' or not request.app.get('profile_sessions_db'): raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization',''),'Bearer '+request.app['app_key']): raise web.HTTPUnauthorized(headers={'WWW-Authenticate':'Bearer'})
    sid,messages=match.groups()
    allowed={'limit','offset'} if messages else ({'limit','before'} if not sid else set())
    if set(request.query)-allowed: raise web.HTTPNotFound()
    limit=page_int(request,'limit',50,100)
    cursor=page_int(request,'offset' if messages else 'before',0 if messages else None,1000000000)
    owned=dict(request.app['registry'].db.execute("SELECT session,COUNT(*) FROM runs WHERE session IS NOT NULL AND session!='' GROUP BY session").fetchall())
    try: payload=await asyncio.to_thread(read,request.app['profile_sessions_db'],sid,messages,limit,cursor,owned)
    except sqlite3.Error: raise web.HTTPServiceUnavailable(text='Profile history unavailable')
    return web.json_response(payload,headers=HEADERS)
