#!/usr/bin/env python3
"""Local server for CSMFeed. Stdlib only.

  POST /ingest   <- CSMFeed EA posts JSON snapshot
  GET  /stream   -> Server-Sent Events, one message per snapshot
  GET  /api      -> latest snapshot as JSON
  GET  /         -> index.html

Optional file-watch fallback:  python3 server.py --file "/path/to/MQL4/Files/csm_snapshot.json"
"""
import argparse, json, os, queue, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
latest = {"raw": None, "recv": 0.0}
clients = set()
lock = threading.Lock()


def publish(raw: str):
    try:
        json.loads(raw)
    except ValueError:
        return False
    with lock:
        latest["raw"], latest["recv"] = raw, time.time()
        for q in list(clients):
            try:
                q.put_nowait(raw)
            except queue.Full:
                pass
    return True


def watch_file(path):
    last = None
    while True:
        try:
            m = os.stat(path).st_mtime
            if m != last:
                last = m
                with open(path, encoding="utf-8", errors="ignore") as f:
                    publish(f.read().strip().lstrip("﻿"))
        except OSError:
            pass
        time.sleep(0.5)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/ingest":
            return self._send(404)
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode("utf-8", "ignore").strip().lstrip("﻿")
        self._send(200 if publish(raw) else 400, b"ok")

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if self.path == "/api":
            return self._send(200, (latest["raw"] or "{}").encode(), "application/json")
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            q = queue.Queue(maxsize=5)
            with lock:
                clients.add(q)
                if latest["raw"]:
                    q.put_nowait(latest["raw"])
            try:
                while True:
                    try:
                        raw = q.get(timeout=15)
                        self.wfile.write(f"data: {raw}\n\n".encode())
                    except queue.Empty:
                        self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                with lock:
                    clients.discard(q)
            return
        self._send(404)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--file", help="watch this snapshot file instead of/as well as HTTP ingest")
    a = ap.parse_args()
    if not a.file:
        import glob
        hits = glob.glob(os.path.expanduser(
            "~/Library/Application Support/CrossOver/Bottles/*/drive_c/users/*/AppData/Roaming/"
            "MetaQuotes/Terminal/*/MQL4/Files/csm_snapshot.json"))
        if hits:
            a.file = max(hits, key=os.path.getmtime)
            print("auto-detected snapshot file:", a.file)
    if a.file:
        threading.Thread(target=watch_file, args=(a.file,), daemon=True).start()
    srv = ThreadingHTTPServer((a.host, a.port), H)
    srv.daemon_threads = True
    print(f"CSM dashboard: http://{a.host}:{a.port}/")
    srv.serve_forever()
