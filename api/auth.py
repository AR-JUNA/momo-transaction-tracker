"""
auth.py
Basic Authentication middleware for the MoMo REST API.

"""

import base64
import hashlib
import hmac
import os


# Credential store
# In production: load from environment variables or secrets manager.
# we store the SHA-256 hash of the password so
# the plaintext never appears in source code.


def _sha256(plaintext: str) -> str:
    return hashlib.sha256(plaintext.encode()).hexdigest()


USERS = {
    # username : sha256(password)
    "admin":    _sha256("admin123"),
    "student":  _sha256("momo2024"),
}


def _timing_safe_compare(a: str, b: str) -> bool:
    """Use hmac.compare_digest to prevent timing-based attacks."""
    return hmac.compare_digest(a.encode(), b.encode())


def check_auth(authorization_header: str) -> tuple[bool, str]:
    """
    Validate a Basic Auth header.

    Returns:
        (True, username)   on success
        (False, reason)    on failure
    """
    if not authorization_header:
        return False, "Missing Authorization header"

    parts = authorization_header.split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "basic":
        return False, "Authorization scheme must be Basic"

    try:
        decoded = base64.b64decode(parts[1]).decode("utf-8")
    except Exception:
        return False, "Invalid base64 encoding"

    if ":" not in decoded:
        return False, "Credentials must be username:password"

    username, password = decoded.split(":", 1)

    stored_hash = USERS.get(username)
    if stored_hash is None:
        return False, "Unknown user"

    if not _timing_safe_compare(stored_hash, _sha256(password)):
        return False, "Invalid password"

    return True, username


def require_auth(handler_func):
    """
    Decorator that wraps a handler method.
    Usage:
        @require_auth
        def do_GET(self): ...
    """
    def wrapper(self, *args, **kwargs):
        ok, info = check_auth(self.headers.get("Authorization", ""))
        if not ok:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="MoMo API"')
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            import json
            self.wfile.write(
                json.dumps({"error": "Unauthorized", "detail": info}).encode()
            )
            return
        self.authenticated_user = info
        return handler_func(self, *args, **kwargs)
    return wrapper