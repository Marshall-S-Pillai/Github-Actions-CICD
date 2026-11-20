"""Unit tests for app.py."""

import json
import unittest
from urllib.request import urlopen
from threading import Thread
from http.server import ThreadingHTTPServer

from app import APP_VERSION, ApplicationHandler, greet, health


class ApplicationTests(unittest.TestCase):
    def test_default_greeting(self):
        self.assertEqual(greet(), "Hello, GitHub Actions!")

    def test_custom_greeting(self):
        self.assertEqual(greet("HCLTech"), "Hello, HCLTech!")

    def test_blank_name_uses_default(self):
        self.assertEqual(greet("   "), "Hello, GitHub Actions!")

    def test_health_response(self):
        self.assertEqual(health(), {"status": "healthy", "version": APP_VERSION})

    def test_health_http_endpoint(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), ApplicationHandler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urlopen(f"http://127.0.0.1:{server.server_port}/health") as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read()), health())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
