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
- ⚠️ **Two rulesets exist.** The live one is the **2026-10-03** deploy (`9b1a7828…`). The file in the
  repo is the **2026-10-04 rewrite**, verified but **NOT deployed** — until `firebase deploy --only
  firestore:rules` runs, every protection described below is on paper only.
- ✅ 2026-10-04 rewrite, verified on the emulator: **124 assertions, both directions**, zero compile
  warnings. `chats`/`messages`→participants, `calls`→caller+callee, `contacts/{uid}/list`→owner,
  `channels` write→owner, `status` write→author, `users/{uid}/{points_transactions,notifications}`→owner,
  `channel_keys`→`get` yes / `list` no. Dead **top-level** `points_transactions`/`notifications` blocks
  deleted (nothing ever wrote there).
- ⚠️ **Gifting needs a cross-ownership exception.** `sendGift` credits `users/{recipient}` from the
  *sender*, so `isSelf`-only **denies every gift**. Branch: `changedOnly(['points','updatedAt'])` + an
  increase only. Points are client-mintable anyway — the ledger is not trustworthy without a server.
- ⚠️ **`markChatRead` may use only ONE `!=` filter.** Firestore rejects `senderId != me` **and**
  `status != read` with `INVALID_ARGUMENT`; the old `catch` cleared the counter instead, so the only
  symptom was read receipts that never advanced. Now: `status != read`, sender filtered in Dart.
- ⚠️ **A 400 is not a denial.** Rules harnesses must map 200→allow, 403→deny and fail otherwise — a
  "not 200 = denied" harness reports green over a rule that never ran (this hid the bug above).
- ⚠️ **`hasOnly` accepts a no-op write** — an empty `affectedKeys()` satisfies it, so `changedOnly([...])`
  alone let anyone re-stamp `channels.lastUpdateAt`. Require a counter to actually move.
- ⚠️ **`exists()` in a rule sees the state BEFORE the batch** — so a counter incremented in the same batch
  as the edge that authorises it cannot be guarded by `exists()`; the first follow would be denied.
  Split by direction. Residual, documented: anyone may step a counter **up** by one.
- ⚠️ **A disjunction DOES satisfy a list query** (verified 200). Don't write the opposite into a comment.
- ⚠️ `deploy --only firestore:rules --dry-run` compiles then exits 1 with a cosmetic "unexpected error" —
  check for "compiled successfully", not the exit code.
- ⚠️ `{document=**}` matches ZERO or more segments → it also matches the **PARENT**.
  `match /users/{uid}/{document=**}` re-opened `/users/{uid}`, making `isSelf()` + `noPasswordMaterial()`
  dead code. Require a real segment: `match /{sub}/{doc=**}`. Only the emulator caught it.
- ⚠️ `collectionGroup('reactions')` needs a root-anchored `match /{path=**}/reactions/{reactionId}` — no
  path-scoped rule can satisfy it. **`grep -rn "collectionGroup" lib/` before any rules deploy.**
- ⚠️ `handleError` returning normally *marks the error handled* and the stream **closes**; `retrying<T>`
  (`call_signaling_service.dart`) re-opens ≤3×. Cast, never coerce, Firestore fields — a new date field on
  a Firestore-backed model must go in the conversion map or you get a **throw**, not a null.

## Rules verification (emulator)
- Harness `_fstest/rules_probe.mjs` (**gitignored**), structural lint `_fstest/lint_rules.py`. Start the
  emulators with `JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"`; `firebase.json` already wires
  auth 9099 / firestore 8080. Method + traps in skill `firestore-rules-from-callsites`.
- ⚠️ `:runQuery` `parent` is a **URL path segment** (`.../documents/chats/{id}:runQuery`). In `from` → 400;
  in the body → accepted and **never answered**, so the probe hangs silently.
- ⚠️ Write probe progress with `appendFileSync`, not stdout — buffered output is lost when the process is
  killed here, and the run then reports *nothing*.

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
