"""Loopback-only synthetic reply UI service; no model/native state or real keys."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import base64
import zlib
import struct
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
width,height=320,180
pixels=b''.join(b'\x00'+b''.join(bytes((35 if x<160 else 225,110 if y<90 else 180,190)) for x in range(width)) for y in range(height))
PNG=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
IMAGE='a'*64
FILE='b'*64
DOC='c'*64
status='waiting_for_approval'
quote_output='NO QUOTE REQUEST RECEIVED'
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def reply(self,code,value,mime='application/json'):
        data=json.dumps(value).encode() if mime=='application/json' else value
        self.send_response(code); self.send_header('Content-Type',mime); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if self.path=='/ready': return self.reply(200,{})
        if self.headers.get('Authorization')!='Bearer synthetic-fixture-only': return self.reply(401,{})
        if self.path=='/v1/app/artifacts/run_empty': return self.reply(200,{'items':[]})
        if self.path=='/v1/app/artifacts/run_error': return self.reply(403,{})
        if self.path in ['/v1/app/artifacts/run_files','/v1/app/artifacts/run_long']:
            name=('研究报告与项目说明'*12+'.md') if self.path.endswith('run_long') else 'second-report.md'
            image={'id':IMAGE,'name':'generated.png','mime':'image/png'}
            return self.reply(200,{'items':[image,{'id':FILE,'name':'generated.txt','mime':'text/plain'},{'id':DOC,'name':name,'mime':'text/markdown'},image]})
        if self.path.endswith('/'+DOC): return self.reply(200,b'# Second synthetic document\nNo user data.','text/markdown')
        if self.path=='/v1/app/artifacts/run_fixture': return self.reply(200,{'items':[{'id':IMAGE,'name':'generated.png','mime':'image/png'},{'id':FILE,'name':'generated.txt','mime':'text/plain'}]})
        if self.path.endswith('/'+IMAGE): return self.reply(200,PNG,'image/png')
        if self.path.endswith('/'+FILE): return self.reply(200,b'Generated downloadable document fixture.\nExact bytes verified.','text/plain')
        if self.path=='/v1/runs/run_quote_fixture': return self.reply(200,{'run_id':'run_quote_fixture','status':'completed','session_id':'quote_session','output':quote_output})
        if self.path=='/v1/runs/run_fixture': return self.reply(200,{'run_id':'run_fixture','status':status,'approval':{'request_id':'request_fixture','command':'Synthetic operation only: create a sample report','choices':['once','deny']}})
        return self.reply(404,{})
    def do_POST(self):
        global status, quote_output
        data=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or '{}')
        if self.headers.get('Authorization')!='Bearer synthetic-fixture-only': return self.reply(401,{})
        if self.path=='/v1/runs' and isinstance(data.get('input'),str):
            quoted=data['input']
            valid='引用消息（' in quoted and 'Generated reply' in quoted and 'manual synthetic reply' in quoted and 'MEDIA:' not in quoted
            quote_output='QUOTE PAYLOAD VERIFIED' if valid else 'QUOTE PAYLOAD INVALID'
            return self.reply(200,{'run_id':'run_quote_fixture','status':'completed','session_id':'quote_session','output':quote_output})
        if self.path=='/v1/runs/run_fixture/approval' and data.get('request_id')=='request_fixture' and data.get('choice') in ['once','deny'] and set(data)=={'request_id','choice'}:
            status='completed'; return self.reply(200,{'resolved':1})
        return self.reply(400,{})
ThreadingHTTPServer(('127.0.0.1',18766),Handler).serve_forever()
