"""Stub HTTP server for verify_test.sh.

Serves files from a fixture root: a request for /a/b?x=y returns the file
<root>/a/b (query string ignored). "/" is served from <root>/_root.
Missing files return 404.

Sidecar files next to a served file change the status code:
  <file>.status      fixed HTTP status code for every request
  <file>.error_rate  integer percent R: the n-th request (n = 0, 1, ...)
                     to that path returns 500 when (n * R) % 100 < R, else
                     200. Deterministic: exactly R% of any 100 consecutive
                     requests fail, spread evenly (R=20: every 5th; R=25:
                     every 4th; R=100: all; R=0: none).

Binds to an ephemeral port on 127.0.0.1 and writes it to <portfile>.

Usage: python3 stub_server.py <root> <portfile>
"""

import collections
import http.server
import os
import sys
import urllib.parse

ROOT = os.path.abspath(sys.argv[1])
PORTFILE = sys.argv[2]
COUNTS = collections.Counter()


def read_int(path):
    with open(path) as f:
        return int(f.read().strip())


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
            status = read_int(target + ".status")
        elif os.path.isfile(target + ".error_rate"):
            rate = read_int(target + ".error_rate")
            n = COUNTS[target]
            COUNTS[target] += 1
            if (n * rate) % 100 < rate:
                status = 500
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
