"""Exercise the production entrypoint with isolated config and native cron home."""
import os
import subprocess
import sys
import unittest
from pathlib import Path


class Startup(unittest.TestCase):
    def test_opt_in_entrypoint_initializes_all_scoped_bridges(self):
        script = r'''
import os, tempfile
from pathlib import Path
from unittest.mock import patch
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    os.environ['HERMES_HOME'] = str(root/'hermes')
    os.environ['QIUQIU_CONFIG_DIR'] = str(root)
    os.environ['QIUQIU_WORKSPACE_DIR'] = str(root/'workspace')
    os.environ['QIUQIU_ENABLE_CRON'] = '1'
    os.environ['QIUQIU_ENABLE_SESSIONS'] = '1'
    (root/'workspace').mkdir(mode=0o700)
    (root/'app-key').write_text('fixture-app')
    (root/'native-key').write_text('fixture-native')
    import restricted_proxy as proxy
    def verify(app, **kwargs):
        assert app['sessions_enabled'] is True
        assert app['cron_bridge'].listing() == {'jobs': []}
        assert app['registry'].history()['items'] == []
        assert app['workspace'].root == root/'workspace'
        assert kwargs['host'] == '127.0.0.1'
        assert kwargs['access_log'] is None
    with patch.object(proxy.web, 'run_app', side_effect=verify) as run:
        proxy.main()
        run.assert_called_once()
'''
        env = os.environ.copy()
        env['PYTHONPATH'] = os.pathsep.join([str(Path(__file__).parent), env['QIU_HERMES_SOURCE']])
        result = subprocess.run([sys.executable, '-c', script], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
