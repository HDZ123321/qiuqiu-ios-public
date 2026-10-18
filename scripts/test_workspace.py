"""Generated fixtures only. Descriptor-safe workspace HTTP integration tests."""
import os
import tempfile
import unittest
from pathlib import Path
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
import workspace_bridge as bridge

class WorkspaceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve() / 'workspace'
        self.root.mkdir(mode=0o700)
        self.scope = bridge.Workspace(self.root)
        app = web.Application(client_max_size=bridge.MAX_BYTES)
        app['workspace'] = self.scope
        app['app_key'] = 'fixture-key'
        app.router.add_route('*', '/v1/workspace', bridge.handle)
        app.router.add_route('*', '/v1/workspace/content', bridge.handle)
        self.client = TestClient(TestServer(app))
        await self.client.start_server()
    async def asyncTearDown(self):
        await self.client.close()
        self.scope.close()
        self.temp.cleanup()
    async def req(self, method, route='', **kwargs):
        return await self.client.request(method, '/v1/workspace'+route, headers={'Authorization':'Bearer fixture-key', **kwargs.pop('headers',{})}, **kwargs)
    async def test_real_upload_download_edit_conflict_roundtrip(self):
        r = await self.req('GET'); self.assertEqual(r.status,200)
        self.assertEqual((await r.json())['scope'],str(self.root))
        r = await self.req('POST','/content?path=fixture.txt',data=b'generated fixture')
        self.assertEqual(r.status,201)
        r = await self.req('GET','/content?path=fixture.txt'); self.assertEqual(await r.read(),b'generated fixture')
        etag = r.headers['ETag']
        r = await self.req('PUT','/content?path=fixture.txt',data=b'edited fixture',headers={'If-Match':etag}); self.assertEqual(r.status,200)
        self.assertEqual((self.root/'fixture.txt').read_bytes(),b'edited fixture')
        r = await self.req('PUT','/content?path=fixture.txt',data=b'stale',headers={'If-Match':etag}); self.assertEqual(r.status,412)
        r = await self.req('POST','/content?path=fixture.txt',data=b'overwrite'); self.assertEqual(r.status,409)
        self.assertEqual((self.root/'fixture.txt').read_bytes(),b'edited fixture')
    async def test_auth_routes_traversal_hidden_and_symlink_read_write(self):
        r = await self.client.get('/v1/workspace'); self.assertEqual(r.status,401)
        (self.root/'safe').mkdir()
        outside = Path(self.temp.name)/'outside.txt'; outside.write_text('not a personal document')
        (self.root/'link.txt').symlink_to(outside)
        (self.root/'linked').symlink_to(self.root/'safe', target_is_directory=True)
        for path in ['../outside.txt','/etc/passwd','.env','safe/../x.txt','link.txt','linked/x.txt','config.json','keys.txt','.hermes/a.txt','a\\b.txt','%2e%2e/x.txt']:
            for method in ['GET','POST','PUT']:
                r=await self.req(method,'/content',params={'path':path},data=b'fixture' if method!='GET' else None)
                self.assertIn(r.status,[400,403,404],(method,path,r.status))
        self.assertEqual(outside.read_text(),'not a personal document')
        r=await self.req('DELETE','/content?path=x.txt'); self.assertEqual(r.status,405)
        r=await self.req('GET'); names=[x['name'] for x in (await r.json())['entries']]
        self.assertNotIn('link.txt',names); self.assertNotIn('linked',names)
    async def test_weak_transport_etag_explicit_save(self):
        r=await self.req('POST','/content?path=transport.md',data=b'generated fixture'); self.assertEqual(r.status,201)
        r=await self.req('GET','/content?path=transport.md'); etag=r.headers['ETag']
        r=await self.req('PUT','/content?path=transport.md',data=b'edited',headers={'If-Match':'W/'+etag})
        self.assertEqual(r.status,200)
    async def test_hardlinks_fifo_and_quota_denied(self):
        outside=Path(self.temp.name)/'hard-outside.txt'; outside.write_text('generated boundary fixture')
        os.link(outside,self.root/'hard.txt')
        os.mkfifo(self.root/'pipe.txt')
        for name in ['hard.txt','pipe.txt']:
            r=await self.req('GET','/content',params={'path':name}); self.assertEqual(r.status,403)
            r=await self.req('PUT','/content',params={'path':name},data=b'fixture',headers={'If-Match':'"fixture"'}); self.assertEqual(r.status,403)
        for index in range(17):
            with (self.root/f'quota-{index}.txt').open('wb') as stream: stream.truncate(bridge.MAX_BYTES)
        r=await self.req('POST','/content?path=extra.txt',data=b'fixture'); self.assertEqual(r.status,507)
        self.assertFalse((self.root/'extra.txt').exists())
    async def test_bounds_utf8_and_missing_precondition(self):
        r=await self.req('POST','/content?path=big.txt',data=b'x'*(bridge.MAX_BYTES+1)); self.assertEqual(r.status,413)
        (self.root/'huge.txt').write_bytes(b'x'*(bridge.MAX_BYTES+1))
        r=await self.req('GET','/content?path=huge.txt'); self.assertEqual(r.status,413)
        (self.root/'normal.txt').write_text('fixture')
        r=await self.req('PUT','/content?path=normal.txt',data=b'new'); self.assertEqual(r.status,428)
        r=await self.req('POST','/content?path=script.sh',data=b'fixture'); self.assertEqual(r.status,403)
        r=await self.req('POST','/content?path=bad.txt',data=b'\xff'); self.assertEqual(r.status,400)
        r=await self.req('POST','/content?path=empty.txt',data=b''); self.assertEqual(r.status,201)

if __name__=='__main__': unittest.main()
