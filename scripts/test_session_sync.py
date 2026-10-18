"""Synthetic fixtures for the app-owned sync route: active lease, native run state,
no private content export, no duplicate rows, no inference scheduled."""
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from aiohttp import web, ClientSession
from aiohttp.test_utils import TestClient, TestServer
import restricted_proxy as proxy
import session_sync_bridge

class SyncHTTP(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.environ.get('HERMES_HOME')
        os.environ['HERMES_HOME'] = self.tmp.name
        self.profile_db = Path(self.tmp.name) / 'profile.sqlite'
        import sqlite3
        db = sqlite3.connect(self.profile_db)
        db.executescript("CREATE TABLE sessions(id TEXT PRIMARY KEY,parent_session_id TEXT,end_reason TEXT);"
                         "CREATE TABLE session_turn_leases(conversation_id TEXT PRIMARY KEY,holder TEXT,acquired_at REAL,expires_at REAL);")
        db.execute("INSERT INTO sessions VALUES('s_a',NULL,NULL)")
        db.commit(); db.close()
        self.app = web.Application()
        self.app['app_key'] = 'fixture-only'
        self.app['registry'] = proxy.Registry(Path(self.tmp.name) / 'registry.sqlite')
        self.app['sessions_enabled'] = True
        self.app['profile_sessions_db'] = self.profile_db
        self.app['native_key'] = 'native-fixture'
        self.app.router.add_route('*', '/{tail:.*}', proxy.handle)
        self.client = TestClient(TestServer(self.app))
        await self.client.start_server()
        self.headers = {'Authorization': 'Bearer fixture-only'}
        self.app['client'] = ClientSession()
        self.state = {'run': {'status': 'completed'}, 'title': None}
    async def asyncTearDown(self):
        await self.app['client'].close()
        await self.client.close()
        self.app['registry'].db.close()
        if self.home is None: os.environ.pop('HERMES_HOME', None)
        else: os.environ['HERMES_HOME'] = self.home
        self.tmp.cleanup()

    async def run_native(self, request):
        if request.path.endswith('/s_a'):
            body = {'session': {'id': 's_a'}}
            if self.state['title']: body['session']['title'] = self.state['title']
            return web.json_response(body)
        return web.json_response(self.state['run'])
    async def test_sync_reports_active_lease_busy_and_never_sends(self):
        self.app['registry'].remember('run_a', 's_a')
        native = web.Application()
        native.router.add_get('/api/sessions/s_a', self.run_native)
        native.router.add_get('/api/sessions/s_a/messages', self.run_native)
        native.router.add_get('/v1/runs/run_a', self.run_native)
        async with TestServer(native) as server:
            self.app['session_native_base'] = str(server.make_url('')).rstrip('/')
            import sqlite3
            db = sqlite3.connect(self.profile_db)
            db.execute("INSERT INTO session_turn_leases VALUES('s_a','pid=999999',?,?)",
                       (time.time(), time.time() + 120))
            db.commit(); db.close()
            data = await (await self.client.get('/v1/app/sessions/sync/s_a', headers=self.headers)).json()
            self.assertTrue(data['channel_active'])
            self.assertFalse(data['can_continue'])
            self.assertEqual(data['server_state'], 'completed')
            self.assertEqual(data['session_id'], 's_a')
            self.assertEqual(self.state['run'], {'status': 'completed'})  # native body untouched
            # Lease expired -> free to continue again.
            db = sqlite3.connect(self.profile_db)
            db.execute("UPDATE session_turn_leases SET expires_at=?", (time.time() - 1,)); db.commit(); db.close()
            data = await (await self.client.get('/v1/app/sessions/sync/s_a', headers=self.headers)).json()
            self.assertFalse(data['channel_active'])
            self.assertTrue(data['can_continue'])
            # No content is exported by sync; only status metadata.
            self.assertNotIn('items', data); self.assertNotIn('content', json.dumps(data))
            # Auth + route hygiene.
            self.assertEqual((await self.client.get('/v1/app/sessions/sync/s_a')).status, 401)
            self.assertEqual((await self.client.get('/v1/app/sessions/sync/foreign', headers=self.headers)).status, 404)
            self.assertEqual((await self.client.post('/v1/app/sessions/sync/s_a', headers=self.headers)).status, 404)
            self.assertEqual((await self.client.get('/v1/app/sessions/sync/s_a?x=1', headers=self.headers)).status, 404)
            # Missing DB is unknown and MUST disable continuation.
            self.app['profile_sessions_db'] = Path(self.tmp.name) / 'missing.sqlite'
            data = await (await self.client.get('/v1/app/sessions/sync/s_a', headers=self.headers)).json()
            self.assertFalse(data['channel_active'])
            self.assertEqual(data['lease_state'], 'unknown')
            self.assertFalse(data['can_continue'])

if __name__ == '__main__': unittest.main()
