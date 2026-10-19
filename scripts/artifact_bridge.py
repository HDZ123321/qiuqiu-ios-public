"""Read-only generated artifacts: explicit MEDIA references inside the existing workspace.
No client paths, remote fetches, home traversal, symlinks or native key forwarding.
"""
import hashlib
import hmac
import mimetypes
import os
import re
import stat
from pathlib import Path
from aiohttp import web

MAX_BYTES = 4*1024*1024
EXTENSIONS = {'.txt','.md','.csv','.json','.pdf','.png','.jpg','.jpeg','.gif','.webp'}
ROUTE = re.compile(r'/v1/app/artifacts/(run_[A-Za-z0-9_-]+)(?:/([a-f0-9]{64}))?\Z')

def references(text, root):
    root = Path(root).resolve(strict=True)
    items = []
    for match in re.finditer(r'(?:^|\s)(?:MEDIA:|QIUQIU_FILE:)(?:"([^"\n]+)"|([^\s]+))', text or ''):
        candidate = Path(match[1] or match[2])
        try:
            relative = candidate.relative_to(root)
            if not relative.parts or any(p.startswith('.') for p in relative.parts): continue
            if candidate.resolve(strict=True) != candidate: continue
            if candidate.suffix.lower() not in EXTENSIONS: continue
            info = candidate.stat()
            if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_BYTES: continue
            if candidate not in items: items.append(candidate)
        except (ValueError,OSError): continue
        if len(items) == 16: break
    return items

def read(path,root):
    # Walk every component with openat/O_NOFOLLOW: no resolve/open TOCTOU escape.
    try:
        parts = Path(path).relative_to(Path(root).resolve(strict=True)).parts
        if not parts or any(p.startswith('.') for p in parts): raise ValueError()
        fd=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            for part in parts[:-1]:
                child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
                os.close(fd); fd=child
            target=os.open(parts[-1],os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
            try:
                info=os.fstat(target)
                if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_BYTES: raise ValueError()
                data=os.read(target,MAX_BYTES+1)
                if len(data)!=info.st_size: raise ValueError()
                return data
            finally: os.close(target)
        finally: os.close(fd)
    except (ValueError,OSError): raise web.HTTPNotFound()

def identity(path,root):
    return hashlib.sha256(str(path.relative_to(root)).encode()).hexdigest()

async def handle(request):
    match=ROUTE.fullmatch(request.path)
    if not match or request.method!='GET' or request.query_string: raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization',''),'Bearer '+request.app['app_key']): raise web.HTTPUnauthorized()
    if not request.app['registry'].owns(match[1]): raise web.HTTPNotFound()
    root=request.app['workspace'].root.resolve(strict=True)
    base=request.app.get('session_native_base','http://127.0.0.1:8642')
    async with request.app['client'].get(base+'/v1/runs/'+match[1],headers={'Authorization':'Bearer '+request.app['native_key']},allow_redirects=False) as response:
        if response.status!=200: raise web.HTTPBadGateway()
        snapshot=await response.json()
    items=references(snapshot.get('output'),root)
    headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}
    if match[2]:
        for path in items:
            if identity(path,root)==match[2]:
                return web.Response(body=read(path,root),headers=headers,content_type=mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
        raise web.HTTPNotFound()
    return web.json_response({'items':[{'id':identity(p,root),'name':p.name,'mime':mimetypes.guess_type(p.name)[0] or 'application/octet-stream'} for p in items], 'scope':'explicit MEDIA references inside dedicated workspace only'},headers=headers)
