# Mac iMessage Bridge

A native macOS menu bar app that incrementally syncs the text of your local
iMessage/SMS history to any backend you point it at. Built with SwiftUI as a
plain Swift Package; reads the Messages database directly, read-only, on your
machine — no Apple APIs, no MDM, no jailbreak.

Use it as a starting point for anything that needs your texts server-side:
personal assistants, search indexes, archival, CRM enrichment. The app is the
client half; you implement two HTTP endpoints on your server (contract below).

## How it works

**Pairing.** Your web app generates a one-time pairing token and renders a
deep link:

```
del-mac://pair?token=<one-time-token>&apiBaseUrl=https://your-server.example
```

The app registers the `del-mac://` URL scheme (`Config/Info.plist`). Clicking
the link opens the app, which exchanges the token at
`POST /api/mac-bridge/pair/complete` for a long-lived device token and stores
it in the macOS Keychain. The API base URL travels inside the pairing link, so
the same binary works against any server, including `localhost` during
development.

**Reading Messages.** The app opens `~/Library/Messages/chat.db` strictly
read-only via [GRDB](https://github.com/groue/GRDB.swift). macOS gates this
behind Full Disk Access; the app detects the missing permission, walks the
user through System Settings, and polls every 2 seconds until access appears.

**Sync loop.** Every 30 seconds (and once on pairing), the app:

1. Reads up to 250 message rows with `ROWID` greater than the last synced
   watermark (`MessagesReader.swift`). The very first sync starts from the
   most recent 250 messages rather than replaying full history.
2. Normalizes rows into threads (chat GUID, display name, participant
   handles) and messages (text body, direction, service, timestamp). Only
   messages with non-empty text are included — attachments and empty rows are
   skipped.
3. POSTs the batch to `POST /api/mac-bridge/sync` with
   `Authorization: Bearer <deviceToken>`.
4. Advances the watermark to the `lastSyncedRowId` the server echoes back,
   persisted in `UserDefaults`, so syncs resume incrementally across restarts.

**Menu bar UI.** A popover shows the current state (not paired, needs Full
Disk Access, connected, syncing, paused, error) with pause/resume and
disconnect controls. Disconnect is local-only: it deletes the Keychain token
and resets the watermark; revoking the device server-side is your server's
job.

**What it never does:** send or modify messages, create anything in the
Messages app, or upload attachments. Text only, one direction.

## Server API contract

Implement these two endpoints and you have a working backend. All bodies are
JSON; timestamps are ISO 8601.

### `POST /api/mac-bridge/pair/complete`

Exchanges the one-time pairing token for device credentials.

```jsonc
// request
{ "token": "<one-time-token>", "deviceName": "Evan's MacBook Pro" }

// response
{ "deviceId": "dev_123", "deviceToken": "<long-lived-secret>" }
```

### `POST /api/mac-bridge/sync`

Receives a batch. Auth: `Authorization: Bearer <deviceToken>`.

```jsonc
// request
{
  "threads": [
    {
      "sourceThreadId": "iMessage;-;+15551234567",   // chat.guid
      "threadName": "Family",                         // chat.display_name, null for DMs
      "participants": ["+15551234567"]                // handle ids (phone/email)
    }
  ],
  "messages": [
    {
      "sourceMessageId": "GUID-FROM-CHAT-DB",
      "sourceRowId": 4821,                            // message.ROWID, the sync cursor
      "sourceThreadId": "iMessage;-;+15551234567",
      "direction": "received",                        // "sent" | "received"
      "service": "iMessage",                          // or "SMS"
      "body": "message text",
      "sentAt": "2026-06-12T17:00:00Z"
    }
  ],
  "lastSyncedRowId": 4821
}

// response — lastSyncedRowId becomes the client's new watermark
{ "ok": true, "syncedMessages": 1, "lastSyncedRowId": 4821 }
```

Batches arrive ordered by `ROWID` ascending, at most 250 messages each, so a
backlog drains over successive 30-second ticks. Use `sourceMessageId` for
idempotent upserts — the client may re-send a batch if your response never
arrives.

## Development

Requires macOS 14+ and Swift 5.9+.

```sh
swift package resolve
swift build
swift run DelMacBridge
```

Tip: when running from a terminal, Full Disk Access is inherited from the
terminal app — grant it to your terminal (or IDE) in System Settings and
`swift run` can read `chat.db` directly.

`Config/` holds the pieces a release bundle needs:

- `Info.plist` — registers the `del-mac://` URL scheme and marks the app as a
  menu bar utility (`LSUIElement`).
- `DelMacBridge.entitlements` — keeps the app outside the App Sandbox (Full
  Disk Access requires it) and allows outbound network access.

There is no `.app` packaging script yet: shipping a real release means
wrapping the executable in a bundle with the provided plist/entitlements,
then signing and notarizing with a Developer ID.

## Adopting this for your own product

The bridge was originally built for Del, a personal-assistant product, and
the identifiers still reflect that. To rebrand, touch four places:

- **URL scheme** — `Config/Info.plist` (`CFBundleURLSchemes`) and the
  `url.scheme == "del-mac"` check in `AppState.handlePairingURL`.
- **Bundle/Keychain identity** — `com.del.mac-bridge` in `Config/Info.plist`
  and `KeychainStore.swift`.
- **Endpoint paths** — `/api/mac-bridge/...` in `APIClient.swift`.
- **Display strings** — app name and copy in `Config/Info.plist` and
  `DelMacBridgeApp.swift`.

## Privacy notes

Everything runs locally until you pair. The app reads message text only after
the user explicitly grants Full Disk Access, and only uploads to the server
named in the pairing link the user clicked. Pausing stops all reads and
uploads; disconnecting deletes the stored credentials.
