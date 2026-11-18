#!/usr/bin/env bash
# One-line installer for Currency Strength Meter (CSM) dashboard.
#   curl -fsSL https://raw.githubusercontent.com/gtujan/currency_strength_meter/main/install.sh | bash
# Env overrides: CSM_REPO (owner/name), CSM_BRANCH, CSM_DIR, CSM_BIN, CSM_LOCAL_SRC (copy from a local dir)
set -euo pipefail

REPO="${CSM_REPO:-gtujan/currency_strength_meter}"
BRANCH="${CSM_BRANCH:-main}"
DIR="${CSM_DIR:-$HOME/currency_strength_meter}"
BIN="${CSM_BIN:-$HOME/.local/bin}"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Python 3.8+
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || die "python3 not found. Install it (macOS: xcode-select --install or brew install python; Debian/Ubuntu: apt install python3 python3-venv)."
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' || die "Python 3.8+ required (found $("$PY" -V 2>&1))."

# 2. Fetch project files (re-running updates code; .venv and logs are preserved)
mkdir -p "$DIR"
if [ -n "${CSM_LOCAL_SRC:-}" ]; then
  say "Copying project from $CSM_LOCAL_SRC to $DIR"
  tar -C "$CSM_LOCAL_SRC" --exclude=.venv --exclude=.git --exclude=.server.pid --exclude=server.log --exclude=__pycache__ --exclude=PROGRESS.md --exclude="JCP_*" -cf - . | tar -C "$DIR" -xf -
else
  [ "$REPO" != "gtujan/currency_strength_meter" ] || die "Set CSM_REPO=<github-owner>/<repo>, or edit REPO at the top of install.sh."
  command -v curl >/dev/null || die "curl not found."
  say "Downloading $REPO@$BRANCH into $DIR"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$DIR" --strip-components=1
fi

# 3. Virtualenv + dependencies
cd "$DIR"
vpy() { for c in .venv/bin/python .venv/Scripts/python.exe; do [ -x "$c" ] && { echo "$c"; return; }; done; }
if [ -z "$(vpy)" ]; then
  say "Creating virtualenv"
  "$PY" -m venv .venv || die "venv creation failed (Debian/Ubuntu: apt install python3-venv)."
fi
VPY="$(vpy)"
say "Installing dependencies"
"$VPY" -m pip install --quiet --upgrade pip
"$VPY" -m pip install --quiet -r requirements.txt
chmod +x csmserve

# 4. Put `csmserve` on PATH
mkdir -p "$BIN"
ln -sf "$DIR/csmserve" "$BIN/csmserve"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "Add to your shell profile:  export PATH=\"$BIN:\$PATH\"" ;;
esac

cat <<MSG

Installed in $DIR

  csmserve run       start the server  -> http://127.0.0.1:8765/
  csmserve stop|restart|status|logs

MT4 setup (once): copy CSMFeed.ex4 (precompiled, no compiling needed) from $DIR into
MQL4/Experts (MT4: File > Open Data Folder), restart MT4, attach CSMFeed to a chart, and allow
WebRequest for http://127.0.0.1:8765 (Tools > Options > Expert Advisors).
CSMFeed.mq4 is the source, only needed if you want to edit it.
MSG
