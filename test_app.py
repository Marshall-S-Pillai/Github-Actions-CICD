"""Unit tests for app.py."""

import unittest

from app import APP_VERSION, greet, health


class ApplicationTests(unittest.TestCase):
    def test_default_greeting(self):
        self.assertEqual(greet(), "Hello, GitHub Actions!")

    def test_custom_greeting(self):
        self.assertEqual(greet("HCLTech"), "Hello, HCLTech!")

    def test_blank_name_uses_default(self):
        self.assertEqual(greet("   "), "Hello, GitHub Actions!")

    def test_health_response(self):
        self.assertEqual(health(), {"status": "healthy", "version": APP_VERSION})


if __name__ == "__main__":
    unittest.main(verbosity=2)
