# Del Messages Mac Bridge

Native macOS menu bar bridge for syncing local Messages text into Del.

## Development

```sh
cd apps/mac-bridge
swift package resolve
swift build
swift run DelMacBridge
```

The package contains the app code and the macOS configuration needed by the
release bundle:

- `Config/Info.plist` registers the `del-mac://pair` URL scheme and marks
  the app as a menu bar utility.
- `Config/DelMacBridge.entitlements` keeps the app outside the sandbox and
  allows outbound network access.

## Runtime Behavior

- Pairing starts in the web app at `/api/mac-bridge/pair/start`.
- The Mac app receives `del-mac://pair?token=...&apiBaseUrl=...`, exchanges
  it at `/api/mac-bridge/pair/complete`, and stores the returned device token
  in Keychain.
- The app opens `~/Library/Messages/chat.db` read-only. macOS requires users to
  grant Full Disk Access before this succeeds.
- Sync sends normalized threads and message rows to `/api/mac-bridge/sync`.
- V1 does not create tasks, modify Messages, send replies, or upload
  attachments.

## Release Follow-Up

This Swift package is the implementation scaffold. The production DMG still
needs an Xcode project or build script that creates a `.app` bundle using the
provided plist/entitlements, then signs and notarizes it with Developer ID.
