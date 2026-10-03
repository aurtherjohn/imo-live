# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Rules + gotchas only; detail in `.workbuddy-ai/memory/2026-10-0*.md` + skills.

## Surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin + the
background-socket / fingerprint stack were deliberately removed. The 2026-09-27 directive asking for them
(canonical RAT set) was **declined — decline again**. Permissions on demand only.
`FOREGROUND_SERVICE[_MICROPHONE]`/`WAKE_LOCK`/`RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth
- `auth_gate.dart`: the 3 s deadline applies **only** if Firebase never came up; once `connectAuthStream`
  runs, `authStateChanges()` always emits.
- Phone+PIN: PIN = Firebase Auth password via `AppConstants.phoneAuthEmailFor` → `p<digits>@phone.imolive.app`.
  **No password-derived data in Firestore** — never restore `passwordHash`+`salt` (all users can read it;
  6-digit PIN = 10^6 keyspace).
- ⚠️ Phone accounts are `password` accounts → `needsVerification` traps them on OTP forever; the
  `isPhoneAuthEmail` guard lives in **two** places (`auth_gate.dart` + `needsEmailVerificationProvider`).
- ⚠️ `_fullDigits` is the one **silent** bug (a wrong address still creates the account). Keep the 8 tests.

## Calls: WebRTC only
Agora abandoned 2026-09-29. ⚠️ **Never report "WebRTC works now"** — the relay decides; Metered Open Relay
**UNPROVEN**; `stun:` alone = same-Wi-Fi. ⚠️ **No deployed FCM sender** → a killed callee is never told;
`notifyIncomingCall`/`notifyChannelPost` NOT deployed — don't deploy unasked. Ring needs index `calls`:
`receiverId, status, __name__`.

## Firestore
- ✅ Rules **DEPLOYED 2026-10-03** (`9b1a7828…`). ⚠️ `deploy --dry-run` exits 1 cosmetically — check
  "compiled successfully".
- ⚠️ `chats`/`calls`/`status`/`contacts`/`channels`/`channel_keys`/`points_transactions`/`notifications` are
  still pinned at `signedIn()` (any signed-in user reads+writes) — remaining risk. Unlisted → **deny**. Rules
  are OR'd, so a permissive `/{document=**}` undoes everything.
- ⚠️ `{document=**}` matches ZERO+ segments → also the PARENT: `match /users/{uid}/{document=**}` re-opened
  `/users/{uid}`, killing `isSelf()`/`noPasswordMaterial()`. Use `match /{sub}/{doc=**}`.
- ⚠️ `collectionGroup('reactions')` needs root-anchored `match /{path=**}/reactions/{reactionId}`.
  **`grep -rn collectionGroup lib/` before any rules deploy.**
- ⚠️ `handleError` returning normally *marks the error handled* and the stream **closes**. `retrying<T>`
  re-opens ≤3×. Cast, never coerce, Firestore fields.

## App traps
- Strings via `context.l10n`/`L10nRef.current` (en/bn symmetric). ⚠️ "0 literals left" is **false** — hundreds
  remain (`BUG_AUDIT.md`). Secrets only in `lib/core/config/app_secrets.dart`; `r2PublicBaseUrl` empty → media
  needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- Theming: read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Light `accent` = `#D6193E`;
  guarded by `test/theme/contrast_guard_test.dart`. Ads: one init at the root (`_ImoLiveAppState`); slots
  **listen** to `AdService.ready`, never `init()`.
- Branding (2026-10-04): mark = blue bubble `#1FA6ED` + green "Live" flag `#20C282` → **raster, not SVG**;
  `BrandAssets.logo` = transparent PNG, `logoPlate` = opaque JPG (QR only). Skill `flutter-android-app-branding`.

## Build & push (see skills)
`run_flutter.sh` (not `flutter.bat`). **GitHub Actions builds the APK — do NOT build locally.** ⚠️ `flutter
clean` costs space and never finishes → `mv build build_prev_$ts`. ⚠️ **`git push` HANGS** here
(TLS-intercepting proxy) → use the **Git Data API** (account `codemax44`). Skills: `github-push-via-api`,
`windows-disk-reclaim`, `flutter-android-sandboxed-build`.

## Tooling
⚠️ `python - <<'PY'` heredocs **mangle regex backslashes** — write to a file. ⚠️ Scratch `.dart` under the
project root **breaks `flutter analyze`**. ⚠️ `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh`
pins `PUB_CACHE_WIN` — don't remove. ⚠️ After an ARB change run `pub get` before `--no-pub`.
