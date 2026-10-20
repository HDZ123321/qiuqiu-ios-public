"""Synthetic-only artifact boundary tests, never reads the real home."""
import tempfile
import unittest
from pathlib import Path
from aiohttp import web
import artifact_bridge as bridge

class Artifacts(unittest.TestCase):
    def test_only_explicit_workspace_media_references_are_deliverable(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()/'scope'; root.mkdir()
            good = root/'report.txt'; good.write_text('Generated fixture document')
            private = Path(d)/'secret.txt'; private.write_text('not public')
            (root/'escape.txt').symlink_to(private)
            text = f'MEDIA:{good}\nMEDIA:{private}\nMEDIA:{root}/escape.txt\nMEDIA:{root}/../secret.txt\nhttps://example.org/image.png'
            items = bridge.references(text,root)
            self.assertEqual([x.name for x in items], ['report.txt'])
            self.assertEqual(bridge.read(items[0],root),b'Generated fixture document')
    def test_root_ancestor_symlink_replacement_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            base=Path(d).resolve(); scope=base/'scope';scope.mkdir(); root=scope/'project';root.mkdir()
            (root/'one.txt').write_text('original')
            other=base/'other';other.mkdir();(other/'project').mkdir();(other/'project'/'one.txt').write_text('wrong')
            (root/'one.txt').unlink();root.rmdir();scope.rmdir();scope.symlink_to(other,target_is_directory=True)
            with self.assertRaises(web.HTTPNotFound):bridge.read(root/'one.txt',root)
    def test_hardlinked_file_is_not_a_deliverable_artifact(self):
        import os
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve(); (root/'one.txt').write_text('one')
            os.link(root/'one.txt',root/'two.txt')
            self.assertEqual(bridge.references(f'MEDIA:{root}/one.txt',root),[])
            with self.assertRaises(web.HTTPNotFound): bridge.read(root/'one.txt',root)
    def test_reference_recheck_rejects_symlink_replacement(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve(); p=root/'result.txt'; p.write_text('ok')
            item=bridge.references(f'MEDIA:{p}',root)[0]
            p.unlink(); p.symlink_to('/etc/hosts')
            with self.assertRaises(web.HTTPException): bridge.read(item,root)

if __name__ == '__main__': unittest.main()
