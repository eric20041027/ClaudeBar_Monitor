# Architecture

ClaudeBar Monitor is a single native Swift executable. It has three logical layers — **credential**, **data**, and **render** — plus a small coordinator. There is no server, no database, and no external process.

## Data flow

```
┌─────────────────────────────────────────────────────────────┐
│  macOS local machine                                          │
│                                                               │
│  ~/Library/Application Support/Claude/Cookies   (SQLite)      │
│        │  encrypted_value (AES-128-CBC, v10/v11 prefix)       │
│        ▼                                                      │
│  Keychain: "Claude Safe Storage" passphrase                   │
│        │  PBKDF2-SHA1(salt="saltysalt", iter=1003) → AES key  │
│        ▼                                                      │
│  CookieDecryptor → sessionKey + lastActiveOrg + cookie header │
│        │                                                      │
│        ▼   HTTPS GET (one request per poll)                   │
│  https://claude.ai/api/organizations/{org}/usage              │
│        │                                                      │
│        ▼                                                      │
│  UsageClient → { five_hour.utilization, resets_at }           │
│        │                                                      │
│        ▼                                                      │
│  StatusViewModel → "🤖 {100 − utilization}%" + color level    │
│        │                                                      │
│        ▼                                                      │
│  TouchBarController → Control Strip item (private DFR API)    │
└─────────────────────────────────────────────────────────────┘
```

## Components

| File | Responsibility |
|------|----------------|
| [`CookieDecryptor.swift`](../Sources/ClaudeBarMonitor/CookieDecryptor.swift) | Reads the Cookies SQLite DB, fetches the AES key from Keychain, decrypts `sessionKey` + `lastActiveOrg`, builds the cookie header. |
| [`UsageClient.swift`](../Sources/ClaudeBarMonitor/UsageClient.swift) | Makes the authenticated `GET .../usage` call, decodes the JSON into typed models, maps failures to a `UsageResult` enum. |
| [`StatusViewModel.swift`](../Sources/ClaudeBarMonitor/StatusViewModel.swift) | Pure mapping from `UsageResult` → display text + color level + tappable flag. No side effects. |
| [`TouchBarController.swift`](../Sources/ClaudeBarMonitor/TouchBarController.swift) | Owns the Control Strip item and updates its label/color. Wraps the private Touch Bar APIs behind crash-safe guards. |
| [`main.swift`](../Sources/ClaudeBarMonitor/main.swift) | `NSApplication` entry point. Sets `.accessory` policy, runs the 4-minute poll timer, wires the tap handler. |

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

## State machine

| Remaining (5h) | Level | Color |
|----------------|-------|-------|
| `> 50%` | safe | label color (white) |
| `20–50%` | warning | yellow |
| `< 20%` | danger | red |

Error states render orange: `⚠️ 需登入` (401/403/no session — tappable, opens Claude), `🔌 離線` (network error), `⚠️ API` (unexpected JSON/status).

## Caveats & Risks

- **Internal API, no contract.** `/organizations/{org}/usage` is undocumented. Field names or the endpoint itself may change without notice. JSON decode failures degrade to `⚠️ API` rather than crashing.
- **Private macOS APIs for the Touch Bar.** Rendering uses `+[NSTouchBarItem addSystemTrayItem:]` (via the ObjC runtime) and `DFRElementSetControlStripPresenceForIdentifier` (via `dlopen`/`dlsym`). Both are guarded so a missing symbol won't crash, but a future macOS release could stop them from rendering. Re-test after OS upgrades.
- **Session lifetime.** When the desktop session expires, the app shows `⚠️ 需登入`; logging back into the Claude app restores it on the next poll.
