"""Restricted route policy tests; no credentials or native service needed."""
import importlib.util
import pathlib
import unittest
spec = importlib.util.spec_from_file_location('restricted_proxy', pathlib.Path(__file__).with_name('restricted_proxy.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

class Routes(unittest.TestCase):
    def test_minimal_routes(self):
        self.assertTrue(proxy.allowed('GET', '/v1/capabilities'))
        self.assertTrue(proxy.allowed('POST', '/v1/runs'))
        self.assertTrue(proxy.allowed('GET', '/v1/runs/run_abc/events'))
        self.assertTrue(proxy.allowed('POST', '/v1/runs/run_abc/approval'))
        for method, path in [('GET','/api/sessions'),('GET','/v1/runs'),('POST','/v1/runs/run_a/steer'),('GET','/v1/models?x=1'),('GET','/v1/runs/%2e%2e/events')]:
            self.assertFalse(proxy.allowed(method, path))
    def test_owner_registry_durable_and_session_isolation(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            db = proxy.Registry(pathlib.Path(d)/'owners.sqlite')
            self.assertFalse(db.owns('run_a'))
            db.remember('run_a', 'session_a')
            self.assertTrue(proxy.Registry(pathlib.Path(d)/'owners.sqlite').owns('run_a'))
            self.assertTrue(db.session('session_a'))
            self.assertFalse(db.session('private_other_session'))

if __name__ == '__main__': unittest.main()
