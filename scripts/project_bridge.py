"""App-managed project document scopes, never native cwd or arbitrary paths."""
import hmac, os, re, unicodedata, uuid
from aiohttp import web
from workspace_bridge import Workspace, HEADERS
ID=re.compile(r'p_[a-f0-9]{32}\Z')

class Projects:
    def __init__(self, root, db):
        self.default=Workspace(root); self.db=db; self.cache={'default':self.default}
        db.execute('CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE)')
        db.execute('CREATE TABLE IF NOT EXISTS project_requests(key TEXT PRIMARY KEY, project TEXT NOT NULL, fingerprint TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS project_runs(run TEXT PRIMARY KEY, project TEXT NOT NULL)')
        db.commit()
    def reserve(self,key,project,body):
        import hashlib
        self.workspace(project)
        fingerprint=hashlib.sha256(body).hexdigest()
        row=self.db.execute('SELECT project,fingerprint FROM project_requests WHERE key=?',(key,)).fetchone()
        if row and row!=(project,fingerprint): raise web.HTTPConflict(text='Request scope is immutable')
        with self.db: self.db.execute('INSERT OR IGNORE INTO project_requests VALUES(?,?,?)',(key,project,fingerprint))
    def remember(self,run,key):
        row=self.db.execute('SELECT project FROM project_requests WHERE key=?',(key,)).fetchone()
        if row:
            existing=self.db.execute('SELECT project FROM project_runs WHERE run=?',(run,)).fetchone()
            if existing and existing!=row: raise web.HTTPConflict()
            with self.db: self.db.execute('INSERT OR IGNORE INTO project_runs VALUES(?,?)',(run,row[0]))
    def run_project(self,run):
        row=self.db.execute('SELECT project FROM project_runs WHERE run=?',(run,)).fetchone()
        return row[0] if row else 'default'
    def for_run(self,run): return self.workspace(self.run_project(run))
    def accepts(self,path,project):
        from pathlib import Path
        try:
            parts=Path(path).relative_to(self.workspace(project).root).parts
            return bool(parts) and not any(p.startswith('.') for p in parts)
        except ValueError: return False
    def listing(self):
        return [{'id':'default','name':'默认工作区'}]+[{'id':i,'name':n} for i,n in self.db.execute('SELECT id,name FROM projects ORDER BY rowid')]
    def create(self,name):
        name=unicodedata.normalize('NFC',name).strip() if isinstance(name,str) else ''
        if not name or len(name)>60 or len(name.encode())>180 or name.startswith('.') or any(c in '/\\%' or unicodedata.category(c).startswith('C') for c in name):
            raise web.HTTPBadRequest(text='Invalid project name')
        if any(p['name'].casefold()==name.casefold() for p in self.listing()): raise web.HTTPConflict(text='Project name exists')
        if len(self.listing())>=101: raise web.HTTPConflict(text='Project limit reached')
        key='p_'+uuid.uuid4().hex
        try: os.mkdir('.projects',0o700,dir_fd=self.default.fd)
        except FileExistsError: pass
        parent=os.open('.projects',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=self.default.fd)
        try: os.mkdir(key,0o700,dir_fd=parent)
        finally: os.close(parent)
        with self.db: self.db.execute('INSERT INTO projects VALUES(?,?)',(key,name))
        return {'id':key,'name':name}
    def workspace(self,key):
        if key=='default': return self.default
        if not isinstance(key,str) or not ID.fullmatch(key) or not self.db.execute('SELECT 1 FROM projects WHERE id=?',(key,)).fetchone(): raise web.HTTPNotFound()
        if key not in self.cache: self.cache[key]=Workspace(self.default.root/'.projects'/key)
        workspace=self.cache[key]
        # Cached directory FDs must still identify the canonical project path.
        # Otherwise artifact projection by pathname could follow a replaced sibling.
        if workspace.root.resolve(strict=True)!=workspace.root: raise web.HTTPForbidden()
        opened=os.fstat(workspace.fd); current=workspace.root.stat()
        if (opened.st_dev,opened.st_ino)!=(current.st_dev,current.st_ino): raise web.HTTPForbidden()
        return workspace
    def close(self):
        for workspace in self.cache.values(): workspace.close()

async def handle(request):
    if request.path!='/v1/app/projects' or request.query_string: raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization',''),'Bearer '+request.app['app_key']): raise web.HTTPUnauthorized()
    projects=request.app.get('projects')
    if projects is None: raise web.HTTPNotFound()
    if request.method=='GET': return web.json_response({'items':projects.listing(),'scope':'app-managed documents; not process cwd'},headers=HEADERS)
    if request.method=='POST':
        payload=await request.json()
        if not isinstance(payload,dict) or set(payload)!={'name'}: raise web.HTTPBadRequest()
        return web.json_response(projects.create(payload['name']),status=201,headers=HEADERS)
    raise web.HTTPMethodNotAllowed(request.method,['GET','POST'])
