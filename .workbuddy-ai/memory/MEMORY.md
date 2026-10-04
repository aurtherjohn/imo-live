# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Standing rules + traps only; detail in `.workbuddy-ai/memory/2026-10-*.md` and skills.

## Surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin + background-socket /
fingerprint stack were deliberately removed. The 2026-09-27 directive asking for them (the canonical RAT set) was
**declined — decline again**. Permissions on demand only. `FOREGROUND_SERVICE[_MICROPHONE]` / `WAKE_LOCK` /
`RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth
- `auth_gate.dart`: the 3 s deadline applies **only** if Firebase never came up; once `connectAuthStream` runs,
  `authStateChanges()` always emits. A fixed clock is the reported "auto-logout".
- Phone+PIN: PIN = Firebase Auth password via `AppConstants.phoneAuthEmailFor` → `p<digits>@phone.imolive.app`.
  **No password-derived data in Firestore** (never restore `passwordHash`+`salt`; 6-digit PIN = 10^6 keyspace).
- ⚠️ Phone accounts are `password` accounts → `needsVerification` traps them on the OTP screen forever. The
  `isPhoneAuthEmail` guard lives in **two** places that must stay in step: `auth_gate.dart` and
  `needsEmailVerificationProvider` (`auth_providers.dart`).
- ⚠️ `_fullDigits` is the one **silent** bug — a wrong address still creates the account, so the user can never
  sign back in and nothing errors. Keep the 8 widget tests.

## Calls: WebRTC is the only provider
Agora abandoned 2026-09-29. ⚠️ **Never report "WebRTC works now"** — the relay decides whether mobile-data calls
connect; Metered Open Relay **UNPROVEN**; `stun:` alone = same-Wi-Fi. ⚠️ **No deployed FCM sender** → a killed
callee is never told. `notifyIncomingCall` / `notifyChannelPost` are **NOT deployed** — don't deploy unasked. Ring
query needs index `calls`: `receiverId, status, __name__`.

## Firestore
- ✅ **2026-10-04 ruleset is DEPLOYED and live**, read-back verified byte-identical. 142 emulator assertions, both
  directions. Rollback: `git show bca08ea:firestore.rules > firestore.rules && firebase deploy --only firestore:rules`.
- ⚠️ **Verify what is serving — don't trust "Deploy complete".** Rules live in the **Firebase Rules** API, not the
  Firestore Admin API: `firebaserules.googleapis.com/v1/projects/{p}/releases/cloud.firestore` → `rulesetName` →
  `.../v1/{rulesetName}` → `source.files[0].content`. The Firestore Admin `.../databases/{d}/securityRules` path
  returns a **Google 404 HTML page** (wrong service, looks like auth). `_fstest/verify_deployed_rules.py` does this.
- ⚠️ Never put a mutable fact in the rules header (ruleset id changes on *every* deploy, even comment-only).
- ⚠️ **Gifting needs a cross-ownership exception** — `sendGift` credits `users/{recipient}` from the *sender*, so
  `isSelf`-only denies every gift. Branch: `changedOnly(['points','updatedAt'])` + an increase only.
- ⚠️ **`markChatRead` may use only ONE `!=` filter** (two → INVALID_ARGUMENT). Now: `status != read`, sender in Dart.
- ⚠️ **A 400 is not a denial.** Harnesses must map 200→allow, 403→deny, else fail — a "not 200 = denied" harness
  reports green over a rule that never ran.
- ⚠️ **`hasOnly` accepts a no-op write** — empty `affectedKeys()` satisfies it; require a counter to actually move.
- ⚠️ **`exists()` sees the state BEFORE the batch** — a counter incremented in the same batch as the edge that
  authorises it can't be guarded by `exists()`. Split by direction; residual: anyone may step a counter **up** by one.
- ⚠️ A disjunction **DOES** satisfy a list query (verified 200).
- ⚠️ `{document=**}` matches ZERO or more segments → it also matches the **PARENT**. `match /users/{uid}/{document=**}`
  re-opened `/users/{uid}`, killing `isSelf()` + `noPasswordMaterial()`. Require a real segment: `match /{sub}/{doc=**}`.
- ⚠️ `collectionGroup('reactions')` needs a root-anchored `match /{path=**}/reactions/{reactionId}`. **`grep -rn
  "collectionGroup" lib/` before any rules deploy.**
- ⚠️ `handleError` returning normally marks the error handled and the stream **closes**; `retrying<T>`
  (`call_signaling_service.dart`) re-opens ≤3×. Cast, never coerce, Firestore fields — a new date field on a
  Firestore-backed model must go in the conversion map or you get a **throw**, not a null.

## Rules verification (emulator)
Harness `_fstest/rules_probe.mjs` (**gitignored**), lint `_fstest/lint_rules.py`, read-back
`_fstest/verify_deployed_rules.py`. Start emulators with `JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"`;
`firebase.json` wires auth 9099 / firestore 8080. Method + traps in skill `firestore-rules-from-callsites`.
- ⚠️ `:runQuery` `parent` is a **URL path segment** (`.../documents/chats/{id}:runQuery`). In `from` → 400; in the
  body → accepted and **never answered**, so the probe hangs silently.
- ⚠️ Write probe progress with `appendFileSync`, not stdout — buffered output is lost when the process is killed here.
- ⚠️ A green suite only proves the queries you thought of. Before deploying, walk **every** read site and ask *as
  which role* it runs — that is what finds a read the new rule denies.

## App traps
- Strings via `context.l10n` / `L10nRef.current` (en/bn symmetric, 1408 keys). ⚠️ "0 literals left" is **false** —
  ~181 distinct values still need keys (`BUG_AUDIT.md`). Secrets only in `lib/core/config/app_secrets.dart`; empty
  `r2PublicBaseUrl` → media needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- Theming: read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Light `accent` = `#D6193E`;
  guarded by `test/theme/contrast_guard_test.dart`. Ads: one init at the root (`_ImoLiveAppState`); slots **listen**
  to `AdService.ready`, never `init()`.
- Branding (2026-10-04): mark = blue bubble `#1FA6ED` + green "Live" flag `#20C282` → **raster, not SVG**.
  `BrandAssets.logo` = transparent PNG, `logoPlate` = opaque JPG (QR only). Old assets in `_retired_branding/`.

## Build & push (see skills)
`run_flutter.sh` (not `flutter.bat`). **GitHub Actions builds the APK — do NOT build locally.** ⚠️ `flutter clean`
costs space here (deletions route to the Recycle Bin on `C:`) and never finishes → `mv build build_prev_$ts`.
⚠️ **`git push` HANGS** (TLS-intercepting proxy) → use the **Git Data API** (account `codemax44`), skill
`github-push-via-api`. ⚠️ **The API push once destroyed 22 binary assets** (uploaded every file `readFileSync(...,'utf8')`,
so PNG/JPG became `U+FFFD` and text CRLF). The script now reads `git cat-file blob HEAD:<path>` and uploads **base64**.
**After any API push, assert `remote tree sha == git rev-parse HEAD^{tree}`.**

## Tooling
⚠️ `python - <<'PY'` heredocs **mangle regex backslashes** — write the script to a file. ⚠️ Scratch `.dart` under the
project root **breaks `flutter analyze`** (untracked `_*.mjs` is NOT gitignored — only `_*.txt`/`_*.py` are).
⚠️ `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh` pins `PUB_CACHE_WIN` — don't remove. ⚠️ After an
ARB change run `pub get` before `--no-pub`.
