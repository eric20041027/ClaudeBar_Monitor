# Tech Stack

Everything used by ClaudeBar Monitor, and why.

## Language & build

| Tool | Version | Why |
|------|---------|-----|
| Swift | 5.9+ | Native macOS, direct access to AppKit + Touch Bar APIs, single self-contained binary. `Package.swift` declares `swift-tools-version:5.9`; it builds on newer toolchains too. |
| Swift Package Manager | bundled | Command-line build (`swift build`) with no Xcode project required. |

## System frameworks (all built into macOS — no third-party packages)

| Framework | Used for |
|-----------|----------|
| **AppKit** | `NSApplication` background agent, `NSCustomTouchBarItem`, colors, and `NSImage`-based drawing for both faces (the coin gauge in `GaugeRenderer` and the pixel-engineer + `$x.xx` composite in `CostRenderer`, so cost never truncates in the narrow slot). |
| **NSTouchBar** (AppKit) | The single Control Strip item with two tap-toggled faces. |
| **CommonCrypto** | `CCKeyDerivationPBKDF` (PBKDF2-SHA1) and `CCCrypt` (AES-128-CBC) for cookie decryption. |
| **Security** | Keychain access (`SecItemCopyMatching`) to read the "Claude Safe Storage" passphrase. |
| **SQLite3** (`libsqlite3`) | Read the Chromium Cookies database directly, read-only. |
| **Foundation** | `URLSession` for the HTTPS request, `JSONDecoder`/`JSONSerialization`, `ISO8601DateFormatter`, and `FileHandle` to tail-read `costs.jsonl`. |
| **DFRFoundation** (private) | `DFRElementSetControlStripPresenceForIdentifier` to pin the item in the Control Strip. Loaded at runtime via `dlopen`/`dlsym`, never linked. |

**Zero external dependencies.** `Package.swift` declares only the `libsqlite3` system library link. There is no `Package.resolved` with third-party packages.

## Deliberately NOT used (and why)

The original plan considered several approaches that were dropped after verification:

| Considered | Dropped because |
|------------|-----------------|
| **Python helper script** | Swift's `URLSession` + `CommonCrypto` do the same job in-process. No second runtime to ship. |
| **BetterTouchTool (BTT)** | Paid dependency. A native `NSTouchBar` item removes it entirely. |
| **Proxyman / Charles proxy** | Was planned to sniff the desktop app's token. Unnecessary — the desktop app's cookies are decryptable locally, so no MITM proxy or trusted root cert is needed. |

This is the key simplification: **the entire credential problem collapses to "read a local SQLite file + one Keychain entry."**

## What each external system contributes

- **Claude desktop app** — owns the authenticated session (the Cookies DB + Keychain key). ClaudeBar Monitor is a read-only consumer of it.
- **claude.ai internal API** — the source of truth for usage numbers (`/organizations/{org}/usage`).
- **Claude Code local files** — the source of truth for session cost: `~/.claude/metrics/costs.jsonl` (official cumulative `estimated_cost_usd` per session) and `~/.claude/projects/**/*.jsonl` (transcripts; used to pick the active session and for the token-priced fallback). Read-only.
- **macOS Touch Bar / Control Strip** — the display surface.
