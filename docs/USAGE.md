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
- It runs two pollers: the **usage** gauge refreshes every **4 minutes** (it calls the Claude API, so it stays infrequent to avoid rate limits), and the **session cost** refreshes every **30 seconds** (it only reads local files). **Tapping the item forces an immediate refresh of both.**

## What you'll see

The Control Strip item has **two faces** — **tap it to toggle** between the usage gauge and the session cost.

**Usage face:**

| Display | Meaning |
|---------|---------|
| `🤖 84%` | 84% of your 5-hour quota remaining. White = safe, yellow = 20–50%, red = under 20%. |
| `⚠️ 需登入` | Session expired / not logged in. **Tap it** to open the Claude app, log in, and it recovers on the next poll. |
| `🔌 離線` | No network / request timed out. |
| `⚠️ API` | The usage API returned an unexpected shape or status. |

**Cost face:**

| Display | Meaning |
|---------|---------|
| `$12.34` | Cumulative cost of your **active Claude Code session** — the one you most recently sent a prompt in. Orange = calm, yellow = busy, red = hot, as spend climbs. |

The cost is the official `estimated_cost_usd` Claude Code records locally (the same number its cost-warning hook reports). It updates within ~30s of finishing a prompt, or instantly if you tap. Switching which session is shown happens when you **send a prompt** in another session, not merely by clicking into it. If a read ever fails it keeps showing the last good number — the cost face never blanks or errors.

## Stop

```bash
pkill -f ClaudeBarMonitor
```

## Run on login (LaunchAgent)

The repo ships [`install.sh`](../install.sh), which builds a release binary, installs it to `~/Library/Application Support/ClaudeBarMonitor/`, writes the LaunchAgent plist (label `com.ericlin.claudebarmonitor`), and starts it — all in one step:

```bash
./install.sh            # build release + install + (re)start
./install.sh uninstall  # stop the agent and remove installed files
```

Re-run `./install.sh` after any code change: the LaunchAgent runs the **installed copy**, not your repo's `.build` output, so a rebuild alone won't take effect at login until you reinstall.

> Note: a LaunchAgent-spawned process may re-trigger the Keychain prompt the first time, since it runs in a different context. Approve it once.

What `install.sh` sets up, for reference:

| | |
|---|---|
| Label | `com.ericlin.claudebarmonitor` |
| Binary | `~/Library/Application Support/ClaudeBarMonitor/ClaudeBarMonitor` (+ its resource bundle) |
| Plist | `~/Library/LaunchAgents/com.ericlin.claudebarmonitor.plist` (`RunAtLoad` + `KeepAlive`) |
| Log | `~/Library/Logs/ClaudeBarMonitor.log` |

## Configuration

There is no config file. The poll intervals are constants in
[`main.swift`](../Sources/ClaudeBarMonitor/main.swift) — `usagePollInterval` (4 min, API) and `costPollInterval` (30 s, local files). The usage color thresholds are in
[`StatusViewModel.swift`](../Sources/ClaudeBarMonitor/StatusViewModel.swift); the cost color thresholds (`busyThreshold`, `hotThreshold`) are in
[`CostDisplay.swift`](../Sources/ClaudeBarMonitor/CostDisplay.swift). Edit and rebuild (then re-run `./install.sh`) to change them.
