"""Smoke test for a csmserve launcher. Usage: python tests/smoke.py <launcher> [launcher args...]
Exercises run / ingest / api / status / restart / stop against a live server."""
import json, os, subprocess, sys, time, urllib.request

LAUNCH = sys.argv[1:]
PORT = os.environ.setdefault("CSM_PORT", "8791")
BASE = "http://127.0.0.1:%s" % PORT


def csm(*a):
    r = subprocess.run(LAUNCH + list(a), capture_output=True, text=True, timeout=60)
    print("$ csmserve %s -> rc=%d\n%s%s" % (" ".join(a), r.returncode, r.stdout, r.stderr))
    return r


def get(path):
    return urllib.request.urlopen(BASE + path, timeout=5).read().decode()


def check(cond, msg):
    if not cond:
        print("FAIL:", msg)
        try:
            print(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "server.log")).read())
        except OSError:
            pass
        csm("stop")
        sys.exit(1)
    print("ok:", msg)


check(csm("status").returncode == 1, "status reports not running initially")
check(csm("run").returncode == 0, "run starts the server")
check("Already running" in csm("run").stdout, "second run is a no-op")
check(get("/") .lstrip().lower().startswith("<!doctype html"), "GET / serves index.html")
snap = json.dumps({"time": "t", "currencies": [], "pairs": []}).encode()
req = urllib.request.Request(BASE + "/ingest", data=snap, method="POST")
check(urllib.request.urlopen(req, timeout=5).status == 200, "POST /ingest accepted")
check(json.loads(get("/api"))["time"] == "t", "GET /api returns ingested snapshot")
check(csm("status").returncode == 0, "status reports running")
check(csm("restart").returncode == 0, "restart works")
check(csm("stop").returncode == 0, "stop works")
time.sleep(1)
check(csm("status").returncode == 1, "status reports stopped after stop")
print("ALL PASSED")
