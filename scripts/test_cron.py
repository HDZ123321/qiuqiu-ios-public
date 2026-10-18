"""Cron boundary tests use only an isolated Hermes home; never tick the scheduler."""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from aiohttp import web

def setUpModule():
    global isolated_home, previous_home
    isolated_home=tempfile.TemporaryDirectory()
    previous_home=os.environ.get('HERMES_HOME')
    os.environ['HERMES_HOME']=isolated_home.name
    sys.path.insert(0, os.environ['QIU_HERMES_SOURCE'])
    # Refuse reuse of previously imported native module bound to a real home.
    if 'cron.jobs' in sys.modules:
        raise RuntimeError('Run cron tests in a fresh process for home isolation')

def tearDownModule():
    isolated_home.cleanup()
    if previous_home is None: os.environ.pop('HERMES_HOME',None)
    else: os.environ['HERMES_HOME']=previous_home

class CronPolicy(unittest.TestCase):
    def test_native_paused_creation_and_readonly_legacy(self):
        from cron_bridge import CronBridge
        from cron import jobs
        with tempfile.TemporaryDirectory() as directory:
            bridge = CronBridge(Path(directory)/'owners.sqlite', jobs)
            legacy = jobs.create_job('private legacy prompt', 'every 2h', name='Existing', paused=True)
            item = bridge.apply('create', {'confirm':'create', 'name':'App task', 'prompt':'Summarize locally', 'schedule':'every 3h'})
            self.assertFalse(item['enabled'])
            self.assertTrue(item['manageable'])
            stored = jobs.get_job(item['id'])
            self.assertEqual(stored['deliver'], 'local')
            self.assertIsNone(stored['script'])
            listing = bridge.listing()['jobs']
            other = next(j for j in listing if j['id'] == legacy['id'])
            self.assertFalse(other['manageable'])
            self.assertNotIn('prompt', other)
            self.assertNotIn('private legacy prompt', str(other))
            for action in ('edit','enable','disable','delete','run'):
                body={'confirm':action,'revision':other['revision']}
                if action=='edit': body.update(name='No',prompt='No',schedule='every 1h')
                with self.assertRaises(web.HTTPNotFound): bridge.apply(action,body,legacy['id'])
            self.assertIsNotNone(jobs.get_job(legacy['id']))
            self.assertTrue(CronBridge(Path(directory)/'owners.sqlite',jobs).owns(stored))

    def test_execution_timeline_is_sanitized_metadata_only(self):
        from cron_bridge import CronBridge
        from cron import jobs
        from cron import executions
        with tempfile.TemporaryDirectory() as directory:
            bridge = CronBridge(Path(directory)/'owners.sqlite', jobs)
            item = bridge.apply('create', {'confirm':'create','name':'Timeline','prompt':'fixture','schedule':'every 6h'})
            execution = executions.create_execution(item['id'], source='scheduler')
            executions.finish_execution(execution['id'], success=True)
            listing = bridge.listing()['jobs']
            job = next(j for j in listing if j['id']==item['id'])
            self.assertIn('latest_execution', job)
            timeline = job['latest_execution']
            self.assertNotIn('error', timeline)
            self.assertNotIn('pid', timeline)
            self.assertNotIn('process_id', timeline)
            for key in ('status','claimed_at'):
                self.assertIn(key, timeline)
            # get_job does not enrich with latest_execution (known native
            # asymmetry); the HTTP detail route reads from listing, so the
            # sanitized projection in listing is the contract under test.
            self.assertEqual(job['latest_execution']['status'], 'completed')
            self.assertNotIn('error', str(job['latest_execution']))
            self.assertNotIn('pid', str(job['latest_execution']))

class CronHTTP(unittest.IsolatedAsyncioTestCase):
    async def test_disabled_bridge_has_no_route(self):
        from aiohttp.test_utils import TestClient, TestServer
        import restricted_proxy
        app=web.Application(); app['app_key']='fixture-only'
        app.router.add_route('*','/{tail:.*}',restricted_proxy.handle)
        async with TestClient(TestServer(app)) as client:
            self.assertEqual((await client.get('/v1/cron',headers={'Authorization':'Bearer fixture-only'})).status,404)

    async def test_proxy_opt_in_auth_confirmation_stale_and_native_lifecycle(self):
        from aiohttp.test_utils import TestClient, TestServer
        import restricted_proxy
        from cron_bridge import CronBridge
        from cron import jobs
        with tempfile.TemporaryDirectory() as directory:
            app = web.Application()
            app['app_key'] = 'fixture-only'
            app['cron_bridge'] = CronBridge(Path(directory)/'owners.sqlite', jobs)
            app.router.add_route('*','/{tail:.*}',restricted_proxy.handle)
            async with TestClient(TestServer(app)) as client:
                headers = {'Authorization':'Bearer fixture-only'}
                self.assertEqual((await client.get('/v1/cron')).status,401)
                self.assertEqual((await client.get('/v1/cron?admin=1',headers=headers)).status,404)
                payload = {'name':'HTTP task','prompt':'Only fixture','schedule':'every 4h'}
                self.assertEqual((await client.post('/v1/cron',json=payload,headers=headers)).status,400)
                payload['confirm']='create'
                response = await client.post('/v1/cron',json=payload,headers=headers)
                self.assertEqual(response.status,200)
                item = await response.json(); target='/v1/cron/'+item['id']
                readback=await (await client.get('/v1/cron',headers=headers)).json()
                item=next(j for j in readback['jobs'] if j['id']==item['id'])
                self.assertFalse(item['enabled'])
                for forbidden in ['script','workdir','enabled_toolsets','origin','deliver']:
                    self.assertEqual((await client.post('/v1/cron',json={**payload,forbidden:'bad'},headers=headers)).status,400)
                edit={'confirm':'edit','revision':item['revision'],'name':'Edited','prompt':'Changed fixture','schedule':'every 5h'}
                response=await client.post(target+'/edit',json=edit,headers=headers)
                self.assertEqual(response.status,200); item=await response.json()
                self.assertEqual(item['name'],'Edited')
                self.assertEqual((await client.post(target+'/delete',json={'confirm':'delete','revision':'stale'},headers=headers)).status,409)
                for action in ['enable','disable','run','disable']:
                    response=await client.post(target+'/'+action,json={'confirm':action,'revision':item['revision']},headers=headers)
                    self.assertEqual(response.status,200); item=await response.json()
                    self.assertEqual(item['enabled'],action in ('enable','run'))
                    if action=='enable':
                        self.assertEqual((await client.post(target+'/edit',json={**edit,'revision':item['revision']},headers=headers)).status,409)
                    if action=='run': self.assertIsNotNone(jobs.get_job(item['id']).get('manual_run_at'))
                response=await client.post(target+'/delete',json={'confirm':'delete','revision':item['revision']},headers=headers)
                self.assertEqual(response.status,200)
                self.assertEqual((await client.get(target,headers=headers)).status,404)
                self.assertIsNone(jobs.get_job(item['id']))

if __name__ == '__main__':
    unittest.main()
