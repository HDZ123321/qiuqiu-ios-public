"""Loopback SSE fixture: no credentials or external services."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain" if self.path == "/badtype" else "text/event-stream; charset=utf-8")
        self.end_headers()
        payload = ': ping\n\ndata: {"choices":[{"delta":{"content":"你好"}}]}\n\ndata: {"choices":[{"delta":{"content":"，球球🌕"}}]}\n\ndata: [DONE]\n\n'.encode()
        if self.path == "/runs": payload = 'event: tool.started\r\ndata: {"event":"tool.started","tool":"terminal"}\r\n\r\nevent: message.interim\ndata: {"event":"message.interim","text":"工作中"}\n\nevent: run.completed\ndata: {"event":"run.completed","output":"最终🌕"}\n\n'.encode()
        if self.path == "/empty": payload = b"data: [DONE]\n\n"
        if self.path == "/truncated": payload = payload.split(b"data: [DONE]")[0]
        if self.path == "/error": payload = b'event: error\ndata: {}\n\n'
        if self.path == "/crlf": payload = payload.replace(b"\n", b"\r\n")
        if self.path == "/slow": time.sleep(5)
        try:
            for b in payload:
                self.wfile.write(bytes([b])); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError): pass
        self.close_connection = True
ThreadingHTTPServer(("127.0.0.1", 18765), Handler).serve_forever()
