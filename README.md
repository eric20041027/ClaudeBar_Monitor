# ClaudeBar Monitor

A lightweight macOS background agent that shows your remaining **Claude Pro** quota directly on the **Touch Bar Control Strip**.

> Displays your remaining 5-hour usage window as `🤖 84%`, refreshed every few minutes. No browser, no proxy, no paid tools — a single native Swift binary that reads your already-logged-in Claude desktop session.

---

## Features

- **Native Touch Bar rendering** — places a live item into the Control Strip (always visible, no app switching).
- **Zero credentials to manage** — reuses the Claude **desktop app**'s existing local session. You never paste a token.
- **Color-coded states** — white (safe) → yellow (warning) → red (danger) as your quota drops.
- **Graceful failure** — shows `⚠️ 需登入` (tap to open Claude), `🔌 離線`, or `⚠️ API` instead of crashing.
- **Single dependency-free binary** — pure Swift + system frameworks. No Python, no BetterTouchTool, no network proxy.

## How it works (one line)

> Decrypt the Claude desktop app's local cookies → call Claude's internal usage API → render the remaining percentage onto the Touch Bar.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full data flow.

## Requirements

| | |
|---|---|
| Hardware | A Mac **with a Touch Bar** (Control Strip) |
| OS | macOS 12+ |
| Toolchain | Swift 6.x (`swift --version`) |
| Account | The **Claude desktop app** installed and **logged in** |

## Build & Run

```bash
git clone https://github.com/eric20041027/ClaudeBar_Monitor.git
cd ClaudeBar_Monitor
swift build
./.build/debug/ClaudeBarMonitor
```

The app runs as a background `.accessory` agent (no Dock icon). On first launch macOS will prompt for **Keychain access** to read the "Claude Safe Storage" key — this is required to decrypt the local session cookie. Approve it.

To run it on login automatically, see [docs/USAGE.md](docs/USAGE.md#run-on-login-launchagent).

## Status

| Layer | State |
|-------|-------|
| Cookie decryption | ✅ Verified |
| Usage API client | ✅ Verified |
| Status / color state machine | ✅ Implemented |
| Touch Bar Control Strip render | ✅ Verified on real hardware |
| Fault handling (login / offline / API) | ✅ Implemented |

## Security & Privacy

- The app **only reads** your local Claude cookies and makes **one HTTPS GET** to `claude.ai` per poll. Nothing is sent anywhere else.
- No credentials are ever written to disk or logged. See [docs/SECURITY.md](docs/SECURITY.md).
- This project uses **undocumented/internal** Claude endpoints and macOS **private APIs** — see [Caveats](docs/ARCHITECTURE.md#caveats--risks).

## Disclaimer

This is an unofficial, personal tool. It relies on internal Claude APIs that carry no compatibility guarantee and may change or break at any time. Use at your own risk and within Anthropic's terms of service. Not affiliated with Anthropic.

## License

MIT — see [LICENSE](LICENSE).
