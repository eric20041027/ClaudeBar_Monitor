#!/usr/bin/env bash
#
# install.sh — build ClaudeBar Monitor (release) and install it as a
# per-user LaunchAgent so it starts automatically at login and stays in
# the background showing Claude usage on the Touch Bar.
#
# Usage:
#   ./install.sh            # build + (re)install + (re)start
#   ./install.sh uninstall  # stop the agent and remove all installed files
#
set -euo pipefail

LABEL="com.ericlin.claudebarmonitor"
UID_NUM="$(id -u)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/ClaudeBarMonitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ClaudeBarMonitor.log"
BIN_NAME="ClaudeBarMonitor"
BUNDLE_NAME="ClaudeBarMonitor_ClaudeBarMonitor.bundle"

stop_agent() {
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
}

uninstall() {
    echo "==> Stopping and removing ClaudeBar Monitor"
    stop_agent
    rm -f "$PLIST"
    rm -rf "$INSTALL_DIR"
    echo "    Removed LaunchAgent, installed binary, and resource bundle."
    echo "    (Log left in place: $LOG)"
}

install() {
    echo "==> Building release binary"
    cd "$REPO_DIR"
    swift build -c release

    local src="$REPO_DIR/.build/release"
    if [[ ! -x "$src/$BIN_NAME" ]]; then
        echo "ERROR: release binary not found at $src/$BIN_NAME" >&2
        exit 1
    fi

    echo "==> Installing to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    # Stop the running copy before overwriting the binary it holds open.
    stop_agent
    cp -f "$src/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
    # The release build emits a resource bundle next to the binary
    # (holds token-frames/token.gif). It must sit beside the binary.
    if [[ -d "$src/$BUNDLE_NAME" ]]; then
        rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
        cp -R "$src/$BUNDLE_NAME" "$INSTALL_DIR/"
    fi

    echo "==> Writing LaunchAgent plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$BIN_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST_EOF

    echo "==> Loading and starting the agent"
    launchctl bootstrap "gui/$UID_NUM" "$PLIST"
    launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    launchctl kickstart -k "gui/$UID_NUM/$LABEL" 2>/dev/null || true

    sleep 1
    if launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | grep -q "state = running"; then
        echo "==> Done. ClaudeBar Monitor is running and will start at every login."
    else
        echo "==> Installed, but the service is not reporting 'running'. Check $LOG"
    fi
}

case "${1:-install}" in
    uninstall|remove) uninstall ;;
    *) install ;;
esac
