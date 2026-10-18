"""Chat attachment boundary regression: real bytes, no credentials/network required."""
import base64
import tempfile
import unittest
from pathlib import Path
from aiohttp import web
from workspace_bridge import Workspace
import restricted_proxy as proxy

class Attachments(unittest.TestCase):
    def test_image_bytes_reach_native_vision_parts(self):
        data = b'\x89PNG\r\n\x1a\n' + b'fixture'
        payload = {'input':'Describe this', 'attachments':[{'name':'photo.png','mime':'image/png','data':base64.b64encode(data).decode()}]}
        with tempfile.TemporaryDirectory() as root:
            Path(root).chmod(0o700)
            workspace = Workspace(Path(root).resolve())
            try:
                result = proxy.prepare_attachments(payload, workspace)
                parts = result['input'][0]['content']
                self.assertEqual(parts[0], {'type':'text','text':'Describe this'})
                self.assertEqual(base64.b64decode(parts[1]['image_url']['url'].split(',')[1]),data)
                self.assertNotIn('attachments',result)
            finally: workspace.close()

    def test_documents_are_scoped_content_addressed_and_retry_stable(self):
        data = b'actual document nonce'
        payload = {'input':'Read', 'attachments':[{'name':'note.txt','mime':'text/plain','data':base64.b64encode(data).decode()}]}
        with tempfile.TemporaryDirectory() as root:
            Path(root).chmod(0o700); workspace=Workspace(Path(root).resolve())
            try:
                first=proxy.prepare_attachments(payload,workspace)
                self.assertEqual(first,proxy.prepare_attachments(payload,workspace))
                files=list(Path(root).resolve().glob('attachment-*.txt'))
                self.assertEqual(len(files),1); self.assertEqual(files[0].read_bytes(),data)
                self.assertIn(str(files[0]),str(first))
                for name,mime,raw in [('../note.txt','text/plain',data),('fake.png','image/png',data),('code.py','text/plain',data),('note.txt','text/plain',b'\xff')]:
                    bad={'input':'Read','attachments':[{'name':name,'mime':mime,'data':base64.b64encode(raw).decode()}]}
                    with self.assertRaises(web.HTTPException): proxy.prepare_attachments(bad,workspace)
            finally: workspace.close()

if __name__ == '__main__': unittest.main()
