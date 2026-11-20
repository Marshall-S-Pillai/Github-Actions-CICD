"""Small dependency-free web application for the GitHub Actions CI/CD capstone."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_VERSION = "1.0.0"


def health() -> dict:
    """Return a simple health response."""
    return {"status": "healthy", "version": APP_VERSION}


def greet(name: str = "GitHub Actions") -> str:
    """Return a greeting for the supplied name."""
    clean_name = name.strip()
    if not clean_name:
        clean_name = "GitHub Actions"
    return f"Hello, {clean_name}!"


class ApplicationHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = json.dumps(health()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        elif self.path == "/":
            body = greet().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
        else:
            body = b'{"error":"not found"}'
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))


def main():
    parser = argparse.ArgumentParser(description="CI/CD demo web application")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), ApplicationHandler)
    print(f"Starting {APP_VERSION} on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
