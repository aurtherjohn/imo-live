# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Deep detail lives in the date logs and **skills**; this file is the
standing rules only.

## Standing decision: the C2 / surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin and the
background-socket + fingerprint stack were deliberately removed. The 2026-09-27 directive asking
for them (the canonical RAT set) was **declined; decline again**. Permissions on demand only.
`FOREGROUND_SERVICE[_MICROPHONE]` / `WAKE_LOCK` / `RECEIVE_BOOT_COMPLETED` ARE declared — that is
correct (ongoing-call notification, WebRTC audio session, notification rescheduling).

## The 9-phase master directive — COMPLETE (reports at repo root)
All nine phases shipped 2026-10-01 → 10-02. Deliverables: `AUDIT_REPORT_V2.md` (Ph4),
`POLISH_REPORT.md` (Ph8), `FINAL_REPORT_9PHASE.md` (Ph9 summary). Detail per phase: logs
`2026-10-01.md` (Ph1–4), `2026-10-02.md` (Ph5–9).
- Ph1 banners/native ads removed (only `AdSlotLabel` left); interstitial+rewarded kept.
- Ph2 video-call leak: **teardown was already correct**; real bug was sticky `_isVideo` on the
  session-lived `callServiceProvider`. Fixed via `_startedFromClean()`. ⚠️ Camera release is
  **UNPROVEN on device** — `flutter_tester` has no flutter_webrtc, so the renderer path is
  unobservable; 2 of 3 tests were discarded for passing with the fix disabled.
- Ph3 channels merged into the chat list (`ChatRow` sealed + `mergeChatRows`, keyed by
  `RowKeys`). ⚠️ `RowKeys.chat(id)` needs its kind **prefix** (chat: vs channel:) — a bare id
  collides in `ValueKey`; `RowKeys.locationOf` strips it for the route.
- Ph4 audit → `AUDIT_REPORT_V2.md`. The big find (Ph3 regression): `Channel.fromJson` cast a
  Firestore `Timestamp` to `String` → threw on every read → broke the whole Chats tab.
  ⚠️ **Any new date field on a Firestore-backed model must be added to the conversion map**,
  or you get a throw, not a null. `Channel` is the only model crossing that boundary.
- Ph5 animations: `appPage()` transition on all routes, `ListStagger`, `Haptics` helper,
  shimmer. ⚠️ `prefersReducedMotion` reads `ReducedMotionScope`, NOT `MediaQuery` — a bare
  `MediaQuery(disableAnimations:true)` test proves nothing. ⚠️ Never regex-convert
  `builder:` → `pageBuilder:` (truncates multi-arg constructors).
- Ph6 vector assets: brand art SVG-only (`flutter_svg`); the only raster is the app's own
  gradient logo (`BrandMark`), which is correct — see Branding below. Adaptive launcher icon
  added. ⚠️ `analysis_options.yaml` excludes `android/**`, so analyze proves nothing about the
  icon XML — only a Gradle build validates it.
- Ph7 WhatsApp/MX-Player video player (`lib/core/widgets/video_view.dart`): tap chrome,
  double-tap seek, long-press 2×, vertical brightness/volume, horizontal scrub. ⚠️ Keep
  `onDoubleTap` ABSENT — with `onTap` present it re-breaks the tap/double-tap race.
  Ph7 also fixed two dead features: `thumbnailPath` and `durationMs` were never written.
- Ph8 polish → `POLISH_REPORT.md`; fixed light-theme contrast (was failing AA) — see Theming.
- Ph9 clean / pub get / analyze / test / release build (EXIT=0, 3 ABIs). ⚠️ **`dist/` is now
  EMPTY** — artifacts were not retained; re-run the build to republish. ⚠️ `flutter clean`
  COSTS space here (deletes route to the Recycle Bin on `C:`) — see Build.

## Auth: never treat "no event yet" as signed out
`auth_gate.dart`: the 3 s deadline applies **only** when Firebase never came up; once
`connectAuthStream` runs, `authStateChanges()` always emits — a fixed clock is the reported
"auto-logout". `setPersistence` is web-only.

