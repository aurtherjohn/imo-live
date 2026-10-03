# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Mechanics live in **skills** and `2026-09-*.md`.

## Standing decision: the C2 / surveillance stack stays removed
Accessibility / notification-listener / foreground-service / boot-receiver / device-admin and the
background-socket + fingerprint stack were deliberately removed. The 2026-09-27 directive asking for
them (the canonical RAT set) was **declined; decline again**. Permissions on demand only.

## Auth: never treat "no event yet" as signed out
`auth_gate.dart`: the 3 s deadline applies **only** when Firebase never came up; once
`connectAuthStream` runs, `authStateChanges()` always emits — a fixed clock is the reported
**"auto-logout"**. `setPersistence` is web-only.

## Phone + PIN sign-in (added 2026-10-03)
The number **is** the identifier and the PIN **is** the Firebase Auth password, under an address
derived from the digits: `AppConstants.phoneAuthEmailFor('8801712345678')` →
`p8801712345678@phone.imolive.app`. **Nothing password-derived is ever written to Firestore.**
- ⚠️ **Do NOT "restore" the requested `passwordHash` + `salt` on `users/{uid}`.** The rules make that
  field readable by every signed-in user, and a 6-digit PIN is a 10^6 keyspace — enumerable offline
  in under a second. A PIN is a password, and only a server that rate-limits can hold one.
- ⚠️ **A phone account is a `password` account**, so `needsVerification = isPasswordAccount &&
  !emailVerified` **traps it on the OTP screen forever** (the derived address has no mailbox). The
  guard `AppConstants.isPhoneAuthEmail(user.email)` lives in **two** places that must stay in step:
  `auth_gate.dart` and `needsEmailVerificationProvider` (`auth_providers.dart`).
- Deriving the address is what lets **signup and login both run with zero Firestore reads while
  signed out** — mandatory, since the rules require `request.auth != null`. Uniqueness comes from
  `createUserWithEmailAndPassword`'s `email-already-in-use`, and the
  `phones/{digits}` + `usernames/{handle}` claim is one **transaction** (`_claimPhoneIdentity`).
- `phone_index` was deliberately **not** created — `phones/{digits}` already is that index.
- ✅ **Verified 2026-10-03** without an APK: 41 emulator assertions (signup → same-uid login, duplicate
  refused `EMAIL_EXISTS`, identical refusal for wrong PIN vs unknown number) and 8 widget tests that
  capture what the screen submits (`01712345678` → `8801712345678`; never doubled; `+91` re-codes).
  ⚠️ `_fullDigits` is the one **silent** bug here — a wrong address still creates the account, so the
  user can never sign back in and nothing errors. Keep those tests.
- Country table is hand-rolled (`lib/core/models/country.dart`, ~250 rows, flag emoji derived from
  the ISO code) rather than `country_picker`, to avoid a re-resolve + ~48 min rebuild here.

## Calls: WebRTC is the ONLY provider
- Agora abandoned 2026-09-29; `agora_*` files are **unreachable** (absent from `libapp.so`, all ABIs).
- ⚠️ **Never report "WebRTC works now".** The relay decides whether mobile-data calls connect; the
  default Metered Open Relay is a rate-limited public test service and as of 2026-09-29 **could not
  be validated**. **UNPROVEN.** `stun:` alone only covers same-Wi-Fi.
- ⚠️ **No deployed FCM sender** → a killed callee is never told. `notifyIncomingCall` is **NOT
  deployed** — do not deploy.

## Firestore
- ⚠️ **Deployed rules are still wide open** (`if request.auth != null` on `/{document=**}`) — any
  signed-in user reads+writes every document. **Biggest outstanding risk.**
- `firestore.rules` now **exists** (2026-10-03) and `firebase.json` points at it, but it is
  **NOT deployed** — writing the file changes nothing until `firebase deploy --only firestore:rules`.
  ⚠️ **Rules are OR'd**, so a permissive `match /{document=**}` silently undoes every restriction in
  the file. That is why it enumerates collections and lets unlisted ones **deny** (fail closed).
  `chats`/`messages`/`points_transactions`/`channel_keys` are still pinned at today's permissiveness
  so the deploy cannot break a feature — tightening them is outstanding work.
