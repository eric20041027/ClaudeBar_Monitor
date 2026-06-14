# Architecture

ClaudeBar Monitor is a single native Swift executable. It has three logical layers — **credential**, **data**, and **render** — plus a small coordinator. There is no server, no database, and no external process.

It drives **one** Control Strip item with **two faces** (usage and cost) that the user toggles by tapping. The two faces are fed by two independent data paths on two independent timers.

## Data flow

```
┌──────────────────────────────────────────────────────────────────┐
│  macOS local machine                                               │
│                                                                    │
│  ── Usage path (every 4 min, hits the Claude API) ──────────────   │
│  ~/Library/Application Support/Claude/Cookies   (SQLite)           │
│        │  encrypted_value (AES-128-CBC, v10/v11 prefix)            │
│        ▼                                                           │
│  Keychain: "Claude Safe Storage" passphrase                        │
│        │  PBKDF2-SHA1(salt="saltysalt", iter=1003) → AES key       │
│        ▼                                                           │
│  CookieDecryptor → sessionKey + lastActiveOrg + cookie header      │
│        │   HTTPS GET   https://claude.ai/api/organizations/{org}/usage
│        ▼                                                           │
│  UsageClient → { five_hour.utilization, resets_at }                │
│        ▼                                                           │
│  StatusViewModel → "🤖 {100 − utilization}%" + color level         │
│        │                                                           │
│  ── Cost path (every 30 s, reads local files only) ─────────────   │
│  ~/.claude/projects/**/*.jsonl  →  newest-mtime = active session   │
│        │  (filename stem = session_id; observer-sessions excluded) │
│        ▼                                                           │
│  ~/.claude/metrics/costs.jsonl  →  latest estimated_cost_usd       │
│        │  for that session_id (tail-read; official cumulative cost)│
│        │  fallback: price the transcript's own tokens until the    │
│        │  session's first official cost line lands (ModelPricing)  │
│        ▼                                                           │
│  TranscriptCostProvider → Double  →  CostDisplay → "$x.xx" + level  │
│        │                                                           │
│        ▼                                                           │
│  TouchBarController → ONE Control Strip item, two faces            │
│        (tap toggles usage ⇄ cost; private DFR API)                 │
└──────────────────────────────────────────────────────────────────┘
```

## Components

| File | Responsibility |
|------|----------------|
| [`CookieDecryptor.swift`](../Sources/ClaudeBarMonitor/CookieDecryptor.swift) | Reads the Cookies SQLite DB, fetches the AES key from Keychain, decrypts `sessionKey` + `lastActiveOrg`, builds the cookie header. |
| [`UsageClient.swift`](../Sources/ClaudeBarMonitor/UsageClient.swift) | Makes the authenticated `GET .../usage` call, decodes the JSON into typed models, maps failures to a `UsageResult` enum. |
| [`StatusViewModel.swift`](../Sources/ClaudeBarMonitor/StatusViewModel.swift) | Pure mapping from `UsageResult` → display text + color level + tappable flag. No side effects. |
| [`CostProvider.swift`](../Sources/ClaudeBarMonitor/CostProvider.swift) | The `CostProviding` protocol (`currentSessionCost() -> Double`) plus a `DemoCostProvider` random walk used only for UI development. The UI depends on the protocol, never the source. |
| [`TranscriptCostProvider.swift`](../Sources/ClaudeBarMonitor/TranscriptCostProvider.swift) | The real `CostProviding`: picks the active session (newest-mtime `.jsonl`), reads its official cumulative `estimated_cost_usd` from `costs.jsonl` (tail-read), falls back to token pricing until that lands. Every failure returns the last good value. |
| [`ModelPricing.swift`](../Sources/ClaudeBarMonitor/ModelPricing.swift) | Per-model USD/1M token table + cache multipliers. Only used by the fallback path, since the transcript's own `costUSD` is null. |
| [`CostDisplay.swift`](../Sources/ClaudeBarMonitor/CostDisplay.swift) | Pure mapping from a cost `Double` → formatted `$x.xx` text + `CostLevel` (calm/busy/hot) color. No side effects. |
| [`CostRenderer.swift`](../Sources/ClaudeBarMonitor/CostRenderer.swift) | Paints one `NSImage` containing the pixel-engineer frame + `$x.xx` in monospaced digits, so the cost never truncates in the narrow Control Strip slot. |
| [`GaugeRenderer.swift`](../Sources/ClaudeBarMonitor/GaugeRenderer.swift) | Paints the usage face (coin gauge + percentage) into an `NSImage`. |
| [`TokenAnimation.swift`](../Sources/ClaudeBarMonitor/TokenAnimation.swift) | Loads animation frames from a GIF (`loadFrames(directory:gifName:)`) for the animated faces. |
| [`ControlStripPresence.swift`](../Sources/ClaudeBarMonitor/ControlStripPresence.swift) | Shared helper wrapping the private DFR Control-Strip-presence call behind `dlopen`/`dlsym` guards. |
| [`TouchBarController.swift`](../Sources/ClaudeBarMonitor/TouchBarController.swift) | Owns the single Control Strip item and its `Mode { .gauge, .cost }`. `handleTap` toggles the face (or opens Claude when login is needed); `update(_:)` / `updateCost(_:)` refresh each face. Wraps the private Touch Bar APIs behind crash-safe guards. |
| [`main.swift`](../Sources/ClaudeBarMonitor/main.swift) | `NSApplication` entry point. Sets `.accessory` policy, runs **two** timers — usage every 4 min (`refreshUsage`, API), cost every 30 s (`refreshCost`, local files) — and wires the tap handler, which forces an immediate refresh of both faces. |

