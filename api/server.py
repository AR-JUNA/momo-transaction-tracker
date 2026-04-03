"""
api/app.py
----------
I built this REST API using Python's built-in http.server module (no Flask,
no FastAPI) exactly as the assignment requires.

The API serves MoMo SMS transaction data parsed from modified_sms_v2.xml.
We protect every endpoint with HTTP Basic Authentication and we persist
all changes (POST, PUT, DELETE) to the cache JSON file on disk — so data
survives server restarts.

Endpoints I implemented:
  GET    /transactions          - list all transactions (with pagination)
  GET    /transactions/{id}     - get one transaction by ID
  POST   /transactions          - add a new transaction
  PUT    /transactions/{id}     - update an existing transaction
  DELETE /transactions/{id}     - delete a transaction
  GET    /health                - check the server is running

To run this server:
  python api/server.py

To test with curl (credentials: admin / momo2024):
  curl -u admin:momo2024 http://localhost:8000/transactions

"""

import sys
import os
import json
import re
import base64
import datetime
import signal
import time
import threading
from http.server        import HTTPServer, BaseHTTPRequestHandler
from urllib.parse       import urlparse, parse_qs

# I add the project root to the path so I can import my other modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from dsa.parse_xml      import load_or_parse
from dsa.dsa_search import build_lookup_dict, linear_search, dict_lookup


# ANSI colour codes — I use these to make the terminal output easier to read
class C:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    RED     = "\033[91m"
    BLUE    = "\033[94m"
    CYAN    = "\033[96m"
    MAGENTA = "\033[95m"
    WHITE   = "\033[97m"
    BG_DARK = "\033[48;5;235m"


# Configuration
HOST        = "0.0.0.0"
PORT        = 8000
API_VERSION = "v1"

# I store credentials here. In a real app I would use environment variables
# and hashed passwords — I explain this in the security section of the report.
VALID_USERS = {
    "admin": "momo2024",
    "viewer": "readonly1",
}

# File paths
HERE        = os.path.dirname(os.path.abspath(__file__))
ROOT        = os.path.join(HERE, "..")
XML_PATH    = os.path.join(ROOT, "modified_sms_v2.xml")
CACHE_PATH  = os.path.join(ROOT, "data", "transactions.json")

# I keep the next available ID in a global so POST requests get unique IDs
_next_id_lock = threading.Lock()


# Shared in-memory data store
# I load the data once when the server starts and keep it in RAM.
# Both the list (for iteration) and the dict (for fast lookup) are updated
# together whenever the data changes.

