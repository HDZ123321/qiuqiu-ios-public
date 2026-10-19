"""Synthetic generation-to-download contract. No live inference or user files."""
import json
import tempfile
import unittest
from pathlib import Path
from aiohttp import web, ClientSession
from aiohttp.test_utils import TestServer, TestClient
from restricted_proxy import Registry, handle
from workspace_bridge import Workspace

class GeneratedDelivery(unittest.IsolatedAsyncioTestCase):
    def test_legacy_projection_unchanged_and_versioned_context_removed_only_exact_suffix(self):
        from restricted_proxy import prepare_delivery, delivery_hint, display_delivery_text
        from types import SimpleNamespace
        workspace=SimpleNamespace(root=Path('/fixture/workspace'))
        legacy={'input':'original quoted user text','model':'fixture'}
        self.assertIs(prepare_delivery(legacy,workspace),legacy)
        projected=prepare_delivery(dict(legacy,artifact_delivery='workspace-media-v1'),workspace)
        text='\n'.join(p['text'] for p in projected['input'][0]['content'])
        self.assertEqual(display_delivery_text(text,workspace),legacy['input'])
        self.assertEqual(display_delivery_text('prefix '+delivery_hint(workspace.root)+'\nuser text',workspace),'prefix '+delivery_hint(workspace.root)+'\nuser text')
        self.assertEqual(display_delivery_text(text+' tampered',workspace),text+' tampered')
        with self.assertRaises(web.HTTPBadRequest):
            prepare_delivery(dict(legacy,artifact_delivery='unknown'),workspace)

    async def test_opted_in_request_reaches_agent_with_delivery_contract_and_downloads(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            captured = []
            async def create(request):
                payload = await request.json(); captured.append(payload)
                # Fixture acts as a tool-using generator only when the actual request
                # projection tells it the authorized delivery contract.
                text = json.dumps(payload['input'], ensure_ascii=False)
                self.assertIn(str(root), text)
                self.assertIn('MEDIA:', text)
                self.assertIn('write', text.lower())
                self.assertNotIn('artifact_delivery', payload)
                (root/'one.txt').write_bytes(b'1')
                return web.json_response({'run_id':'run_generated','status':'queued'},status=202)
            async def status(request):
                return web.json_response({'run_id':'run_generated','session_id':'session_fixture','status':'completed','output':f'MEDIA:{root}/one.txt'})
            upstream = TestServer(web.Application())
            upstream.app.router.add_post('/v1/runs', create)
            upstream.app.router.add_get('/v1/runs/run_generated', status)
            await upstream.start_server()
            app=web.Application(); app['app_key']='app-fixture'; app['native_key']='native-fixture'
            app['registry']=Registry(root/'owners.sqlite'); app['workspace']=Workspace(root); app['active']=0
            app['session_native_base']=str(upstream.make_url('')).rstrip('/')
            try:
                async with ClientSession() as session:
                    app['client']=session; app.router.add_route('*','/{tail:.*}',handle)
                    async with TestClient(TestServer(app)) as client:
                        h={'Authorization':'Bearer app-fixture','Idempotency-Key':'fixture-new-v1'}
                        body={'input':'发个txt文件给我。内容为1。','model':'fixture','artifact_delivery':'workspace-media-v1'}
                        r=await client.post('/v1/runs',headers=h,json=body)
                        self.assertEqual(r.status,202,await r.text())
                        r=await client.post('/v1/runs',headers=h,json=body)
                        self.assertEqual(r.status,202)
                        self.assertEqual(captured[0],captured[1])
                        route='/v1/app/artifacts/run_generated'
                        items=(await (await client.get(route,headers=h)).json())['items']
                        self.assertEqual([i['name'] for i in items],['one.txt'])
                        r=await client.get(route+'/'+items[0]['id'],headers=h)
                        self.assertEqual(await r.read(),b'1')
                        self.assertEqual((await client.get(route+'?path=/etc/passwd',headers=h)).status,404)
            finally:
                await upstream.close()

if __name__=='__main__': unittest.main()
