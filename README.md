# Imo LIVE

Offline-first messaging and calling app for Android, built with Flutter.

- **Package / Application ID:** `com.imo.live`
- **Firebase project:** `imo-live-inc`
- **Version:** 1.0.0 (versionCode 2 — see `pubspec.yaml`)
- **Platforms:** Android (shipped). iOS targets exist in the project but are not built.

## Current Features (Working)

| Area | Implementation |
| --- | --- |
| Messaging | One-to-one chat, text / photo / video / voice note / location / contact |
| Groups | Group creation and group chat |
| Calling | Voice and video calls over WebRTC (peer-to-peer, Firestore as signalling) |
| Auth | Google Sign-In and phone number + PIN. No email/password |
| Push | OneSignal, sent through a Cloudflare Worker |
| Local store | Hive, JSON-per-record, as the render source of truth |
| Remote store | Cloud Firestore (transport), Cloudflare R2 (media) |

## Removed Features (Latest Changes)

The following features were completely removed:

1. **Earn / Income:** Earning money, gift sending, points system, monetization admin — all removed.
2. **Channels:** Broadcast channels, channel analytics, channel join requests, channel monetization — all removed.
3. **Communities:** Communities screen, create community, communities list — all removed.

Only **Groups** remain as the multi-user chat feature.

## Architecture in One Paragraph

Firestore is the transport, not the source of truth. Every read renders from the local Hive store, and Firestore snapshots are merged into it in the background — which is what makes the app usable on a bad connection and what makes a local action (sending a message, deleting a chat) take effect immediately instead of after a round trip. Repositories are the swap point: `lib/features/*/domain/` defines the interfaces, `lib/local/database/` implements them against Hive.

## File Structure

```
lib/
  app/            router, auth gate, app shell
  core/           models, services (calls, push, media), widgets, config
  features/       auth, chats, calls, contacts, groups, settings, search, profile
  local/          Hive-backed repository implementations
  l10n/           ARB files (en, bn) + generated localizations
```

## Building

⚠️ **CI builds the APK. Do not build release APKs locally.**

`.github/workflows/build-apk.yml` runs on every push to `main`, gates on `flutter analyze` and `flutter test`, decodes the release keystore from the `KEYSTORE_BASE64` secret, builds split-per-ABI APKs, verifies the signing certificate against the SHA-1 and SHA-256 registered in Firebase, and publishes a GitHub Release tagged `build-<run number>`.

For local development use the wrapper, not `flutter` directly:

```bash
./run_flutter.sh run          # debug run
./run_flutter.sh analyze
./run_flutter.sh test
```

`run_flutter.sh` exists because `flutter.bat` on this Windows host exits 0 without doing anything, and because `PUB_CACHE` must be pinned. See the script's own comments.

### Release Signing

CI signs with the keystore in `KEYSTORE_BASE64`. Locally, copy `android/key.properties.example` to `android/key.properties` and fill it in.

There is **no debug fallback**: `assertReleaseSigning` in `android/app/build.gradle.kts` fails the build when no release keystore is configured, rather than silently producing a debug-signed APK whose SHA-1 is not registered in Firebase. `flutter run` and `flutter build apk --debug` are unaffected.

## ⚠️ Before Publishing

`lib/core/config/app_secrets.dart` currently holds **live credentials compiled into the APK**, including a Cloudflare R2 secret access key with read/write/delete on the media bucket, and a public test TURN relay. Read the warning at the top of that file. Rotating the R2 credentials and pointing the app at a dedicated TURN deployment are both console operations, not code changes — see the `--dart-define` overrides documented in that file and in `R2Config` / `WebRtcIce`.

Secrets that must **not** be in the client — the OneSignal REST key and the Agora App Certificate — live in Cloudflare Worker environment variables.

## Configuration

| Value | Where |
| --- | --- |
| Firebase (project id, app id, API key) | `android/app/google-services.json` |
| OneSignal App ID, Worker URL | `lib/core/config/app_secrets.dart` |
| R2 bucket, endpoint, credentials | `lib/core/config/app_secrets.dart` |
| STUN / TURN | `lib/core/config/app_secrets.dart`, overridable via `--dart-define` |

## Testing

```bash
./run_flutter.sh test
```

The suite runs hermetically; tests that need a live network service are gated behind a flag rather than hitting the network on every run.

## Localisation

English (`en`) and Bengali (`bn`), symmetric — every key exists in both ARB files. UI strings are read through `context.l10n`, never hardcoded.

## Version History (Current State)

- **Current:** Earn, Channels, Communities features removed. Only Groups, Chats, Calls, Contacts, Profile, Settings remain.
- **Previous:** Earn / Watch-to-Earn tab, channel list and monetization, communities list and screen, subscriptions screen.