- ⚠️ **`{document=**}` matches ZERO or more segments, so it also matches the PARENT document.**
  `match /users/{uid}/{document=**}` re-opened `/users/{uid}` itself and made `isSelf()` +
  `noPasswordMaterial()` **dead code** — the emulator returned **200** for a `{passwordHash: …}` write
  to another user's profile. Fixed by requiring a real segment: `match /{sub}/{doc=**}`. Applies to
  every collection with subcollections. **A rules file that reads correctly can still not be
  enforced** — only the emulator caught this; analyze, lint and re-reading all passed on the broken
  version.
- **Verifying rules without an APK:** `firebase emulators:start --only auth,firestore` +
  `node _verify_phone_auth.mjs` (dependency-free Node harness over the REST APIs, 49 assertions,
  exit 0). `firebase.json` needs an `emulators` block or auth refuses to start; `java` must be on
  `PATH` (`<android studio>/jbr`). ⚠️ **`Bearer owner` is an admin bypass** (fixtures only);
  **a bogus bearer is 400 `invalid jwt`, never 403** — "signed out" means *no* header; any decodable
  JWT is trusted (`alg: none` included). Full detail: skill `firestore-rules-from-callsites` Step 7.
- ⚠️ **`ChannelService.watchMyReactions` uses `collectionGroup('reactions')`, which a path-scoped
  rule CANNOT satisfy** — `channels/{id}/{sub}/{doc=**}` matches the documents and Firestore still
  answers `403 No matching allow statements`, killing the whole query. It needs a root-anchored
  `match /{path=**}/reactions/{reactionId} { allow read: if signedIn(); }`. **Before deploying any
  ruleset, `grep -rn "collectionGroup" lib/`.** Two deploy-breaking bugs were found this way and
  neither was visible to analyze, lint, or re-reading the file.
- Ring query needs index `calls`: `receiverId, status, __name__` (READY), else the phone never rings.
- ⚠️ **A failing listener must never be silent.** `handleError` returning normally *marks the error
  handled*, and a snapshot stream **closes when it errors**. `retrying<T>` re-opens ≤3× and
  **rethrows**. Cast, never coerce, Firestore fields (`(d['x'] as num?)?.toInt()`).

## Ads (AdMob, test ids)
**One init, at the root** (`_ImoLiveAppState`), which owns `dispose()`; slots **listen** to
`AdService.ready` — never `init()` from a slot (its timer outlives the tree and trips
`flutter_test`). `nativeFactoryRegistered` is **false** → `AdNativeSlot` degrades to a banner.

## Architecture traps
- URLs/credentials live only in `lib/core/config/app_secrets.dart`, `static const` → plaintext in
  `libapp.so`. Only a byte-search (ASCII **and** UTF-16LE) settles "in the binary".
- `r2PublicBaseUrl` is **empty** → second-device media needs `--dart-define=R2_PUBLIC_BASE_URL=…`.
- **User-visible strings go through `context.l10n`** (1,371 keys, en/bn symmetric) or
  `L10nRef.current` in services — skill `flutter-hardcoded-string-localization`.
  ⚠️ **The "0 literals left" claim is false as of 2026-10-03** — `chats_screen.dart` `_EmptyChats`
  still has 10 literals (`'No favorites yet'`, `'No groups yet'`, `'No work chats'`, `'Start a chat'`,
  …) with no ARB keys. Needs a real l10n pass, not a counter run.
- ⚠️ **A string counter is only as good as its argument whitelist.** This one reported 189 residual
  literals as 28. Never trust a residual count without listing it.

