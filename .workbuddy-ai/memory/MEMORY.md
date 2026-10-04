# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Standing rules + traps only. Detail: `.workbuddy-ai/memory/2026-10-*.md`,
`.workbuddy-ai/memory/firestore-rules-traps.md`, `worker/*.js`, skills in `~/.workbuddy-ai/skills/`.

## Surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin + the
background-socket / fingerprint stack were deliberately removed. The 2026-09-27 directive asking for them
(the canonical RAT set) was **declined — decline again**. Permissions on demand only.
`FOREGROUND_SERVICE[_MICROPHONE]` / `WAKE_LOCK` / `RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth
- `auth_gate.dart`: the 3 s deadline applies **only** if Firebase never came up; once `connectAuthStream`
  runs, `authStateChanges()` always emits. A fixed clock is the reported "auto-logout".
- Phone+PIN: PIN = Firebase Auth password via `AppConstants.phoneAuthEmailFor` → `p<digits>@phone.imolive.app`.
  **No password-derived data in Firestore** (never restore `passwordHash`+`salt`; 6-digit PIN = 10^6 keyspace).
- ⚠️ Phone accounts are `password` accounts → `needsVerification` traps them on the OTP screen forever. The
  `isPhoneAuthEmail` guard lives in **two** places that must stay in step: `auth_gate.dart` and
  `needsEmailVerificationProvider` (`auth_providers.dart`).
- ⚠️ `_fullDigits` is the one **silent** bug — a wrong address still creates the account, so the user can never
  sign back in and nothing errors. Keep the 8 widget tests.

## Calls: WebRTC is the only provider
Agora abandoned 2026-09-29. ⚠️ **Never report "WebRTC works now"** — the relay decides whether mobile-data
calls connect; Metered Open Relay **UNPROVEN**; `stun:` alone = same-Wi-Fi. Ring query needs index `calls`:
`receiverId, status, __name__`.

## Push: OneSignal replaced FCM (2026-10-04)
`firebase_messaging` is **gone**; `onesignal_flutter ^5.2.9` is the only push stack. `onesignal_service.dart`
owns `linkUser`/`unlinkUser` (→ `users/{uid}.oneSignalPlayerId`) and `sendNotificationToUser` (POSTs to the
Cloudflare Worker, which holds the REST key — **never in the APK**); `PushNotificationService` keeps the
tested `PushPayload`/`PushKind` parser but is OneSignal-backed. Both sends are detached, *after* a successful
write; the tap payload carries `callerId` *and* `callId`; listeners register in `main()` before `runApp`.
**Worker contract CONFIRMED by probe**: GET/OPTIONS 405, `{}` → 400 `receiverUid and title are required`,
full body → 200 + OneSignal's raw response. ⚠️ Unknowable from outside: whether it addresses by `external_id`
(= uid) or by the stored player id — the latter is null on a fresh install, so a player-id-addressed Worker
fails silently — and whether it sets `android_channel_id` (visible only in `OSNotification.rawPayload` on a
device; `_logChannel` prints it). Reference: `worker/send-notification-worker.js`.
Skill: `flutter-onesignal-push-migration`.

## Profile picture: local path vs remote URL
`*.avatarPath` is a path on **this** device — non-null only for your own picture. `Contact.avatarUrl` /
`Chat.avatarUrl` (added 2026-10-04) are the remote ones, from `users/{uid}.avatarUrl`. ⚠️ Every peer-facing
`IAvatar` must pass `imageUrl: x.avatarUrl`; `imagePath:` alone shows initials for everyone else. The Firestore
*write* was never the bug — `updateProfile` has written `avatarUrl` with `SetOptions(merge:true)` since
`4c28505`; no peer-side model or widget carried the URL.
Skill: `flutter-peer-visible-field-propagation`.

## App traps
- Strings via `context.l10n` / `L10nRef.current` (en/bn symmetric, 1408 keys). ⚠️ "0 literals left" is **false** —
  ~181 distinct values still need keys (`BUG_AUDIT.md`). Secrets only in `lib/core/config/app_secrets.dart`;
  empty `r2PublicBaseUrl` → media needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- Theming: read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Light `accent` = `#D6193E`,
  guarded by `test/theme/contrast_guard_test.dart`. Ads: one init at the root (`_ImoLiveAppState`); slots
  **listen** to `AdService.ready`, never `init()`.
- Branding: raster, not SVG — skill `flutter-android-app-branding`. Old assets in `_retired_branding/`.

## Build & push (see skills)
`run_flutter.sh` (not `flutter.bat`). **GitHub Actions builds the APK — do NOT build locally.** ⚠️ `flutter clean`
costs space here (deletions route to the Recycle Bin on `C:`) and never finishes → `mv build build_prev_$ts`.
⚠️ **`git push` HANGS** (TLS-intercepting proxy) → **Git Data API** (account `codemax44`), skill
`github-push-via-api`. ⚠️ That path once destroyed 22 binary assets (everything uploaded via
`readFileSync(...,'utf8')`, so PNG/JPG became `U+FFFD` and text CRLF); it now reads
`git cat-file blob HEAD:<path>` and uploads **base64**. **After any API push assert
`remote tree sha == git rev-parse HEAD^{tree}`.**

## Tooling
⚠️ **Multiple `Edit` calls to the SAME file in ONE message clobber each other** — each edit reads the original,
then rewrites the whole file, so with N parallel edits only one survives, yet all N report "Successfully
edited". Symptom: `flutter analyze` errors about names you *just added*. **One edit per file per message.**
⚠️ `python - <<'PY'` heredocs **mangle regex backslashes** — write the script to a file. ⚠️ Scratch `.dart` under
the project root **breaks `flutter analyze`** (untracked `_*.mjs` at root is NOT gitignored; `_fstest/` IS).
⚠️ `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh` pins `PUB_CACHE_WIN` — don't remove.
⚠️ After an ARB change run `pub get` before `--no-pub`. ⚠️ `flutter analyze` takes 2-4 min — run it backgrounded.
