#!/usr/bin/env python3
"""Print the SCRAM-SHA-256 verifier of a password read from stdin.

The monitoring role's password reaches the server only as this verifier (docs/specs/round-1.md#the-monitoring-role):
a failed CREATE ROLE is logged with its statement, and the server's log lands in the shared workspace. Usage:

    terraform -chdir=terraform/envs/dev output -raw obs_monitor_password | python3 sql/scram.py

The format is PostgreSQL's own (RFC 5803): SCRAM-SHA-256$<iterations>:<salt>$<StoredKey>:<ServerKey>.
"""
import base64
import hashlib
import hmac
import os
import sys

ITERATIONS = 4096  # PostgreSQL's default scram_iterations


def verifier(password: str, salt: bytes, iterations: int = ITERATIONS) -> str:
    salted = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    client_key = hmac.new(salted, b"Client Key", "sha256").digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted, b"Server Key", "sha256").digest()
    b64 = lambda raw: base64.b64encode(raw).decode("ascii")
    return f"SCRAM-SHA-256${iterations}:{b64(salt)}${b64(stored_key)}:{b64(server_key)}"


def main() -> int:
    password = sys.stdin.read().rstrip("\n")
    if not password.isascii() or not password.isalnum() or len(password) < 24:
        # Terraform generates 32 letters and digits; anything else would need SASLprep
        print("expected a password of at least 24 ASCII letters and digits on stdin", file=sys.stderr)
        return 1
    print(verifier(password, os.urandom(16)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
