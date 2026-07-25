#!/bin/sh
set -eu

LABEL="io.github.remote-kbm.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f -- "$PLIST_PATH"

echo "remote-kbm automatic startup was removed."
echo "Dependencies and logs were kept under:"
echo "  $HOME/Library/Application Support/remote-kbm"
echo "  $HOME/Library/Logs/remote-kbm"
