import tempfile, unittest
from pathlib import Path
from aiohttp import web, ClientSession
from aiohttp.test_utils import TestServer, TestClient
from restricted_proxy import Registry, handle, prepare_delivery
from workspace_bridge import Workspace
from project_bridge import Projects

class ProjectHTTP(unittest.IsolatedAsyncioTestCase):
    async def test_scope_routes_run_projection_and_cross_project_artifacts(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve(); root.chmod(0o700)
            registry=Registry(':memory:'); projects=Projects(root,registry.db)
            a=projects.create('A')['id']; b=projects.create('B')['id']
            ar=projects.workspace(a).root; br=projects.workspace(b).root
            (ar/'one.txt').write_bytes(b'one'); (br/'two.txt').write_bytes(b'two')
            (root/'old.txt').write_bytes(b'old')
            observed=[]
            async def native(req):
                if req.method=='POST': observed.append(await req.json()); return web.json_response({'run_id':'run_fixture'},status=202)
                return web.json_response({'run_id':'run_fixture','session_id':'synthetic','output':f'QIUQIU_FILE:{ar}/one.txt\nQIUQIU_FILE:{br}/two.txt\nMEDIA:{root}/old.txt'})
            upstream=TestServer(web.Application()); upstream.app.router.add_route('*','/{tail:.*}',native); await upstream.start_server()
            app=web.Application();app.update(app_key='fixture',native_key='native',registry=registry,projects=projects,workspace=projects.default,active=0,session_native_base=str(upstream.make_url('')).rstrip('/'))
            async with ClientSession() as session:
                app['client']=session;app.router.add_route('*','/{tail:.*}',handle)
                async with TestClient(TestServer(app)) as client:
                    h={'Authorization':'Bearer fixture'}
                    self.assertEqual((await client.get('/v1/app/projects')).status,401)
                    response=await client.get('/v1/app/projects',headers=h);self.assertEqual(response.status,200)
                    self.assertEqual(len((await response.json())['items']),3)
                    response=await client.get('/v1/workspace',params={'project':a},headers=h);self.assertEqual(response.status,200)
                    self.assertEqual([i['name'] for i in (await response.json())['entries']],['one.txt'])
                    self.assertEqual((await client.get('/v1/workspace/content',params={'project':a,'path':'../two.txt'},headers=h)).status,403)
                    self.assertEqual((await client.get('/v1/workspace/content',params={'project':a,'path':'two.txt'},headers=h)).status,404)
                    payload={'input':'hello','artifact_delivery':'workspace-project-v1','project_id':a}
                    rh={**h,'Idempotency-Key':'immutable'}
                    self.assertEqual((await client.post('/v1/runs',json=payload,headers=rh)).status,202)
                    self.assertNotIn('project_id',observed[0]); self.assertIn(str(ar),str(observed[0]['input']))
                    self.assertNotIn('cwd',observed[0])
                    payload['project_id']=b
                    self.assertEqual((await client.post('/v1/runs',json=payload,headers=rh)).status,409)
                    response=await client.get('/v1/app/artifacts/run_fixture',headers=h)
                    items=(await response.json())['items'];self.assertEqual([i['name'] for i in items],['one.txt'])
                    response=await client.get('/v1/app/artifacts/run_fixture/'+items[0]['id'],headers=h);self.assertEqual(await response.read(),b'one')
            await upstream.close();projects.close()

if __name__=='__main__': unittest.main()
