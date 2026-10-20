#!/usr/bin/env python3
"""openamigacurl host test: a local HTTPS server for the OpenTLS backend.

    tls_server.py PORT CERT KEY [tls12|tls13|tls13-notickets|http11]

POST answers the body's SHA-256 and length; GET /N answers N bytes; GET with
an X-Close header answers over HTTP/1.0 and closes TCP with no close_notify,
with X-Close-Notify the same after a close_notify.
"tls12" makes it speak TLS 1.2 at most; "tls13" makes it refuse anything
older than TLS 1.3 (OpenSSL sends two session tickets after each TLS 1.3
handshake); "tls13-notickets" is "tls13" that sends no tickets; "http11"
makes it answer ALPN with http/1.1 only (without it, the server ignores
ALPN). Without one it speaks TLS 1.2 and 1.3.
MIT, Copyright (c) 2026 AmigaChrome Team."""
import hashlib
import http.server
import socketserver
import ssl
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        left = int(self.headers["Content-Length"])
        h = hashlib.sha256()
        got = 0
        while got < left:
            b = self.rfile.read(min(65536, left - got))
            if not b:
                break
            h.update(b)
            got += len(b)
        body = ("%s %d\n" % (h.hexdigest(), got)).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        n = int(self.path.strip("/") or 0)
        notify = self.headers.get("X-Close-Notify")
        if self.headers.get("X-Close") or notify:
            self.protocol_version = "HTTP/1.0"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"x" * n)
            self.wfile.flush()
            if notify:
                try:
                    self.connection.unwrap()
                except (OSError, ValueError):
                    pass
            self.connection.shutdown(2)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(n))
        self.end_headers()
        self.wfile.write(b"y" * n)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    mode = sys.argv[4] if len(sys.argv) > 4 else ""
    if mode == "tls12":
        ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    elif mode in ("tls13", "tls13-notickets"):
        ctx.minimum_version = ssl.TLSVersion.TLSv1_3
        ctx.num_tickets = 0 if mode == "tls13-notickets" else 2
    elif mode == "http11":
        ctx.set_alpn_protocols(["http/1.1"])
    srv = Server(("127.0.0.1", port), Handler)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
