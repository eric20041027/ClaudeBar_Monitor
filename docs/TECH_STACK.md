# Tech Stack

Everything used by ClaudeBar Monitor, and why.

## Language & build

| Tool | Version | Why |
|------|---------|-----|
| Swift | 6.x | Native macOS, direct access to AppKit + Touch Bar APIs, single self-contained binary. |
| Swift Package Manager | bundled | Command-line build (`swift build`) with no Xcode project required. |

## System frameworks (all built into macOS — no third-party packages)

| Framework | Used for |
|-----------|----------|
| **AppKit** | `NSApplication` background agent, `NSButton`/`NSCustomTouchBarItem`, colors. |
| **NSTouchBar** (AppKit) | The Control Strip item itself. |
| **CommonCrypto** | `CCKeyDerivationPBKDF` (PBKDF2-SHA1) and `CCCrypt` (AES-128-CBC) for cookie decryption. |
| **Security** | Keychain access (`SecItemCopyMatching`) to read the "Claude Safe Storage" passphrase. |
| **SQLite3** (`libsqlite3`) | Read the Chromium Cookies database directly, read-only. |
| **Foundation** | `URLSession` for the HTTPS request, `JSONDecoder`, `ISO8601DateFormatter`. |
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
- **claude.ai internal API** — the single source of truth for usage numbers (`/organizations/{org}/usage`).
- **macOS Touch Bar / Control Strip** — the display surface.
