#!/usr/bin/env python3
"""Cross-platform control script for the CSM server (macOS, Linux, Windows). Stdlib only.

  python csmserve.py run|start|stop|restart|status|logs  [extra args passed to server.py]

Env: CSM_PORT (default 8765), CSM_HOST (default 0.0.0.0).
"""
import os, re, signal, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
IS_WIN = os.name == "nt"
PORT = int(os.environ.get("CSM_PORT", "8765"))
HOST = os.environ.get("CSM_HOST", "0.0.0.0")
LOG = os.path.join(HERE, "server.log")
PIDFILE = os.path.join(HERE, ".server.pid")
URL = "http://127.0.0.1:%d/" % PORT


def venv_python():
    for rel in (("Scripts", "python.exe"), ("bin", "python")):
        p = os.path.join(HERE, ".venv", *rel)
        if os.path.isfile(p):
            return p
    return sys.executable


def port_open():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=0.5):
            return True
    except OSError:
        return False


def _out(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def find_pid():
    """PID listening on PORT (works even if started outside this script)."""
    if IS_WIN:
        for line in _out(["netstat", "-ano", "-p", "TCP"]).splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[3].upper() == "LISTENING" and parts[1].endswith(":%d" % PORT):
                return int(parts[4])
    else:
        out = _out(["lsof", "-nP", "-tiTCP:%d" % PORT, "-sTCP:LISTEN"]).split()
        if out:
            return int(out[0])
        m = re.search(r"pid=(\d+)", _out(["ss", "-ltnpH", "sport = :%d" % PORT]))
        if m:
            return int(m.group(1))
        out = _out(["fuser", "%d/tcp" % PORT]).split()
        if out and out[0].isdigit():
            return int(out[0])
    # fall back to the pid we recorded when we started it
    try:
        with open(PIDFILE) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def cmd_run(extra):
    if port_open():
        print("Already running (pid %s) at %s" % (find_pid() or "?", URL))
        return 0
    args = [venv_python(), "-u", os.path.join(HERE, "server.py"), "--host", HOST, "--port", str(PORT)] + extra
    kw = {}
    if IS_WIN:
        kw["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000  # DETACHED | NEW_PROCESS_GROUP | NO_WINDOW
    else:
        kw["start_new_session"] = True
    with open(LOG, "wb") as log:
        p = subprocess.Popen(args, cwd=HERE, stdin=subprocess.DEVNULL, stdout=log, stderr=log, **kw)
    with open(PIDFILE, "w") as f:
        f.write(str(p.pid))
    for _ in range(60):
        time.sleep(0.25)
        if port_open():
            print("Started (pid %d) at %s" % (p.pid, URL))
            return 0
        if p.poll() is not None:
            break
    print("Failed to start (exit code %s). Last log lines:" % p.poll())
    cmd_tail(20, follow=False)
    return 1


def _kill(pid, force):
    if IS_WIN:
        subprocess.run(["taskkill", "/PID", str(pid), "/T"] + (["/F"] if force else []),
                       capture_output=True)
    else:
        try:
            os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
        except ProcessLookupError:
            pass


def cmd_stop():
    pid = find_pid() if port_open() else None
    if not pid:
        print("Not running.")
        _rm(PIDFILE)
        return 0
    _kill(pid, False)
    for _ in range(20):
        if not port_open():
            break
        time.sleep(0.3)
    if port_open():
        _kill(pid, True)
        time.sleep(0.5)
    _rm(PIDFILE)
    print("Stopped (pid %d)." % pid)
    return 0


def cmd_status():
    if port_open():
        print("Running (pid %s) at %s" % (find_pid() or "?", URL))
        return 0
    print("Not running.")
    return 1


def cmd_tail(n=20, follow=True):
    try:
        f = open(LOG, "rb")
    except OSError:
        print("No log file yet.")
        return 1
    with f:
        lines = f.read().decode("utf-8", "replace").splitlines()[-n:]
        for l in lines:
            print(l)
        if not follow:
            return 0
        try:
            while True:
                chunk = f.read()
                if chunk:
                    sys.stdout.write(chunk.decode("utf-8", "replace"))
                    sys.stdout.flush()
                else:
                    time.sleep(0.5)
        except KeyboardInterrupt:
            return 0


def _rm(p):
    try:
        os.remove(p)
    except OSError:
        pass


def main(argv):
    action = argv[0] if argv else ""
    extra = argv[1:]
    if action in ("run", "start"):
        return cmd_run(extra)
    if action == "stop":
        return cmd_stop()
    if action == "restart":
        cmd_stop()
        return cmd_run(extra)
    if action == "status":
        return cmd_status()
    if action == "logs":
        return cmd_tail()
    print("Usage: csmserve run|stop|restart|status|logs  (env CSM_PORT to change port, default 8765)")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
