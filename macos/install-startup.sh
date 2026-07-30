#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
PYTHON_BOOTSTRAP=${PYTHON_BOOTSTRAP:-python3}
LABEL="io.github.remote-kbm.agent"
DATA_DIR="$HOME/Library/Application Support/remote-kbm"
APP_DIR="$DATA_DIR/app"
VENV_DIR="$DATA_DIR/venv"
PYTHON_PATH="$VENV_DIR/bin/python"
SERVER_PATH="$APP_DIR/server/main.py"
REQUIREMENTS_PATH="$PROJECT_ROOT/requirements.txt"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/remote-kbm"
OUT_LOG="$LOG_DIR/server.log"
ERROR_LOG="$LOG_DIR/server-error.log"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "ERROR: This installer is for macOS. Run ./install.sh from the repository root." >&2
    exit 2
fi
if ! command -v "$PYTHON_BOOTSTRAP" >/dev/null 2>&1; then
    echo "ERROR: python3 was not found. Install Python 3.10 or newer, then retry." >&2
    exit 2
fi
if ! "$PYTHON_BOOTSTRAP" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
    echo "ERROR: Python 3.10 or newer is required." >&2
    exit 2
fi

mkdir -p "$DATA_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
if [ ! -x "$PYTHON_PATH" ]; then
    echo "Creating isolated environment at $VENV_DIR"
    "$PYTHON_BOOTSTRAP" -m venv "$VENV_DIR"
fi

echo "Installing remote-kbm dependencies..."
"$PYTHON_PATH" -m pip install --disable-pip-version-check -r "$REQUIREMENTS_PATH"
"$PYTHON_PATH" -c 'import aiohttp, pynput, qrcode'

mkdir -p "$APP_DIR/server" "$APP_DIR/client"
cp "$PROJECT_ROOT"/server/*.py "$APP_DIR/server/"
cp -R "$PROJECT_ROOT/client/." "$APP_DIR/client/"

"$PYTHON_PATH" - "$PLIST_PATH" "$LABEL" "$PYTHON_PATH" "$SERVER_PATH" \
    "$APP_DIR" "$OUT_LOG" "$ERROR_LOG" <<'PY'
import plistlib
import sys

plist_path, label, python_path, server_path, project_root, out_log, error_log = sys.argv[1:]
job = {
    "Label": label,
    "ProgramArguments": [python_path, server_path],
    "WorkingDirectory": project_root,
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "ThrottleInterval": 10,
    "ProcessType": "Background",
    "EnvironmentVariables": {"PYTHONUNBUFFERED": "1"},
    "StandardOutPath": out_log,
    "StandardErrorPath": error_log,
}
with open(plist_path, "wb") as stream:
    plistlib.dump(job, stream, sort_keys=False)
PY

plutil -lint "$PLIST_PATH"
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
launchctl enable "$DOMAIN/$LABEL"
launchctl kickstart -k "$DOMAIN/$LABEL"

echo
echo "remote-kbm startup is installed and launch was requested."
echo "Logs: $OUT_LOG"
echo "      $ERROR_LOG"
echo
echo "REQUIRED: In System Settings > Privacy & Security > Accessibility,"
echo "allow the Python interpreter used by remote-kbm:"
echo "  $PYTHON_PATH"
echo "After an update, fully close and reopen the phone app."
echo "Also allow incoming connections if the macOS firewall prompts."
"$PYTHON_PATH" "$SERVER_PATH" --show-connect
