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
    # Force-clear ANY remaining ClaudeBarMonitor process, not just the
    # LaunchAgent — e.g. a manual `swift run` debug build (.build/.../debug or
    # release). Two instances fight over the single Control Strip slot and the
    # Touch Bar item flickers / falls back to the coin GIF. The single-instance
    # flock only blocks instances started AFTER one holds the lock, so a stray
    # already-running copy must be killed here.
    #
    # Match the executable PATH ending in "/$BIN_NAME" (the launched binary is
    # always invoked by full path with no trailing args), NOT a loose substring:
    # the repo dir is "ClaudeBar_Monitor" (underscore) while the binary is
    # "ClaudeBarMonitor" (no underscore), so an anchored "/ClaudeBarMonitor$"
    # can't match this script's own cmdline or the repo path. ($ end-anchor,
    # not \b — BSD pgrep/pkill regex does not honor \b.) We're inside install
    # (about to (re)install), so no instance here is worth keeping alive.
    pkill -f "/$BIN_NAME\$" 2>/dev/null || true
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

    # Re-sign the COPY. The release binary is ad-hoc (linker-signed); copying it
    # to a new path invalidates that signature under launchd's stricter check,
    # so the agent is killed with OS_REASON_CODESIGNING even though the same
    # binary runs fine in the foreground. A fresh ad-hoc signature on the
    # installed copy fixes it.
    codesign --force --sign - "$INSTALL_DIR/$BIN_NAME" >/dev/null 2>&1 || \
        echo "    WARN: codesign failed; agent may be killed (OS_REASON_CODESIGNING)." >&2

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
