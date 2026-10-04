# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Standing rules + traps only — narrative detail lives in
`.workbuddy-ai/memory/2026-10-*.md`, `firestore-rules-traps.md`, and the skills under
`~/.workbuddy-ai/skills/`.

## Never build the surveillance stack (declined 2026-09-27 — decline again)
Accessibility / notification-listener / boot-receiver / device-admin / background-socket / fingerprint were
deliberately removed. Permissions on demand only. `FOREGROUND_SERVICE[_MICROPHONE]`, `WAKE_LOCK`,
`RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth
- Phone+PIN = Firebase Auth password: `p<digits>@phone.imolive.app`. **Never store password material in
  Firestore** (a 6-digit PIN is a 10^6 keyspace).
- ⚠️ Phone accounts are `password` accounts → `needsVerification` traps them on the OTP screen forever. The
  `isPhoneAuthEmail` guard must stay in step in **two** places: `auth_gate.dart` and
  `needsEmailVerificationProvider`.
- ⚠️ `_fullDigits` was the one **silent** failure: `startsWith(dial)` is not proof the code is present (India
  `91` vs a mobile starting `9`) → the account was created under a different address, unreachable, no error.
  Fixed 2026-10-04; keep all 10 `phone_login_test.dart` tests.
- `auth_gate.dart`'s 3 s deadline applies **only** if Firebase never came up; otherwise `authStateChanges()`
  always emits. A fixed clock is the reported "auto-logout".

## Calls
WebRTC only; Agora abandoned 2026-09-29. ⚠️ **Never report "WebRTC works now"** — the relay decides whether
mobile-data calls connect; Metered Open Relay **UNPROVEN**; `stun:` alone = same-Wi-Fi. The `calls` index
(`receiverId, status`) is verified READY — don't re-open it.

## Push — OneSignal replaced FCM (2026-10-04)
`firebase_messaging` is **gone**. `onesignal_service.dart` owns `linkUser`/`unlinkUser` and
`sendNotificationToUser` → the Cloudflare Worker, which holds the REST key (**never in the APK**).
`PushNotificationService` keeps the tested payload parser. Sends are detached, *after* a successful write;
listeners register in `main()` before `runApp`. The Worker contract is **CONFIRMED by probe**; ⚠️ still
unknowable from the client: `external_id` vs the stored player id (the latter is null on a fresh install → a
silent failure), and `android_channel_id` (visible only in `rawPayload` on a device; `_logChannel` prints it).

## Profile picture
`*.avatarPath` is local to **this** device — non-null only for your own picture. `Contact.avatarUrl` /
`Chat.avatarUrl` are the remote ones. ⚠️ Every peer-facing `IAvatar` must pass `imageUrl: x.avatarUrl`;
`imagePath:` alone shows initials for everyone else. The write was never the bug — the read path was.

## App traps
- Strings via `context.l10n` / `L10nRef.current` (en/bn symmetric, 1582 keys). `_l10n_convert.py` sees only a
  literal *immediately* after a slot; `_l10n_expr_convert.py` covers ternaries / `??` fallbacks. Secrets only
  in `lib/core/config/app_secrets.dart`.
- Read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Ads init once at the root; slots
  **listen** to `AdService.ready`. Branding is raster, not SVG.

## Build & push
`run_flutter.sh`, not `flutter.bat`. **GitHub Actions builds the APK — do NOT build locally.** ⚠️ `flutter
clean` never finishes here (deletions route to the Recycle Bin) → `mv build build_prev_$ts`. ⚠️ **`git push`
HANGS** (TLS proxy) → Git Data API, skill `github-push-via-api`. **After any API push assert
`remote tree sha == git rev-parse HEAD^{tree}`** — the server-side commit has a *different* sha; compare trees,
never commits. (The API once uploaded blobs as UTF-8 and destroyed 22 binaries; it now uses `git cat-file blob
HEAD:<path>` + base64.)

## Tooling
⚠️ **Multiple `Edit` calls to the SAME file in ONE message clobber each other** (each rewrites the whole file,
so only one survives, yet all report success). Symptom: `flutter analyze` errors about names you *just added*.
**One edit per file per message.**
⚠️ `python - <<'PY'` heredocs mangle regex backslashes — write the script to a file. Scratch `.dart` at the
project root **breaks `flutter analyze`**. `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh` pins
it — don't remove. Run `pub get` after an ARB change. `flutter analyze` takes 2-4 min — run it backgrounded.
