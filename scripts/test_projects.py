"""Synthetic project scopes, no native/model or user data."""
import tempfile, unittest
from pathlib import Path
from aiohttp import web
from restricted_proxy import Registry

class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.root=Path(self.tmp.name); self.root.chmod(0o700)
        self.registry=Registry(':memory:')
    def tearDown(self): self.tmp.cleanup()
    def test_project_creation_preserves_legacy_and_hides_siblings(self):
        from project_bridge import Projects
        from workspace_bridge import Workspace
        (self.root/'legacy.txt').write_text('legacy')
        projects=Projects(self.root,self.registry.db)
        a=projects.create('研究 A'); b=projects.create('研究 B')
        self.assertNotEqual(a['id'], b['id'])
        with_scope=projects.workspace(a['id'])
        with_scope.content('report.txt','POST',b'one')
        self.assertEqual(projects.workspace('default').listing('')['entries'][0]['name'],'legacy.txt')
        self.assertEqual(projects.workspace(b['id']).listing('')['entries'],[])
        self.assertEqual(projects.listing()[0],{'id':'default','name':'默认工作区'})
        self.assertEqual((self.root/'legacy.txt').read_text(),'legacy')
        projects.close()

    def test_invalid_names_ids_and_symlinks_rejected(self):
        from project_bridge import Projects
        projects=Projects(self.root,self.registry.db)
        for name in ['../x','.hidden','a/b','a\\b','a%2fb','\u202ehidden','', 'x'*61]:
            with self.assertRaises(web.HTTPBadRequest): projects.create(name)
        a=projects.create('Cafe\u0301')
        self.assertEqual(a['name'],'Café')
        with self.assertRaises(web.HTTPConflict): projects.create('Café')
        for key in ['../x','.projects','/etc',None,'p_'+'f'*32]:
            with self.assertRaises(web.HTTPNotFound): projects.workspace(key)
        folder=self.root/'.projects'/a['id']; folder.rmdir(); folder.symlink_to(self.root,target_is_directory=True)
        with self.assertRaises((ValueError,OSError)): projects.workspace(a['id'])
        projects.close()
    def test_immutable_request_scope_and_run_binding(self):
        from project_bridge import Projects
        projects=Projects(self.root,self.registry.db)
        a=projects.create('A')['id']; b=projects.create('B')['id']
        projects.reserve('retry-key',a,b'original')
        projects.reserve('retry-key',a,b'original')
        with self.assertRaises(web.HTTPConflict): projects.reserve('retry-key',b,b'original')
        with self.assertRaises(web.HTTPConflict): projects.reserve('retry-key',a,b'changed')
        projects.remember('run_one','retry-key')
        self.assertEqual(projects.for_run('run_one').root,projects.workspace(a).root)
        self.assertEqual(projects.for_run('run_legacy').root,self.root)
        self.assertFalse(projects.accepts(self.root/'legacy.txt',a))
        self.assertFalse(projects.accepts(projects.workspace(b).root/'other.txt',a))
        self.assertFalse(projects.accepts(projects.workspace(a).root/'other.txt','default'))
        self.assertTrue(projects.accepts(projects.workspace(a).root/'report.txt',a))
        projects.close()

if __name__=='__main__': unittest.main()
