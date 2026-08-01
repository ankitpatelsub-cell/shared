import os
import tempfile
import unittest

tmp = tempfile.NamedTemporaryFile(delete=False)
os.environ["TERMVAULT_DB"] = tmp.name
import server


class VaultBackendTests(unittest.TestCase):
    def setUp(self):
        server.initialize()

    def test_password_hash_is_deterministic(self):
        salt = "MDEyMzQ1Njc4OWFiY2RlZg=="
        self.assertEqual(server.password_hash("long-test-password", salt),
                         server.password_hash("long-test-password", salt))

    def test_schema_exists(self):
        with server.connect() as db:
            names = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertTrue({"users", "sessions", "vaults"}.issubset(names))


if __name__ == "__main__":
    unittest.main()