## Phone + PIN sign-in (2026-10-03)
Number = identifier, PIN = Firebase Auth password, under `AppConstants.phoneAuthEmailFor('8801712345678')`
→ `p8801712345678@phone.imolive.app`. **Nothing password-derived is written to Firestore.**
- ⚠️ **Do NOT "restore" the requested `passwordHash` + `salt` on `users/{uid}`** — rules make it
  readable by every signed-in user and a 6-digit PIN is a 10^6 keyspace. A PIN is a password;
  only a rate-limiting server may hold one.
- ⚠️ A phone account is a `password` account, so `needsVerification` **traps it on the OTP screen
  forever**. The `isPhoneAuthEmail` guard lives in **two** places that must stay in step:
  `auth_gate.dart` and `needsEmailVerificationProvider` (`auth_providers.dart`).
- Deriving the address is what lets signup+login run with **zero Firestore reads while signed
  out** (rules require `request.auth != null`). Uniqueness from `createUserWithEmailAndPassword`;
  the `phones/{digits}` + `usernames/{handle}` claim is one transaction (`_claimPhoneIdentity`).
- ⚠️ `_fullDigits` is the one **silent** bug — a wrong address still creates the account, so the
  user can never sign back in and nothing errors. Keep the 8 widget tests. Country table is
  hand-rolled (`lib/core/models/country.dart`) to avoid a re-resolve + ~48 min rebuild.

## Calls: WebRTC is the ONLY provider
- Agora abandoned 2026-09-29; `agora_*` files are unreachable (absent from `libapp.so`, all ABIs).
- ⚠️ **Never report "WebRTC works now".** The relay decides whether mobile-data calls connect;
  the default Metered Open Relay is a rate-limited public test service and **could not be
  validated**. **UNPROVEN.** `stun:` alone only covers same-Wi-Fi.
- ⚠️ **No deployed FCM sender** → a killed callee is never told. `notifyIncomingCall` and
  `notifyChannelPost` are **NOT deployed** — do not deploy without the Boss asking.
- Ring query needs index `calls`: `receiverId, status, __name__` (READY), else the phone never rings.

## Firestore
- ⚠️ **Deployed rules are still wide open** (`if request.auth != null` on `/{document=**}`) — any
  signed-in user reads+writes every document. **Biggest outstanding risk; a deploy, not a code
  change, and it needs the Boss's authorisation.**
- `firestore.rules` exists and `firebase.json` points at it, but it is **NOT deployed**.
  ⚠️ **Rules are OR'd** — a permissive `match /{document=**}` silently undoes every restriction.
  The file enumerates collections and lets unlisted ones **deny** (fail closed).
  `chats`/`messages`/`points_transactions`/`channel_keys` are still pinned at today's
  permissiveness so the deploy can't break a feature; tightening them is outstanding.
