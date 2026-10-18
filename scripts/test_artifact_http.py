import asyncio
import tempfile
import unittest
from pathlib import Path
from aiohttp import web, ClientSession
from aiohttp.test_utils import TestServer, TestClient
from restricted_proxy import Registry, handle
from workspace_bridge import Workspace

class ArtifactHTTP(unittest.IsolatedAsyncioTestCase):
    async def test_authenticated_owned_run_download_exact_bytes_no_path_endpoint(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve(); (root/'report.txt').write_bytes(b'generated fixture bytes')
            async def native(request):
                self.assertEqual(request.headers['Authorization'],'Bearer native-fixture')
                return web.json_response({'run_id':'run_fixture','output':f'MEDIA:{root}/report.txt\nMEDIA:/etc/hosts'})
            upstream=TestServer(web.Application()); upstream.app.router.add_get('/v1/runs/run_fixture',native)
            await upstream.start_server()
            app=web.Application(); app['app_key']='app-fixture'; app['native_key']='native-fixture'; app['registry']=Registry(root/'owners.sqlite'); app['registry'].remember('run_fixture','session_fixture'); app['workspace']=Workspace(root); app['session_native_base']=str(upstream.make_url('')).rstrip('/')
            async with ClientSession() as session:
                app['client']=session; app.router.add_route('*','/{tail:.*}',handle)
                async with TestClient(TestServer(app)) as client:
                    route='/v1/app/artifacts/run_fixture'
                    self.assertEqual((await client.get(route)).status,401)
                    h={'Authorization':'Bearer app-fixture'}
                    self.assertEqual((await client.get('/v1/app/artifacts/run_other',headers=h)).status,404)
                    response=await client.get(route,headers=h); self.assertEqual(response.status,200)
                    items=(await response.json())['items']; self.assertEqual([i['name'] for i in items],['report.txt'])
                    response=await client.get(route+'/'+items[0]['id'],headers=h)
                    self.assertEqual(await response.read(),b'generated fixture bytes')
                    self.assertEqual((await client.get(route+'?path=/etc/hosts',headers=h)).status,404)
                    self.assertEqual((await client.post(route,headers=h)).status,404)
            await upstream.close()

if __name__=='__main__': unittest.main()
