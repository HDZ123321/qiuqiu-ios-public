"""App-owned run registry history route: metadata only, paginated, read-only.

Never returns run output, prompts or conversation content; those stay behind
the existing per-run ownership checks. Registry belongs to this restricted
proxy boundary, not the native global history (which has no list endpoint).
"""
import importlib.util
import pathlib
import tempfile
import unittest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

spec = importlib.util.spec_from_file_location('restricted_proxy', pathlib.Path(__file__).with_name('restricted_proxy.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


def make_app(registry_path, key='fixture-only'):
    app = web.Application()
    app['app_key'] = key
    app['registry'] = proxy.Registry(registry_path)
    app.router.add_route('*', '/{tail:.*}', proxy.handle)
    return app


class RegistryHistory(unittest.TestCase):
    def test_registry_records_created_at_and_paginates_newest_first(self):
        with tempfile.TemporaryDirectory() as d:
            registry = proxy.Registry(pathlib.Path(d) / 'runs.sqlite')
            for run in ('run_old', 'run_mid', 'run_new'):
                registry.remember(run, 'session-' + run)
            page = registry.history(limit=2)
            self.assertEqual([r['run_id'] for r in page['items']], ['run_new', 'run_mid'])
            self.assertEqual(page['next_cursor'], 2)
            older = registry.history(limit=2, before=page['next_cursor'])
            self.assertEqual([r['run_id'] for r in older['items']], ['run_old'])
            self.assertIsNone(older['next_cursor'])
            for item in page['items'] + older['items']:
                self.assertEqual(set(item), {'run_id', 'session', 'created_seq'})

    def test_registry_output_never_enters_history_payload(self):
        with tempfile.TemporaryDirectory() as d:
            registry = proxy.Registry(pathlib.Path(d) / 'runs.sqlite')
            registry.remember('run_a', 'session_a')
            page = registry.history(limit=10)
            self.assertNotIn('output', str(page))
            self.assertNotIn('input', str(page))


class RegistryHistoryHTTP(unittest.IsolatedAsyncioTestCase):
    async def test_history_requires_auth_and_is_metadata_only(self):
        with tempfile.TemporaryDirectory() as d:
            app = make_app(pathlib.Path(d) / 'runs.sqlite')
            async with TestClient(TestServer(app)) as client:
                self.assertEqual((await client.get('/v1/app/runs')).status, 401)
                self.assertEqual((await client.get('/v1/app/runs?admin=1', headers={'Authorization': 'Bearer fixture-only'})).status, 404)
                self.assertEqual((await client.post('/v1/app/runs', headers={'Authorization': 'Bearer fixture-only'})).status, 404)
                headers = {'Authorization': 'Bearer fixture-only'}
                app['registry'].remember('run_x', 'session_x')
                response = await client.get('/v1/app/runs?limit=1', headers=headers)
                self.assertEqual(response.status, 200)
                page = await response.json()
                self.assertEqual(page['items'][0]['run_id'], 'run_x')
                self.assertEqual(page['items'][0]['session'], 'session_x')
                self.assertEqual(response.headers.get('Cache-Control'), 'no-store')
                self.assertEqual((await client.get('/v1/app/runs?limit=999', headers=headers)).status, 400)
                self.assertEqual((await client.get('/v1/app/runs?limit=nope', headers=headers)).status, 400)
                self.assertEqual((await client.get('/v1/app/runs?before=-1', headers=headers)).status, 400)
                self.assertIsNone(page['next_cursor'])


if __name__ == '__main__':
    unittest.main()
