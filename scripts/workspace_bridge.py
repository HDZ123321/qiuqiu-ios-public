"""Scoped mobile documents, independent of Hermes/admin. No access/content logs.
All path walks use directory FDs + O_NOFOLLOW. No delete, execution or arbitrary
filesystem access. Only non-hidden document allowlist under a dedicated root.
"""
import asyncio
import hashlib
import hmac
import mimetypes
import os
import stat
import uuid
from pathlib import Path
from aiohttp import web

MAX_BYTES = 4 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
MAX_ENTRIES = 1000
TEXT = {'.txt','.md','.csv','.json','.log','.yaml','.yml'}
DOCUMENTS = TEXT | {'.pdf','.png','.jpg','.jpeg','.gif','.webp','.heic'}
SENSITIVE = {'config','configuration','credentials','credential','secret','secrets','key','keys','token','tokens','auth','password','passwords','id_rsa','id_ed25519'}
HEADERS = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}

class Workspace:
    def __init__(self, root):
        self.root = Path(root).absolute()
        if self.root.is_symlink() or self.root.resolve() != self.root:
            raise ValueError('Workspace must be canonical and not a symlink')
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        st = os.fstat(self.fd)
        if st.st_uid != os.getuid() or st.st_mode & 0o077:
            os.close(self.fd)
            raise ValueError('Dedicated workspace must be owner-only')
        self.lock = asyncio.Lock()
    def close(self):
        os.close(self.fd)
    @staticmethod
    def parts(path, directory=False):
        if path == '' and directory: return []
        parts = path.split('/')
        if len(path.encode()) > 1024 or len(parts)>12 or any(not p or p.startswith('.') or '\\' in p or '%' in p or any(ord(c)<32 or ord(c)==127 for c in p) or len(p.encode())>180 for p in parts):
            raise web.HTTPForbidden()
        if any(any(word in SENSITIVE for word in p.lower().replace('-','.').replace('_','.').split('.')) for p in parts):
            raise web.HTTPForbidden()
        if not directory and Path(parts[-1]).suffix.lower() not in DOCUMENTS:
            raise web.HTTPForbidden()
        return parts
    def directory(self, parts):
        fd = os.dup(self.fd)
        try:
            for part in parts:
                nxt = os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
                os.close(fd); fd=nxt
            return fd
        except Exception:
            os.close(fd); raise
    @staticmethod
    def regular(fd):
        st=os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1: raise web.HTTPForbidden()
        if st.st_size>MAX_BYTES: raise web.HTTPRequestEntityTooLarge(max_size=MAX_BYTES,actual_size=st.st_size)
        return st
    def read_at(self, parent, name):
        fd=os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=parent)
        try:
            self.regular(fd)
            data=b''
            while len(data)<=MAX_BYTES:
                chunk=os.read(fd,min(65536,MAX_BYTES+1-len(data)))
                if not chunk: return data
                data+=chunk
            raise web.HTTPRequestEntityTooLarge(max_size=MAX_BYTES,actual_size=len(data))
        finally: os.close(fd)
    @staticmethod
    def etag(data): return '"'+hashlib.sha256(data).hexdigest()+'"'
    def listing(self,path):
        fd=self.directory(self.parts(path,directory=True))
        try:
            names=os.listdir(fd)
            if len(names)>MAX_ENTRIES: raise web.HTTPForbidden(text='Directory exceeds entry limit')
            entries=[]
            for name in sorted(names,key=str.casefold):
                rel=path+'/'+name if path else name
                st=os.stat(name,dir_fd=fd,follow_symlinks=False)
                isdir=stat.S_ISDIR(st.st_mode)
                try: self.parts(rel,directory=isdir)
                except web.HTTPException: continue
                if not isdir and (not stat.S_ISREG(st.st_mode) or st.st_nlink!=1): continue
                entries.append({'name':name,'path':rel,'directory':isdir,'size':st.st_size,'modified':st.st_mtime})
            return {'scope':str(self.root),'path':path,'max_bytes':MAX_BYTES,'entries':entries}
        finally: os.close(fd)
    def usage(self,fd):
        total=0; count=0
        for name in os.listdir(fd):
            st=os.stat(name,dir_fd=fd,follow_symlinks=False); count+=1
            if count>MAX_ENTRIES: raise web.HTTPInsufficientStorage()
            if stat.S_ISREG(st.st_mode): total+=st.st_size
            elif stat.S_ISDIR(st.st_mode):
                child=os.open(name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
                try: total+=self.usage(child)
                finally: os.close(child)
            if total>MAX_TOTAL: raise web.HTTPInsufficientStorage()
        return total
    def content(self,path,method,data=None,match=None):
        parts=self.parts(path); fd=self.directory(parts[:-1]); name=parts[-1]
        try:
            if method=='GET': return self.read_at(fd,name)
            # Cloudflare gzip weakens a content ETag although decoded bytes are identical.
            # Compare its exact SHA256 token, never wildcard or multiple-version matches.
            if match and match.startswith('W/'): match=match[2:]
            assert data is not None
            try:
                st = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1: raise web.HTTPForbidden()
            except FileNotFoundError: pass
            if Path(name).suffix.lower() in TEXT:
                try: data.decode('utf-8')
                except UnicodeDecodeError: raise web.HTTPBadRequest(text='Text must be UTF-8')
            if method=='PUT':
                if Path(name).suffix.lower() not in TEXT: raise web.HTTPForbidden(text='Only UTF-8 text is editable')
                if not match: raise web.HTTPPreconditionRequired()
                old=self.read_at(fd,name)
                if not hmac.compare_digest(self.etag(old),match): raise web.HTTPPreconditionFailed()
            else:
                try:
                    os.stat(name,dir_fd=fd,follow_symlinks=False)
                except FileNotFoundError: pass
                else:
                    # A symlink is forbidden even on a create-only upload.
                    st=os.stat(name,dir_fd=fd,follow_symlinks=False)
                    if not stat.S_ISREG(st.st_mode): raise web.HTTPForbidden()
                    raise web.HTTPConflict(text='File already exists')
            if self.usage(self.fd)+len(data)>MAX_TOTAL: raise web.HTTPInsufficientStorage()
            temp='.upload-'+uuid.uuid4().hex
            out=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=fd)
            try:
                with os.fdopen(out,'wb') as stream:
                    stream.write(data); stream.flush(); os.fsync(stream.fileno())
                if method=='POST':
                    # link is atomic create-if-absent; never clobber another writer.
                    try: os.link(temp,name,src_dir_fd=fd,dst_dir_fd=fd,follow_symlinks=False)
                    except FileExistsError: raise web.HTTPConflict()
                else:
                    # The service lock serializes app edits; If-Match protects stale editors.
                    if self.etag(self.read_at(fd,name))!=match: raise web.HTTPPreconditionFailed()
                    os.replace(temp,name,src_dir_fd=fd,dst_dir_fd=fd)
                os.fsync(fd)
            finally:
                try: os.unlink(temp,dir_fd=fd)
                except FileNotFoundError: pass
            return data
        finally: os.close(fd)

