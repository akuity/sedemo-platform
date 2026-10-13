"""Stub HTTP server for verify_test.sh.

Serves files from a fixture root: a request for /a/b?x=y returns the file
<root>/a/b (query string ignored). If <root>/a/b.status exists, its content
is the HTTP status code. "/" is served from <root>/_root. Missing files
return 404. Binds to an ephemeral
port on 127.0.0.1 and writes the port number to <portfile>.

Usage: python3 stub_server.py <root> <portfile>
"""

import http.server
import os
import sys
import urllib.parse

ROOT = os.path.abspath(sys.argv[1])
PORTFILE = sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/":
            path = "/_root"
        target = os.path.abspath(os.path.join(ROOT, path.lstrip("/")))
        if not target.startswith(ROOT + os.sep) or not os.path.isfile(target):
            self.send_response(404)
            self.end_headers()
            return
        status = 200
        if os.path.isfile(target + ".status"):
            with open(target + ".status") as f:
                status = int(f.read().strip())
        with open(target, "rb") as f:
            body = f.read()
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(PORTFILE + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
os.rename(PORTFILE + ".tmp", PORTFILE)
server.serve_forever()
