#!/usr/bin/env python3
"""
Local handoff rendezvous — the Mac is the backend (pure stdlib, no cloud).

Serves the Flutter web build AND holds scan sessions in memory, which is the
whole trick: the browser is then **same-origin** with the session API, so there
is no CORS to configure, no mixed-content block, and no cloud project. The
iPhone POSTs its scan over the LAN; it is a native app, so CORS never applies
to it either.

    python3 tools/handoff_server.py [--port 8080] [--root build/web]

Endpoints
    POST   /events           -> append analytics events (activation funnel)
    GET    /events            -> everything collected, newest last
    GET    /handoff/<CODE>   -> session JSON, or 404 if unknown
    POST   /handoff/<CODE>   -> store session JSON (the phone writes here)
    DELETE /handoff/<CODE>   -> drop the session
    everything else          -> static file from --root (the Flutter build)

Sessions live in memory only and expire; restarting the server clears them.
This is a test rig for a LAN you trust, not a production service — there is no
authentication beyond the pairing code, so do not run it on a public network.
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

SESSION_TTL_SECONDS = 900  # 15 minutes; a scan takes 2-3

_sessions = {}
_events = []          # القياس المحلّي — يكفي للتحقّق من القِمع قبل أي خلفية
_lock = threading.Lock()
EVENTS_CAP = 5000     # سقف كي لا تكبر جلسة طويلة بلا حدّ


def _prune(now=None):
    now = now or time.time()
    with _lock:
        for code in [c for c, (t, _) in _sessions.items()
                     if now - t > SESSION_TTL_SECONDS]:
            del _sessions[code]


def put_session(code, payload, now=None):
    _prune(now)
    with _lock:
        _sessions[code.upper()] = (now or time.time(), payload)


def get_session(code, now=None):
    _prune(now)
    with _lock:
        entry = _sessions.get(code.upper())
    return entry[1] if entry else None


def drop_session(code):
    with _lock:
        _sessions.pop(code.upper(), None)


def lan_ip():
    """Best-effort LAN address — what the phone must be pointed at."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no packet is sent; just picks the route
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Handler(SimpleHTTPRequestHandler):
    root = "build/web"

    def translate_path(self, path):
        rel = path.split("?", 1)[0].split("#", 1)[0].lstrip("/")
        root = os.path.realpath(Handler.root)
        index = os.path.join(root, "index.html")

        # Containment is checked explicitly against the resolved path rather
        # than by scrubbing the string: `..` segments, symlinks and encoded
        # variants all collapse under realpath, and anything landing outside
        # the build directory is refused rather than served.
        full = os.path.realpath(os.path.join(root, rel))
        if full != root and not full.startswith(root + os.sep):
            return index

        if not rel or os.path.isdir(full):
            return index
        # SPA fallback: GoRouter paths like /sandbox are not files on disk, so an
        # unknown extensionless path must serve index.html — otherwise reloading
        # the browser anywhere but the root 404s.
        if not os.path.exists(full) and not os.path.splitext(rel)[1]:
            return index
        return full

    # ---- session API ------------------------------------------------------

    def _code(self):
        parts = self.path.split("?", 1)[0].strip("/").split("/")
        return parts[1] if len(parts) >= 2 and parts[0] == "handoff" else None

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # Same-origin in the intended setup; sent anyway so a `flutter run -d
        # chrome` on a different port still works during development.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path.split("?", 1)[0].rstrip("/") == "/events":
            with _lock:
                return self._send_json(200, {"count": len(_events),
                                             "events": list(_events)})
        code = self._code()
        if code is None:
            return SimpleHTTPRequestHandler.do_GET(self)
        session = get_session(code)
        if session is None:
            return self._send_json(404, {"error": "unknown session"})
        return self._send_json(200, session)

    def do_POST(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path == "/events":
            length = int(self.headers.get("Content-Length") or 0)
            try:
                payload = json.loads(self.rfile.read(length).decode() or "{}")
            except json.JSONDecodeError:
                return self._send_json(400, {"error": "malformed json"})
            batch = payload.get("events") or []
            with _lock:
                _events.extend(batch)
                if len(_events) > EVENTS_CAP:
                    del _events[: len(_events) - EVENTS_CAP]
                total = len(_events)
            for e in batch:
                print("  [event] %s" % e.get("name"))
            return self._send_json(200, {"ok": True, "stored": total})

        code = self._code()
        if code is None:
            return self._send_json(404, {"error": "not a session path"})
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            return self._send_json(400, {"error": "malformed json"})
        put_session(code, payload)
        print("  [handoff] %s <- %s" % (code.upper(), payload.get("status")))
        return self._send_json(200, {"ok": True})

    def do_DELETE(self):
        code = self._code()
        if code is None:
            return self._send_json(404, {"error": "not a session path"})
        drop_session(code)
        return self._send_json(200, {"ok": True})

    def log_message(self, *args):
        pass  # the session prints above are the only interesting traffic


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--root", default="build/web")
    args = ap.parse_args()
    Handler.root = args.root

    if not os.path.isdir(args.root):
        print("warning: %s does not exist — run `flutter build web` first."
              % args.root, file=sys.stderr)

    ip = lan_ip()
    print("Furn-App handoff rendezvous")
    print("  Mac browser : http://localhost:%d/" % args.port)
    print("  iPhone      : http://%s:%d/   <- enter this in the app" % (ip, args.port))
    print("  serving     : %s" % args.root)
    print("  events      : http://localhost:%d/events" % args.port)
    print()
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
