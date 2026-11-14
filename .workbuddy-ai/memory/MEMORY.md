# Project memory — Imo LIVE (`tiger`)

Flutter app `imo_live`. Standing rules + traps only — narrative detail lives in
`.workbuddy-ai/memory/2026-10-*.md`, `firestore-rules-traps.md`, and the skills under
`~/.workbuddy-ai/skills/`.

## Never build the surveillance stack (declined 2026-09-27 — decline again)
Accessibility / notification-listener / boot-receiver / device-admin / background-socket / fingerprint were
deliberately removed. Permissions on demand only. `FOREGROUND_SERVICE[_MICROPHONE]`, `WAKE_LOCK`,
`RECEIVE_BOOT_COMPLETED` ARE declared — correct.

## Auth — Google + Phone only (email auth removed 2026-10-06)
- ⚠️ **There is no email/password sign-in any more.** `otp_screen.dart`, `AppRoutes.otp`, the
  `/auth/verify` route, `signUpWithEmail` / `signInWithEmail` / `sendPasswordReset` /
  `sendEmailVerification` / `ActionCodeSettings`, `isEmailVerified`, `needsEmailVerificationProvider` and
  the `imo://verify-email` intent-filter were all deleted. Do not re-add or reference them; older notes
  that describe them are obsolete.
- Phone+PIN = Firebase Auth password: `p<digits>@phone.imolive.app`. **Never store password material in
  Firestore** (a 6-digit PIN is a 10^6 keyspace). ⚠️ The two surviving `signInWithEmailAndPassword` calls
  in `firebase_auth_service.dart` ARE the phone path — do not "clean them up".
- ⚠️ `FadeSlideIn` lives in `app/app.dart`, `AppColors` in `app_tokens.dart`, `AppRoutes` in
  `core/constants/app_constants.dart` — three separate imports, all easily dropped by mistake.
- ⚠️ `_fullDigits` was the one **silent** failure: `startsWith(dial)` is not proof the code is present (India
  `91` vs a mobile starting `9`) → the account was created under a different address, unreachable, no error.
  Fixed 2026-10-04; keep all 10 `phone_login_test.dart` tests.

## Calls
WebRTC only; Agora abandoned 2026-09-29. ⚠️ **Never report "WebRTC works now"** — the relay decides whether
mobile-data calls connect; Metered Open Relay **UNPROVEN**; `stun:` alone = same-Wi-Fi. The `calls` index
(`receiverId, status`) is verified READY — don't re-open it. Incoming calls ring the **device ringtone** via
`RingtoneService` (static, `_isPlaying`-guarded). ⚠️ `_begin()` runs from a post-frame callback, so the
incoming branch needs a `mounted` guard — without it the ring starts after `dispose()` has already stopped
it and the phone rings forever with no UI to stop it.

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
- ⚠️ A `Row(mainAxisSize: min)` inside a `Center` hands non-flexible children **unbounded width** → a long
  label overflows instead of shrinking (`AuthPrimaryButton` did exactly this). Wrap it in
  `Flexible` + `FittedBox(BoxFit.scaleDown)`. Bengali labels are longer than English, so this bites in `bn` first.
- Strings via `context.l10n` / `L10nRef.current` (en/bn symmetric, **1601** keys). `_l10n_convert.py` sees only
  a literal *immediately* after a slot; `_l10n_expr_convert.py` covers ternaries / `??` fallbacks. ⚠️ `UI_ARG`'s
  slot list is itself a blind spot — `value:` was missing, which hid ~20 English strings across the whole
  settings surface. Secrets only in `lib/core/config/app_secrets.dart`.
- Read `context.c.onX` for foregrounds; raw `AppColors.X` only for fills. Ads init once at the root; slots
  **listen** to `AdService.ready`. Branding is raster, not SVG.

## Build & push
`run_flutter.sh`, not `flutter.bat`. **GitHub Actions builds the APK — do NOT build locally.** ⚠️ `flutter
clean` never finishes here (deletions route to the Recycle Bin) → `mv build build_prev_$ts`.
- ⚠️ `pubspec.yaml`'s `+N` IS the versionCode — `build.gradle.kts` reads `flutter.versionCode`/`versionName`.
  Never hardcode either in Gradle. Currently `1.0.0+2`.
- ⚠️ **`origin/main` is a parallel lineage.** Pushes have gone through the Git Data API, which creates
  server-side commits with *different* shas, so the local ref goes stale and `git log HEAD..origin/main`
  lies. Always resolve the true tip via the API and compare **trees**, never commits.
- `git push` **worked** on 2026-10-06 (the old "hangs forever" trap did not reproduce) — re-test it before
  reaching for `github-push-via-api`.
- ⚠️ A `git rebase` once wiped `.git/refs` entirely (git then reports `fatal: not a git repository` while
  `.git/` exists). Recovery: recreate `refs/heads|tags|remotes/origin|logs` by hand, then `mv .git/index
  aside` + `git add -A` to rebuild every blob from the working tree, then `git commit-tree -p <remote-tip>`.
  ⚠️ That `git add -A` **drops tracked-but-ignored files** — `android/gradlew`, `gradlew.bat` and
  `gradle-wrapper.jar` must be re-added with `git add -f` or CI breaks. Diff old vs new index to catch it.

## Tooling
⚠️ **Multiple `Edit` calls to the SAME file in ONE message clobber each other** (each rewrites the whole file,
so only one survives, yet all report success). Symptom: `flutter analyze` errors about names you *just added*.
**One edit per file per message.**
⚠️ `python - <<'PY'` heredocs mangle regex backslashes — write the script to a file. Scratch `.dart` at the
project root **breaks `flutter analyze`**. `PUB_CACHE` → write-protected `F:\pub-cache`; `run_flutter.sh` pins
it — don't remove. Run `pub get` after an ARB change. `flutter analyze` takes 2-9 min — run it backgrounded.

## ⚠️ Toolchain destroyed 2026-10-06 — re-check before trusting any command
`~/.workbuddy-ai/binaries/PortableGit/versions/1.2.0/bin/` was reduced to **just `bash.exe`** and
`C:\Users\ASUS\AppData\Local\Pub\Cache\` was **emptied**, mid-session, with ~6 GB freed on C:. Cause
unknown — **not Defender** (`Get-MpThreatDetection` clean) and not a running cleanup process. Consequences:
- The **`Bash` tool is dead** (`Top-level not found: …\PortableGit\versions\1.2.0\bin`), so `run_flutter.sh`,
  `git`, and the push scripts are all unusable. Re-test with a bare `echo` before planning around it.
- **Native-exe spawning from the PowerShell tool is silent** — `& whoami.exe` returns no output *and* no exit
  code; only PowerShell **cmdlets** work. The system Git at `C:\Program Files\Git\cmd\git.exe` therefore
  exists but is unreachable from here. `Invoke-RestMethod` is the only remaining network path (the GitHub API
  404s unauthenticated — `codemax44/tiger` is private).
- **A `safe-delete` guard latches and blocks every later deletion** in the session
  (`[safe-delete][SAFE_DELETE_BULK_GUARD_ERROR]`). It allows the first few files of a batch, then refuses even
  a single `Remove-Item`. So don't promise cleanup mid-session.
- ⚠️ **`PowerShell` `Out-File` defaults to UTF-16** and the `Read` tool sees that as binary. Always pass
  `-Encoding UTF8`.
- The repo is unaffected by all of the above, and root scratch `_*.txt`/`_*.py`/`_*.log` is **gitignored**
  (`.gitignore` line 159) — so `git add -A` cannot sweep it up.
