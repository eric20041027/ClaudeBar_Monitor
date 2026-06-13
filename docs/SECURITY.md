# Security & Privacy

## What this app accesses

| Resource | Access | Purpose |
|----------|--------|---------|
| `~/Library/Application Support/Claude/Cookies` | **read-only** | Read the encrypted `sessionKey` and `lastActiveOrg` cookies. |
| Keychain item `Claude Safe Storage` | **read** | Obtain the AES passphrase to decrypt the above. macOS gates this with a user prompt. |
| `https://claude.ai/api/organizations/{org}/usage` | **HTTPS GET** | Fetch usage numbers. One request per poll. |

That is the complete list. No other files, hosts, or services are touched.

## What it does NOT do

- **Does not write or cache credentials.** The decrypted `sessionKey` lives only in memory for the duration of a request. It is never written to disk, never logged, never printed.
- **Does not send your data anywhere except `claude.ai`.** There is no telemetry, no analytics, no third-party host.
- **Does not modify** the Claude app, its cookies, or your account in any way. It is strictly read-only on local state.

## Why Keychain access is required

The Claude desktop app (Electron/Chromium) encrypts its cookies with a key stored in your login Keychain. Decrypting the session cookie therefore requires reading that one Keychain entry. macOS shows a permission prompt the first time — this is expected and is the correct security boundary doing its job.

## Repository hygiene

If you fork or contribute, **never commit**:

- Decrypted cookie values, `sessionKey`, or `sessionKeyLC`.
- Your organization UUID (`lastActiveOrg`).
- Any `Cookies` SQLite file or copy thereof.
- Local probe/scratch scripts that print decrypted values.

`.gitignore` excludes build output and common scratch-file patterns. The source code itself contains **no secrets** — only the public Chromium decryption constants (`saltysalt`, iteration count, etc.), which are not sensitive.

## Threat notes for users

- Anyone who can already read your Keychain and home directory can read your Claude session regardless of this tool — it does not lower your security posture, it uses the same boundary the Claude app does.
- Because it depends on **internal** Claude APIs, treat any future auth changes (e.g. token rotation) as expected; the app surfaces `⚠️ 需登入` rather than failing silently.
