"""Opt-in native cron boundary. Never forwards dashboard/admin routes or runs a scheduler."""
import asyncio
import hashlib
import hmac
import json
import re
import sqlite3
import threading
from aiohttp import web

ROUTE = re.compile(r'/v1/cron(?:/([a-f0-9]{12})(?:/(edit|enable|disable|delete|run))?)?\Z')

class CronBridge:
    def __init__(self, registry, native):
        self.native = native
        self.db = sqlite3.connect(registry)
        self.db.execute('CREATE TABLE IF NOT EXISTS cron_owners(id TEXT PRIMARY KEY, created TEXT NOT NULL)')
        self.db.commit()
        self.lock = threading.RLock()

    def owns(self, job):
        return self.db.execute('SELECT 1 FROM cron_owners WHERE id=? AND created=?',
                               (job['id'], job.get('created_at',''))).fetchone() is not None

    def project(self, job):
        owned = self.owns(job)
        result = {key: job.get(key) for key in ('id','name','enabled','state','schedule_display','next_run_at','last_run_at','last_status')}
        result['manageable'] = owned
        result['revision'] = hashlib.sha256(json.dumps({k:v for k,v in job.items() if k != 'latest_execution'}, sort_keys=True, default=str).encode()).hexdigest()
        if owned:
            result['prompt'] = job.get('prompt','')
        # Sanitized execution timeline: safe status/timestamps only. Never the
        # native error text (may contain prompts/paths) or process identity.
        latest = job.get('latest_execution')
        if isinstance(latest, dict):
            result['latest_execution'] = {key: latest.get(key) for key in
                ('id','status','claimed_at','started_at','finished_at','source') if key in latest}
        return result

    def listing(self):
        with self.lock:
            return {'jobs':[self.project(job) for job in self.native.list_jobs(include_disabled=True)]}

    def apply(self, action, payload, job_id=None):
        with self.lock:
            if not isinstance(payload, dict) or payload.get('confirm') != action:
                raise web.HTTPBadRequest(text='Explicit exact action confirmation required')
            fields = {'confirm','name','prompt','schedule'} if action == 'create' else {'confirm','revision'}
            if action == 'edit': fields |= {'name','prompt','schedule'}
            if set(payload) != fields:
                raise web.HTTPBadRequest(text='Unsupported fields')
            values = {}
            if action in ('create','edit'):
                for key, maximum in [('name',100),('prompt',8000),('schedule',120)]:
                    if not isinstance(payload[key],str) or not 0 < len(payload[key].strip()) <= maximum:
                        raise web.HTTPBadRequest(text='Invalid task fields')
                values = {key:payload[key].strip() for key in ('name','prompt','schedule')}
            try:
                if action == 'create':
                    job = self.native.create_job(**values, deliver='local', paused=True, origin=None,
                                                 script=None, workdir=None, no_agent=False)
                    self.db.execute('INSERT INTO cron_owners VALUES(?,?)', (job['id'],job['created_at']))
                    self.db.commit()
                    return self.project(self.native.get_job(job['id']))
                if not isinstance(job_id,str) or not re.fullmatch('[a-f0-9]{12}', job_id):
                    raise web.HTTPNotFound()
                job = self.native.get_job(job_id)
                if not job or not self.owns(job): raise web.HTTPNotFound()
                if payload['revision'] != self.project(job)['revision']:
                    raise web.HTTPConflict(text='Task changed; refresh before confirming again')
                if action == 'edit':
                    # Editing an enabled task could execute a changed prompt before renewed approval.
                    if job.get('enabled'): raise web.HTTPConflict(text='Pause task before editing')
                    self.native.update_job(job_id,values)
                elif action == 'enable': self.native.resume_job(job_id)
                elif action == 'disable': self.native.pause_job(job_id,reason='Explicit mobile app action')
                elif action == 'run': self.native.trigger_job(job_id)
                elif action == 'delete':
                    self.native.remove_job(job_id)
                    if self.native.get_job(job_id) is not None: raise web.HTTPBadGateway()
                    self.db.execute('DELETE FROM cron_owners WHERE id=?',(job_id,)); self.db.commit()
                    return {'deleted':job_id}
                else: raise web.HTTPBadRequest()
                verified = self.native.get_job(job_id)
                if not verified: raise web.HTTPBadGateway()
                return self.project(verified)
            except ValueError:
                # Do not expose native errors (which can include prompts/paths) to HTTP clients.
                raise web.HTTPBadRequest(text='Native scheduler rejected task or schedule')

async def handle(request):
    bridge = request.app.get('cron_bridge')
    if bridge is None: raise web.HTTPNotFound()
    if not hmac.compare_digest(request.headers.get('Authorization',''), 'Bearer '+request.app['app_key']):
        raise web.HTTPUnauthorized()
    match = ROUTE.fullmatch(request.raw_path)
    if not match: raise web.HTTPNotFound()
    job_id, action = match.groups()
    headers = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}
    if request.method == 'GET' and action is None:
        listing = bridge.listing()
        if job_id:
            job = next((j for j in listing['jobs'] if j['id']==job_id),None)
            if job is None: raise web.HTTPNotFound()
            return web.json_response(job,headers=headers)
        return web.json_response(listing,headers=headers)
    if request.method != 'POST' or (job_id is not None and action is None): raise web.HTTPNotFound()
    if request.content_length is not None and request.content_length > 16384:
        raise web.HTTPRequestEntityTooLarge(max_size=16384,actual_size=request.content_length)
    raw = bytearray()
    async for chunk in request.content.iter_chunked(4096):
        raw.extend(chunk)
        if len(raw)>16384: raise web.HTTPRequestEntityTooLarge(max_size=16384,actual_size=len(raw))
    try: payload = json.loads(raw)
    except (ValueError,TypeError): raise web.HTTPBadRequest()
    # One process/event-loop transaction; no awaits between ownership check and native write.
    return web.json_response(bridge.apply(action or 'create',payload,job_id),headers=headers)
