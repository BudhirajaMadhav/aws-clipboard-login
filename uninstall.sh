#!/bin/bash
# Remove the launchd agent and the ~/.local/bin symlinks. Leaves ~/.aws and
# ~/.clipboard-history alone.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
PLIST_DEST="$HOME/Library/LaunchAgents/com.user.clipboard-monitor.plist"

if [ -f "$PLIST_DEST" ]; then
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    echo "  removed $PLIST_DEST"
fi

for f in clipboard-monitor aws-from-clipboard aws-cred-process; do
    if [ -L "$BIN_DIR/$f" ]; then
        rm -f "$BIN_DIR/$f"
        echo "  removed $BIN_DIR/$f"
    elif [ -e "$BIN_DIR/$f" ]; then
        echo "  skipped $BIN_DIR/$f (not a symlink — leaving intact)"
    fi
done

echo ""
echo "✓ Uninstalled."
