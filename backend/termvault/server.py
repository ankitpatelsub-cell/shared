#!/usr/bin/env python3
"""Minimal zero-knowledge TermVault sync API using only Python stdlib."""

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("TERMVAULT_DB", "/data/termvault.sqlite3")
MAX_BODY = 12 * 1024 * 1024
SESSION_SECONDS = 30 * 24 * 60 * 60


def connect():
    db = sqlite3.connect(DB_PATH, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA journal_mode=WAL")
    return db


def initialize():
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    with connect() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE,
          password_salt TEXT NOT NULL, password_hash TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
          token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS vaults (
          user_id TEXT PRIMARY KEY, revision INTEGER NOT NULL DEFAULT 0,
          salt TEXT, nonce TEXT, ciphertext TEXT, updated_at INTEGER,
          FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        """)


def password_hash(password, salt):
    return base64.b64encode(hashlib.scrypt(
        password.encode(), salt=base64.b64decode(salt), n=2**15, r=8, p=1,
        maxmem=64 * 1024 * 1024
    )).decode()


def issue_token(db, user_id):
    token = secrets.token_urlsafe(32)
    digest = hashlib.sha256(token.encode()).hexdigest()
    db.execute("DELETE FROM sessions WHERE expires_at < ?", (int(time.time()),))
    db.execute("INSERT INTO sessions VALUES (?, ?, ?)",
               (digest, user_id, int(time.time()) + SESSION_SECONDS))
    return token


class Handler(BaseHTTPRequestHandler):
    server_version = "TermVault/1"

    def log_message(self, fmt, *args):
        print(json.dumps({"time": int(time.time()), "message": fmt % args}))

    def response(self, status, payload):
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BODY:
            raise ValueError("invalid request size")
        return json.loads(self.rfile.read(length))

    def user_id(self, db):
        value = self.headers.get("Authorization", "")
        if not value.startswith("Bearer "):
            return None
        digest = hashlib.sha256(value[7:].encode()).hexdigest()
        row = db.execute(
            "SELECT user_id FROM sessions WHERE token_hash=? AND expires_at>?",
            (digest, int(time.time())),
        ).fetchone()
        return row["user_id"] if row else None

    def do_GET(self):
        if self.path == "/health":
            return self.response(HTTPStatus.OK, {"status": "ok"})
        if self.path != "/v1/vault":
            return self.response(HTTPStatus.NOT_FOUND, {"error": "not_found"})
        with connect() as db:
            user_id = self.user_id(db)
            if not user_id:
                return self.response(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            row = db.execute("SELECT * FROM vaults WHERE user_id=?", (user_id,)).fetchone()
            if not row or row["ciphertext"] is None:
                return self.response(HTTPStatus.OK, {"revision": 0, "vault": None})
            return self.response(HTTPStatus.OK, {"revision": row["revision"], "vault": {
                "salt": row["salt"], "nonce": row["nonce"],
                "ciphertext": row["ciphertext"], "updatedAt": row["updated_at"]
            }})

    def do_POST(self):
        try:
            body = self.body()
            if self.path in ("/v1/register", "/v1/login"):
                return self.auth(body, register=self.path.endswith("register"))
        except (ValueError, KeyError, json.JSONDecodeError) as error:
            return self.response(HTTPStatus.BAD_REQUEST, {"error": str(error)})
        return self.response(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def auth(self, body, register):
        email = body["email"].strip().lower()
        password = body["password"]
        if "@" not in email or len(password) < 12:
            return self.response(HTTPStatus.BAD_REQUEST, {"error": "invalid_credentials_format"})
        with connect() as db:
            row = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
            if register:
                if row:
                    return self.response(HTTPStatus.CONFLICT, {"error": "account_exists"})
                salt = base64.b64encode(os.urandom(16)).decode()
                user_id = secrets.token_hex(16)
                db.execute("INSERT INTO users VALUES (?, ?, ?, ?, ?)",
                           (user_id, email, salt, password_hash(password, salt), int(time.time())))
                db.execute("INSERT INTO vaults(user_id) VALUES (?)", (user_id,))
            else:
                if not row or not hmac.compare_digest(password_hash(password, row["password_salt"]), row["password_hash"]):
                    return self.response(HTTPStatus.UNAUTHORIZED, {"error": "invalid_credentials"})
                user_id = row["id"]
            token = issue_token(db, user_id)
            db.commit()
            return self.response(HTTPStatus.OK, {"token": token, "expiresIn": SESSION_SECONDS})

    def do_PUT(self):
        if self.path != "/v1/vault":
            return self.response(HTTPStatus.NOT_FOUND, {"error": "not_found"})
        try:
            body = self.body()
            revision = int(body["revision"])
            vault = body["vault"]
            for key in ("salt", "nonce"):
                base64.b64decode(vault[key], validate=True)
            if not isinstance(vault["ciphertext"], str) or len(vault["ciphertext"]) > MAX_BODY:
                raise ValueError("invalid ciphertext")
        except (ValueError, KeyError, json.JSONDecodeError):
            return self.response(HTTPStatus.BAD_REQUEST, {"error": "invalid_vault"})
        with connect() as db:
            user_id = self.user_id(db)
            if not user_id:
                return self.response(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            current = db.execute("SELECT revision FROM vaults WHERE user_id=?", (user_id,)).fetchone()[0]
            if revision != current:
                return self.response(HTTPStatus.CONFLICT, {"error": "revision_conflict", "revision": current})
            new_revision = current + 1
            db.execute("UPDATE vaults SET revision=?,salt=?,nonce=?,ciphertext=?,updated_at=? WHERE user_id=?",
                       (new_revision, vault["salt"], vault["nonce"], vault["ciphertext"], int(time.time()), user_id))
            db.commit()
            return self.response(HTTPStatus.OK, {"revision": new_revision})


if __name__ == "__main__":
    initialize()
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8791"))), Handler).serve_forever()