class DataStore:
    """
    We hold all transactions in two structures that stay in sync:
      - self.list  : ordered list used for pagination and iteration
      - self.index : dict {id -> transaction} used for O(1) lookups

    The key addition here is persistence. After every write operation
    (POST, PUT, DELETE) we call _persist() which rewrites the cache JSON
    file on disk. That means when the server restarts it loads the updated
    file and all changes are still there — nothing is lost.
    """

    def __init__(self):
        self.list:        list[dict]      = []
        self.index:       dict[int, dict] = {}
        self._next_id:    int             = 1
        self._cache_path: str | None      = None   # set during load()
        self._lock                        = threading.Lock()

    def load(self, transactions: list[dict], cache_path: str) -> None:
        """
        We load the initial dataset and remember the cache path so we can
        write back to it whenever the data changes.
        """
        with self._lock:
            self._cache_path = cache_path
            self.list        = transactions
            self.index       = build_lookup_dict(transactions)
            if transactions:
                self._next_id = max(t["id"] for t in transactions) + 1

    def _persist(self) -> None:
        """
        We write the current list back to the cache file on disk.

        We do an atomic write: first write to a .tmp file, then rename it
        over the real file. This way a crash mid-write never produces a
        corrupted cache file — either the old file is intact or the new one
        is complete. There is never a half-written state.

        We call this inside the lock, so the file always matches memory.
        If the write fails for any reason we print a warning but do not
        crash — the data is still correct in memory for this session.
        """
        if not self._cache_path:
            return
        try:
            os.makedirs(os.path.dirname(self._cache_path), exist_ok=True)
            tmp_path = self._cache_path + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(self.list, f, indent=2)
            os.replace(tmp_path, self._cache_path)   # atomic on all major OSes
        except Exception as exc:
            print(f"  [DataStore] WARNING: could not save changes to disk — {exc}")

    def get_all(self, page: int = 1, per_page: int = 50,
                txn_type: str = None) -> tuple[list, int]:
        """We return a paginated slice of transactions, optionally filtered by type."""
        with self._lock:
            data = self.list
            if txn_type:
                data = [t for t in data if t.get("type", "").upper() == txn_type.upper()]
            total = len(data)
            start = (page - 1) * per_page
            end   = start + per_page
            return data[start:end], total

    def get_one(self, txn_id: int) -> dict | None:
        """We find a single transaction by ID using the O(1) dict lookup."""
        with self._lock:
            return self.index.get(txn_id)

    def add(self, data: dict) -> dict:
        """
        We add a new transaction, assign the next available ID, stamp a
        created_at timestamp, then write to disk so this survives a restart.
        """
        with self._lock:
            data["id"]         = self._next_id
            data["created_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            self._next_id     += 1
            self.list.append(data)
            self.index[data["id"]] = data
            self._persist()   # ← write to disk immediately
            return data

    def update(self, txn_id: int, updates: dict) -> dict | None:
        """
        We apply a partial update to an existing transaction and write the
        change to disk so it is not lost on restart.
        """
        with self._lock:
            txn = self.index.get(txn_id)
            if txn is None:
                return None
            updates.pop("id", None)   # the ID can never change
            txn.update(updates)
            txn["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            self._persist()   # ← write to disk immediately
            return txn

    def delete(self, txn_id: int) -> bool:
        """
        We remove a transaction from both structures and write to disk so
        the deletion is still there when the server next starts.
        """
        with self._lock:
            txn = self.index.pop(txn_id, None)
            if txn is None:
                return False
            self.list = [t for t in self.list if t["id"] != txn_id]
            self._persist()   # ← write to disk immediately
            return True

    @property
    def count(self) -> int:
        return len(self.list)


# I create one global data store instance
store = DataStore()

# Request statistics — I count requests per method for the dashboard
class Stats:
    def __init__(self):
        self.total        = 0
        self.success      = 0
        self.auth_fail    = 0
        self.not_found    = 0
        self.errors       = 0
        self.by_method    = {"GET": 0, "POST": 0, "PUT": 0, "DELETE": 0}
        self.start_time   = time.time()
        self._lock        = threading.Lock()

    def record(self, method: str, status: int) -> None:
        with self._lock:
            self.total += 1
            self.by_method[method] = self.by_method.get(method, 0) + 1
            if status == 401:
                self.auth_fail += 1
            elif status == 404:
                self.not_found += 1
            elif status >= 500:
                self.errors += 1
            else:
                self.success += 1

    def uptime(self) -> str:
        secs = int(time.time() - self.start_time)
        h, r = divmod(secs, 3600)
        m, s = divmod(r, 60)
        return f"{h:02d}:{m:02d}:{s:02d}"


stats = Stats()


# Helper functions

def _log(method: str, path: str, status: int, extra: str = "") -> None:
    """
    I print a clean, colour-coded log line for every request.
    Green = success, Yellow = client error, Red = auth fail / server error.
    """
    now = datetime.datetime.now().strftime("%H:%M:%S")

    if status == 200 or status == 201:
        colour = C.GREEN
    elif status == 401 or status == 403:
        colour = C.RED
    elif status in (400, 404, 405):
        colour = C.YELLOW
    else:
        colour = C.MAGENTA

    method_display = {
        "GET":    f"{C.CYAN}GET   {C.RESET}",
        "POST":   f"{C.GREEN}POST  {C.RESET}",
        "PUT":    f"{C.YELLOW}PUT   {C.RESET}",
        "DELETE": f"{C.RED}DELETE{C.RESET}",
    }.get(method, f"{method:<6}")

    status_str = f"{colour}{C.BOLD}{status}{C.RESET}"
    extra_str  = f"  {C.DIM}{extra}{C.RESET}" if extra else ""

    print(f"  {C.DIM}{now}{C.RESET}  {method_display}  {path:<40} {status_str}{extra_str}")


def _json_response(handler, status: int, data: dict | list) -> None:
    """I send a JSON response with the correct Content-Type header."""
    body = json.dumps(data, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type",  "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("X-Powered-By", "MoMo Analytics API / Team Yellow")
    handler.end_headers()
    handler.wfile.write(body)


def _error(handler, status: int, message: str) -> None:
    """I send a standard error response."""
    _json_response(handler, status, {"error": message, "status": status})


def _check_auth(handler) -> tuple[bool, str | None]:
    """
    I check the Authorization header for Basic Auth credentials.
    I decode the base64-encoded 'username:password' string and
    check it against my VALID_USERS dictionary.

    Returns (True, username) if valid, or (False, None) if not.
    """
    auth_header = handler.headers.get("Authorization", "")

    if not auth_header.startswith("Basic "):
        return False, None

    try:
        # The header looks like: "Basic dXNlcjpwYXNz"
        # I decode the base64 part to get "username:password"
        encoded     = auth_header[6:]
        decoded     = base64.b64decode(encoded).decode("utf-8")
        username, password = decoded.split(":", 1)
    except Exception:
        return False, None

    if VALID_USERS.get(username) == password:
        return True, username

    return False, None


def _read_body(handler) -> dict | None:
    """I read and parse the JSON request body. Returns None if it is invalid."""
    length = int(handler.headers.get("Content-Length", 0))
    if length == 0:
        return {}
    try:
        raw  = handler.rfile.read(length)
        return json.loads(raw.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


