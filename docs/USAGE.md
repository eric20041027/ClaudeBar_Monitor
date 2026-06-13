# Usage

## Build

```bash
swift build              # debug build → .build/debug/ClaudeBarMonitor
swift build -c release   # optimized build → .build/release/ClaudeBarMonitor
```

## Run

```bash
./.build/debug/ClaudeBarMonitor
```

- Runs as a background `.accessory` agent — **no Dock icon, no menu bar item**, output appears only on the Touch Bar Control Strip.
- On first launch, macOS prompts for **Keychain access** ("Claude Safe Storage"). Approve it; the prompt does not reappear after that.
- It polls every **4 minutes** (within the 3–5 min range recommended to avoid tripping rate-limit protections).

## What you'll see

| Display | Meaning |
|---------|---------|
| `🤖 84%` | 84% of your 5-hour quota remaining. White = safe, yellow = 20–50%, red = under 20%. |
| `⚠️ 需登入` | Session expired / not logged in. **Tap it** to open the Claude app, log in, and it recovers on the next poll. |
| `🔌 離線` | No network / request timed out. |
| `⚠️ API` | The usage API returned an unexpected shape or status. |

## Stop

```bash
pkill -f ClaudeBarMonitor
```

## Run on login (LaunchAgent)

To start the monitor automatically at login, install a LaunchAgent.

1. Build a release binary and note its absolute path:

   ```bash
   swift build -c release
   echo "$(pwd)/.build/release/ClaudeBarMonitor"
   ```

2. Create `~/Library/LaunchAgents/com.claudebar.monitor.plist` (replace `ABSOLUTE_PATH` with the path printed above):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.claudebar.monitor</string>
       <key>ProgramArguments</key>
       <array>
           <string>ABSOLUTE_PATH</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   ```

3. Load it:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.claudebar.monitor.plist
   ```

To remove it:

```bash
launchctl unload ~/Library/LaunchAgents/com.claudebar.monitor.plist
rm ~/Library/LaunchAgents/com.claudebar.monitor.plist
```

> Note: a LaunchAgent-spawned process may re-trigger the Keychain prompt the first time, since it runs in a different context. Approve it once.

## Configuration

There is no config file. The poll interval is a constant (`pollInterval`) in
[`main.swift`](../Sources/ClaudeBarMonitor/main.swift); the color thresholds are in
[`StatusViewModel.swift`](../Sources/ClaudeBarMonitor/StatusViewModel.swift). Edit and rebuild to change them.