## Theming: foreground vs fill is a real distinction
`AppColorScheme` carries `onSuccess/onWarning/onInfo/onDanger/online` because the raw brand hues
fail WCAG AA **on white** (green 1.98, amber 1.83, blue 2.53, red 3.41). **Read `context.c.onX` for
any foreground; use raw `AppColors.X` only for fills/tints.** Light `accent` is `#D6193E` (5.16:1),
NOT the brand `#FF2D55` (3.65:1) — the brand hue is fine on dark only. Guarded by
`test/theme/contrast_guard_test.dart`. ⚠️ A mechanical `AppColors.X → context.c.onX` sweep breaks in
3 silent ways (duplicated ternaries, `const` contexts, context-free getters) — see `2026-10-02.md`
before repeating one.

## Build
`run_flutter.sh` (not `flutter.bat`). ⚠️ **Compare sha256, never size**; regenerate `dist/*.sha1` on
republish. Space: `windows-disk-reclaim`.
- ⚠️ **`flutter clean` COSTS space here AND does not finish** — deletes route to the Recycle Bin on
  `C:`, so it frees nothing and kills the incremental cache; and the per-file delete over a 25k-file
  `build/` gets SIGTERM'd by the sandbox, leaving the tree *partially* deleted. Measured 2026-10-03.
  **Substitute `mv build build_prev_$ts`** — same space profile, instant, recoverable. The reclaim
  that works is truncating the Bin's own project-build payloads (~4.26 GiB in seconds).
- ⚠️ `dist/*.sha1` sidecars hold **sha256** (64 hex), not sha1 — match the convention, not the name.
- A release `--split-per-abi` build needs **~5.6 GiB transient**; cold `assembleRelease` ≈ 45 min.
  A cold `assembleDebug` (after parking `build/`) measured **47m54s** on 2026-10-03.
- `minSdk = 24` but adaptive icons only apply API 26+, so API 24–25 falls back to `mipmap-*dpi` PNGs.
  `ic_launcher_round.png` now exists at all five densities and `android:roundIcon` is declared
  (added 2026-10-03, superseding the earlier removal) — keep the PNGs or API 24–25 has no round icon.

## Branding (replaced 2026-10-03)
The mark is a **gradient** speech-bubble ring ("imo LIVE"), so it is **raster, not SVG** — the
"every logo ships as SVG" convention does not apply to it, and tinting it with `BlendMode.srcIn`
would flatten it. `BrandMark` (raster) now sits beside `BrandIcon` (SVG) in `brand_assets.dart`;
`BrandAssets.logo` = `assets/images/app_logo_transparent.png`, `logoPlate` = the opaque white-plate
`app_logo.jpg` (used only on the QR screen's white card). Icon tile is flat **`#141417`**, not a
gradient: the ring's own gradient runs along the same axis, so a gradient tile erases its left half.
Foreground sits in the **66dp/108dp** safe zone; the `monochrome` layer is a **separate silhouette**
(alpha alone turns the "LIVE" pill into a blob — punch the near-white letterforms back out).
Workflow + scripts: skill **`flutter-android-app-branding`**. Retired files (no VCS here) are in
`_retired_branding/`.

## Tooling
⚠️ **`python - <<'PY'` heredocs mangle regex backslashes** on this host — a scan silently returned
"0 sites" while grep found 135. **Write the script to a file and run it.** (Same for `cat <<EOF`
appends containing backticks or quotes — write the block with the editor, then `cat file >> target`.)
- ⚠️ **`PUB_CACHE` is a persistent *user* env var pointing at `F:\pub-cache`, and that volume is now
  write-protected** (`OS Error: The media is write protected, errno = 19`). Every `pub get` fails.
  It hides because `analyze`/`build` skip `pub get` while `pubspec.yaml` is unchanged — it only
  explodes the moment a dependency is edited. `run_flutter.sh` now pins `PUB_CACHE_WIN`
  (`C:/Users/ASUS/AppData/Local/Pub/Cache`, which is what `.dart_tool/package_config.json` already
  resolves against); override with `TIGER_PUB_CACHE`. **Do not remove that line.**
- ⚠️ `flutter analyze` / `flutter test` need `--no-pub` **only** when `pubspec.yaml` is already
  resolved; after an ARB change you **must** run `pub get` first or `gen-l10n` leaves
  `app_localizations*.dart` stale and every new `context.l10n.x` is an `undefined_getter`.

