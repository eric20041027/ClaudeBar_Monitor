# ClaudeBar Monitor

A lightweight macOS background agent that shows your remaining **Claude Pro** quota **and the running cost of your current Claude Code session** directly on the **Touch Bar Control Strip**.

> One Control Strip item with two faces: your remaining 5-hour usage window as `🤖 84%`, and — tap to toggle — the live cost of your active Claude Code session as `$12.34`. No browser, no proxy, no paid tools — a single native Swift binary that reads your already-logged-in Claude desktop session and your local Claude Code transcripts.

---

## Features

- **Native Touch Bar rendering** — places a live item into the Control Strip (always visible, no app switching).
- **Two faces, tap to toggle** — the 5-hour usage gauge and the current Claude Code **session cost**, in one Control Strip slot.
- **Real session cost** — reads the official per-session `estimated_cost_usd` Claude Code records locally, the same figure the cost-warning hook reports. Updates within ~30s of finishing a prompt (instant on tap).
- **Zero credentials to manage** — reuses the Claude **desktop app**'s existing local session. You never paste a token.
- **Color-coded states** — usage: white (safe) → yellow → red as quota drops; cost: orange (calm) → yellow (busy) → red (hot) as spend climbs.
- **Graceful failure** — shows `⚠️ 需登入` (tap to open Claude), `🔌 離線`, or `⚠️ API` instead of crashing; the cost face always shows the last good number, never a blank.
- **Single dependency-free binary** — pure Swift + system frameworks. No Python, no BetterTouchTool, no network proxy.

## How it works (one line)

> **Usage:** decrypt the Claude desktop app's local cookies → call Claude's internal usage API → render the remaining percentage.
> **Cost:** find the newest Claude Code transcript (the active session) → read its official cumulative cost from `~/.claude/metrics/costs.jsonl` → render `$x.xx`. Both paint onto the same Touch Bar item.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full data flow.

## Requirements

| | |
|---|---|
| Hardware | A Mac **with a Touch Bar** (Control Strip) |
| OS | macOS 12+ |
| Toolchain | Swift 5.9+ (`swift-tools-version:5.9`; builds fine on newer toolchains) |
| Account | The **Claude desktop app** installed and **logged in** |
| Cost face (optional) | **Claude Code** installed — the cost display reads its local transcripts under `~/.claude`. The usage gauge works without it. |

## Build & Run

```bash
git clone https://github.com/eric20041027/ClaudeBar_Monitor.git
cd ClaudeBar_Monitor
swift build
./.build/debug/ClaudeBarMonitor
```

The app runs as a background `.accessory` agent (no Dock icon). On first launch macOS will prompt for **Keychain access** to read the "Claude Safe Storage" key — this is required to decrypt the local session cookie. Approve it.

To build, install as a login LaunchAgent, and start it in one step, use the bundled script:

```bash
./install.sh            # build release + install + start the LaunchAgent
./install.sh uninstall  # stop and remove it
```

See [docs/USAGE.md](docs/USAGE.md#run-on-login-launchagent) for details.

## Status

| Layer | State |
|-------|-------|
| Cookie decryption | ✅ Verified |
| Usage API client | ✅ Verified |
| Status / color state machine | ✅ Implemented |
| Touch Bar Control Strip render | ✅ Verified on real hardware |
| Fault handling (login / offline / API) | ✅ Implemented |
| Session cost (official `costs.jsonl`) | ✅ Verified on real hardware |
| Tap-to-toggle usage ⇄ cost | ✅ Verified on real hardware |

## Security & Privacy

- The app **only reads** local files (your Claude cookies, and — for the cost face — your Claude Code transcripts under `~/.claude`) and makes **HTTPS GET** requests to `claude.ai` for usage only. Nothing is sent anywhere else; the cost face is entirely offline.
- No credentials are ever written to disk or logged. See [docs/SECURITY.md](docs/SECURITY.md).
- This project uses **undocumented/internal** Claude endpoints and macOS **private APIs** — see [Caveats](docs/ARCHITECTURE.md#caveats--risks).

## Disclaimer

This is an unofficial, personal tool. It relies on internal Claude APIs that carry no compatibility guarantee and may change or break at any time. Use at your own risk and within Anthropic's terms of service. Not affiliated with Anthropic.

## License

MIT — see [LICENSE](LICENSE).
