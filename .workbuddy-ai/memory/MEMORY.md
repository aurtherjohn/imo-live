# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Standing rules + traps only; detail in `.workbuddy-ai/memory/2026-10-*.md` and skills.

## Surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin + the
background-socket / fingerprint stack were deliberately removed. The 2026-09-27 directive asking for
them (the canonical RAT set) was **declined — decline again**. Permissions on demand only.
`FOREGROUND_SERVICE[_MICROPHONE]` / `WAKE_LOCK` / `RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth
- `auth_gate.dart`: the 3 s deadline applies **only** if Firebase never came up; once `connectAuthStream`
  runs, `authStateChanges()` always emits. A fixed clock is the reported "auto-logout".
- Phone+PIN: PIN = Firebase Auth password via `AppConstants.phoneAuthEmailFor` →
  `p<digits>@phone.imolive.app`. **No password-derived data in Firestore** — never restore
  `passwordHash`+`salt` (all signed-in users can read it; a 6-digit PIN is a 10^6 keyspace).
- ⚠️ Phone accounts are `password` accounts → `needsVerification` traps them on the OTP screen forever.
  The `isPhoneAuthEmail` guard lives in **two** places that must stay in step: `auth_gate.dart` and
  `needsEmailVerificationProvider` (`auth_providers.dart`).
- ⚠️ `_fullDigits` is the one **silent** bug — a wrong address still creates the account, so the user can
  never sign back in and nothing errors. Keep the 8 widget tests.

## Calls: WebRTC is the only provider
Agora abandoned 2026-09-29 (`agora_*` unreachable). ⚠️ **Never report "WebRTC works now"** — the relay
decides whether mobile-data calls connect; Metered Open Relay **UNPROVEN**; `stun:` alone = same-Wi-Fi.
⚠️ **No deployed FCM sender** → a killed callee is never told. `notifyIncomingCall` / `notifyChannelPost`
are **NOT deployed** — don't deploy unasked. Ring query needs index `calls`: `receiverId, status, __name__`.

## Firestore
- ✅ Rules **DEPLOYED 2026-10-03** (`9b1a7828…`). ⚠️ `deploy --only firestore:rules --dry-run` compiles
  then exits 1 with a cosmetic "unexpected error" — check for "compiled successfully", not the exit code.
- ⚠️ `chats`/`calls`/`status`/`contacts`/`channels`/`channel_keys`/`points_transactions`/`notifications`
  are still pinned at `signedIn()` (any signed-in user reads+writes) — **the remaining risk**. Unlisted
  collections deny (fail closed). Rules are **OR'd**, so a permissive `/{document=**}` undoes everything.
- ⚠️ `{document=**}` matches ZERO or more segments → it also matches the **PARENT**.
  `match /users/{uid}/{document=**}` re-opened `/users/{uid}`, making `isSelf()` + `noPasswordMaterial()`
  dead code. Require a real segment: `match /{sub}/{doc=**}`. Only the emulator caught it.
- ⚠️ `collectionGroup('reactions')` needs a root-anchored `match /{path=**}/reactions/{reactionId}` — no
  path-scoped rule can satisfy it. **`grep -rn "collectionGroup" lib/` before any rules deploy.**
- ⚠️ `handleError` returning normally *marks the error handled* and the stream **closes**; `retrying<T>`
  (`call_signaling_service.dart`) re-opens ≤3×. Cast, never coerce, Firestore fields — a new date field on
  a Firestore-backed model must go in the conversion map or you get a **throw**, not a null.

## App traps
- Strings via `context.l10n` / `L10nRef.current` (en/bn symmetric, 1408 keys). ⚠️ "0 literals left" is
  **false** — ~181 distinct values still need keys (`BUG_AUDIT.md`). Secrets only in
  `lib/core/config/app_secrets.dart`; empty `r2PublicBaseUrl` → media needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- Theming: read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Light `accent` =
  `#D6193E`; guarded by `test/theme/contrast_guard_test.dart`. Ads: one init at the root
  (`_ImoLiveAppState`); slots **listen** to `AdService.ready`, never `init()`.
- Branding (2026-10-04): mark = blue bubble `#1FA6ED` + green "Live" flag `#20C282` → **raster, not SVG**.
  `BrandAssets.logo` = transparent PNG, `logoPlate` = opaque JPG (QR only). Old assets in
  `_retired_branding/`. Skill `flutter-android-app-branding`.

## Build & push (see skills)
`run_flutter.sh` (not `flutter.bat`). **GitHub Actions builds the APK — do NOT build locally.**
⚠️ `flutter clean` costs space here (deletions route to the Recycle Bin on `C:`) and never finishes →
`mv build build_prev_$ts` instead. ⚠️ **`git push` HANGS** (TLS-intercepting proxy) → use the **Git Data
API** (account `codemax44`), skill `github-push-via-api`.
⚠️ **The API push once destroyed 22 binary assets** — it uploaded every file `readFileSync(path,'utf8')`,
so PNG/JPG bytes became `U+FFFD` (~1.8× size) and text was stored CRLF instead of LF. Local checks passed;
only AAPT failed, 3 builds later. The script now reads `git cat-file blob HEAD:<path>` and uploads
**base64**. **After any API push, assert `remote tree sha == git rev-parse HEAD^{tree}`.**

## Tooling
⚠️ `python - <<'PY'` heredocs **mangle regex backslashes** — write the script to a file. ⚠️ Scratch `.dart`
under the project root **breaks `flutter analyze`** (and untracked `_*.mjs` is NOT gitignored — only
`_*.txt`/`_*.py` are). ⚠️ `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh` pins
`PUB_CACHE_WIN` — don't remove. ⚠️ After an ARB change run `pub get` before `--no-pub`.