## Credential decryption detail

The Claude desktop app is an Electron/Chromium app, so its cookie store uses the **standard Chromium macOS encryption scheme**:

1. A random passphrase is stored in the macOS Keychain under the service name `Claude Safe Storage`.
2. The AES key is derived: `PBKDF2-HMAC-SHA1(passphrase, salt="saltysalt", iterations=1003, keyLen=16)`.
3. Each `encrypted_value` is prefixed with `v10`/`v11`; the rest is AES-128-CBC with a 16-byte all-spaces IV and PKCS7 padding.
4. Electron additionally prepends a 32-byte domain hash to the plaintext, which is stripped to recover the cookie value.

These constants are public and identical across all Chromium-derived apps.

## The usage API

```http
GET https://claude.ai/api/organizations/{organizationId}/usage
Cookie: sessionKey=...; lastActiveOrg=...; cf_clearance=...; (all claude.ai cookies)
```

Response (relevant fields, values are illustrative placeholders):

```jsonc
{
  "five_hour": { "utilization": 16.0, "resets_at": "2026-01-01T00:00:00.000000+00:00" },
  "seven_day": { "utilization":  2.0, "resets_at": "2026-01-07T00:00:00.000000+00:00" }
}
```

- `utilization` is the percentage **already used** (0–100). Remaining = `100 − utilization`.
- `resets_at` is ISO-8601 **UTC** (with fractional seconds); convert to local time for display.
- `five_hour` corresponds to Claude's rolling 5-hour rate-limit window.

## Session cost

The cost face reports the running spend of the Claude Code session you are actively working in. It reads two local sources and writes nothing.

**Which session.** The *active session* is the single newest-mtime `.jsonl` under `~/.claude/projects` (excluding `observer-sessions`, which background tooling writes constantly). Its filename stem is the `session_id`. In practice this is the session that most recently *sent a message* — switching the displayed session happens "on send", not "on click into the list". This is a deliberate, accepted limitation: with multiple Claude Code sessions running in the desktop app in parallel, no readable file reliably identifies the foreground window, so newest-write is the best available signal.

> This was confirmed empirically: snapshotting every state file under `~/Library/Application Support/Claude/` across a session-window switch (without sending a prompt) showed **zero files modified**. The Chromium-based desktop app keeps foreground focus in memory and flushes nothing on a focus change, so file-watching for "which window is in focus" is impossible in principle. See [USAGE.md → How the displayed session switches](USAGE.md#how-the-displayed-session-switches) for the user-facing summary.

**How much.** Claude Code records the official cost itself in `~/.claude/metrics/costs.jsonl` — one JSON line per request:

```jsonc
{
  "session_id": "…",
  "transcript_path": "/Users/…/<session_id>.jsonl",
  "model": "claude-opus-4-8",
  "input_tokens": 0, "output_tokens": 0,
  "cache_write_tokens": 0, "cache_read_tokens": 0,
  "estimated_cost_usd": 12.34   // CUMULATIVE per session, monotonic
}
```

`estimated_cost_usd` is the same figure Claude Code's cost-warning hook reports. The provider tail-reads the file (last ~256 KB, via `FileHandle`) and takes the latest line for the active `session_id` — O(1) per poll regardless of how large the append-only file grows.

**Fallback.** A freshly opened session can be the newest `.jsonl` before its first `costs.jsonl` line lands. During that gap the provider prices the transcript's own token usage via `ModelPricing` so the gauge still tracks *that* session, then snaps to the official number once it appears. (The transcript's own `costUSD` field is null, which is why cost can't be read directly there.)

**Cost level.** `CostDisplay` maps cumulative cost to a color band — calm (orange), busy (yellow), hot (red). The USD thresholds (`busyThreshold`, `hotThreshold` in `CostDisplay.swift`) are tunable constants.

## State machine

| Remaining (5h) | Level | Color |
|----------------|-------|-------|
| `> 50%` | safe | label color (white) |
| `20–50%` | warning | yellow |
| `< 20%` | danger | red |

Error states render orange: `⚠️ 需登入` (401/403/no session — tappable, opens Claude), `🔌 離線` (network error), `⚠️ API` (unexpected JSON/status). The **cost face has no error states** — any read failure (missing file, malformed line) is non-fatal and shows the last good number.

## Caveats & Risks

- **Internal API, no contract.** `/organizations/{org}/usage` is undocumented. Field names or the endpoint itself may change without notice. JSON decode failures degrade to `⚠️ API` rather than crashing.
- **Private macOS APIs for the Touch Bar.** Rendering uses `+[NSTouchBarItem addSystemTrayItem:]` (via the ObjC runtime) and `DFRElementSetControlStripPresenceForIdentifier` (via `dlopen`/`dlsym`). Both are guarded so a missing symbol won't crash, but a future macOS release could stop them from rendering. Re-test after OS upgrades.
- **Session lifetime.** When the desktop session expires, the app shows `⚠️ 需登入`; logging back into the Claude app restores it on the next poll.
- **Cost depends on Claude Code's local layout.** The cost face reads `~/.claude/metrics/costs.jsonl` and `~/.claude/projects/**/*.jsonl`. These are Claude Code internals with no stability contract; if their location or schema changes, the cost face degrades to the last good value (or token-priced fallback) rather than failing. The `estimated_cost_usd` figure is Claude Code's own estimate, not a billed amount.