- ⚠️ **`{document=**}` matches ZERO or more segments, so it also matches the PARENT document.**
  `match /users/{uid}/{document=**}` re-opened `/users/{uid}` and made `isSelf()` +
  `noPasswordMaterial()` dead code (emulator returned 200 for a `{passwordHash:…}` write to
  another user's profile). Fix: require a real segment — `match /{sub}/{doc=**}`. Applies to
  every collection with subcollections. Only the emulator caught it; analyze/lint/re-read passed.
- ⚠️ **`ChannelService.watchMyReactions` uses `collectionGroup('reactions')`, which NO
  path-scoped rule can satisfy** (403 kills the whole query). Needs a root-anchored
  `match /{path=**}/reactions/{reactionId}`. **Before deploying any ruleset,
  `grep -rn "collectionGroup" lib/`.** Two deploy-breaking bugs were found this way.
- ⚠️ **A failing listener must never be silent.** `handleError` returning normally *marks the
  error handled*, and a snapshot stream **closes when it errors**. `retrying<T>` re-opens ≤3× and
  **rethrows**. Cast, never coerce, Firestore fields (`(d['x'] as num?)?.toInt()`).

## Ads (AdMob, test ids)
**One init, at the root** (`_ImoLiveAppState`), which owns `dispose()`; slots **listen** to
`AdService.ready` — never `init()` from a slot (its timer outlives the tree and trips
`flutter_test`). Banners/native were removed in Ph1; interstitial + rewarded remain.

## Architecture traps
- URLs/credentials live only in `lib/core/config/app_secrets.dart`, `static const` → plaintext in
  `libapp.so`. Only a byte-search (ASCII **and** UTF-16LE) settles "in the binary".
- `r2PublicBaseUrl` is **empty** → second-device media needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- **User-visible strings go through `context.l10n`** (1,371 keys, en/bn symmetric) or
  `L10nRef.current` in services — skill `flutter-hardcoded-string-localization`.
  ⚠️ **The "0 literals left" claim is false** — `chats_screen.dart` `_EmptyChats` still has 10
  literals with no ARB keys. Needs a real l10n pass, not a counter run.
  ⚠️ **A string counter is only as good as its argument whitelist** (this one reported 189 as 28).
  Never trust a residual count without listing it.

## Theming: foreground vs fill is a real distinction
`AppColorScheme` carries `onSuccess/onWarning/onInfo/onDanger/online` because the raw brand hues
fail WCAG AA **on white** (green 1.98, amber 1.83, blue 2.53, red 3.41). **Read `context.c.onX`
for any foreground; use raw `AppColors.X` only for fills/tints.** Light `accent` is `#D6193E`
(5.16:1), NOT the brand `#FF2D55` (3.65:1) — the brand hue is fine on dark only. Dark keeps the
raw hues verbatim. Guarded by `test/theme/contrast_guard_test.dart`. ⚠️ A mechanical
`AppColors.X → context.c.onX` sweep breaks in 3 silent ways (duplicated ternaries, `const`
contexts, context-free getters) — see `2026-10-02.md` before repeating one.

## Build
`run_flutter.sh` (not `flutter.bat`). ⚠️ **Compare sha256, never size**; `dist/*.sha1` sidecars
hold **sha256** (64 hex), not sha1. Regenerate them on republish (and note `dist/` is currently
empty). Space: skill `windows-disk-reclaim`.
- ⚠️ **`flutter clean` COSTS space here AND does not finish** — deletes route to the Recycle Bin
  on `C:`, so it frees nothing and kills the incremental cache; the per-file delete over a
  25k-file `build/` gets SIGTERM'd, leaving the tree partially deleted. **Substitute
  `mv build build_prev_$ts`.** The reclaim that works is truncating the Bin's project-build
  payloads (~4.26 GiB in seconds; skip `S-1-5-18`, Windows path length at `$I` offset 24, UTF-16LE).
- A release `--split-per-abi` build needs **~5.6 GiB transient**; cold `assembleRelease` ≈ 45 min.
- `minSdk = 24` but adaptive icons only apply API 26+, so API 24–25 falls back to `mipmap-*dpi`
  PNGs — keep `ic_launcher_round.png` at all five densities or that range has no round icon.

## Branding
The mark is a **gradient** speech-bubble ring ("imo LIVE"), so it is **raster, not SVG** — the
"every logo ships as SVG" convention does not apply, and tinting it with `BlendMode.srcIn` would
flatten it. `BrandMark` (raster) sits beside `BrandIcon` (SVG) in `brand_assets.dart`;
`BrandAssets.logo` = transparent PNG, `logoPlate` = opaque white-plate JPG (QR screen only).
Icon tile is flat **`#141417`**, not a gradient. Foreground sits in the **66dp/108dp** safe zone;
the `monochrome` layer is a **separate silhouette**. Workflow + scripts: skill
`flutter-android-app-branding`. Retired files in `_retired_branding/`.

## Tooling
⚠️ **`python - <<'PY'` heredocs mangle regex backslashes** on this host — write the script to a
file and run it. (Same for `cat <<EOF` with backticks/quotes.)
- ⚠️ **Scratch `.dart` files anywhere under the project root break `flutter analyze`** (produced
  187 bogus errors once). Move them out of the tree before analyzing.
- ⚠️ **`PUB_CACHE` is a persistent user env var pointing at `F:\pub-cache`, now write-protected**
  (`errno = 19`) → every `pub get` fails; it hides until a dependency is edited. `run_flutter.sh`
  pins `PUB_CACHE_WIN` (`C:/Users/ASUS/AppData/Local/Pub/Cache`); override with `TIGER_PUB_CACHE`.
  **Do not remove that line.**
- ⚠️ `flutter analyze`/`test` need `--no-pub` **only** when `pubspec.yaml` is already resolved;
  after an ARB change run `pub get` first or `gen-l10n` leaves `app_localizations*.dart` stale and
  every new `context.l10n.x` is an `undefined_getter`.