async def handle(request):
    auth = request.headers.get('Authorization','')
    keys = [request.app['app_key']]
    if request.app.get('workspace_key'): keys.append(request.app['workspace_key'])
    if not any(hmac.compare_digest(auth,'Bearer '+key) for key in keys):
        raise web.HTTPUnauthorized(headers={'WWW-Authenticate':'Bearer'})
    if set(request.query)-{'path'} or len(request.query.getall('path',[]))>1: raise web.HTTPBadRequest()
    workspace=request.app['workspace']; path=request.query.get('path','')
    try:
        async with workspace.lock:
            if request.path=='/v1/workspace':
                if request.method!='GET': raise web.HTTPMethodNotAllowed(request.method,['GET'])
                return web.json_response(await asyncio.to_thread(workspace.listing,path),headers=HEADERS)
            if request.path!='/v1/workspace/content': raise web.HTTPNotFound()
            if request.method not in {'GET','POST','PUT'}: raise web.HTTPMethodNotAllowed(request.method,['GET','POST','PUT'])
            workspace.parts(path)
            data=None if request.method=='GET' else await asyncio.wait_for(request.read(),timeout=30)
            if data is not None and len(data)>MAX_BYTES: raise web.HTTPRequestEntityTooLarge(max_size=MAX_BYTES,actual_size=len(data))
            result=await asyncio.to_thread(workspace.content,path,request.method,data,request.headers.get('If-Match'))
            headers={**HEADERS,'ETag':workspace.etag(result),'Content-Disposition':'attachment'}
            return web.Response(body=result,status=201 if request.method=='POST' else 200,content_type=mimetypes.guess_type(path)[0] or 'application/octet-stream',headers=headers)
    except asyncio.TimeoutError: raise web.HTTPRequestTimeout()
    except FileNotFoundError: raise web.HTTPNotFound()
    except (OSError,ValueError): raise web.HTTPForbidden()
