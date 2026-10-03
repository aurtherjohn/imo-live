# FINAL REPORT — Phase 9 (9-phase overhaul)

Release build of `imo_live` (Imo LIVE) 1.0.0+1, package `com.imo.live`.

This supersedes the Sep 28 `FINAL_REPORT.md`, which covered the *previous*
directive (audit / earn / channels / call UI). That file is left in place as
history. This one covers the nine-phase overhaul.

`flutter analyze` clean · **398 tests passing** · three per-ABI release APKs
built, published and verified.

---

## 1. Pipeline result

| step | result |
| --- | --- |
| `flutter clean` | ⚠️ ran, then **interrupted** — see §3 |
| `flutter pub get` | resolved (68 packages have newer, constrained versions) |
| `flutter gen-l10n` | regenerated from the EN/BN ARB files |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **398 passed, 9 skipped** |
| `flutter build apk --release --split-per-abi` | **EXIT=0** in 2685.6 s |

Environment: Flutter 3.47.3 stable · Dart 3.13.3 · Gradle 9.3.1 · minSdk 24.

---

## 2. Artifacts published to `dist/`

| ABI | bytes | sha256 |
| --- | --- | --- |
| arm64-v8a | 130,826,144 | `3aa72b549752aba5f826a90dcbc036712c6b0e898957358af4480fe9877ba5cf` |
| armeabi-v7a | 105,426,368 | `9c51c5ca809d20a0af5016236d00f11f5dcad36088627cbd96c0dcc22bb03ce4` |
| x86_64 | 115,435,947 | `e8deeaa8c3116e22c36e9fc72030fe8dce2e6d5b27bc50882cc321b66a89063f` |

Each carries a `.sha1` sidecar, and all three sidecars were re-verified against
their APK. **The sidecar extension is misleading — it holds sha256** (64 hex),
matching the existing convention in this repo.

The hashes differ from the 2026-09-30 build (`d014673d…`), confirming these are
genuine rebuilds rather than copied artifacts.

---

## 3. The disk problem, and what actually solved it

`C:` had **5.9 GiB** free. A split-per-ABI release build needs roughly **5.6 GiB
transient**, so this was not going to fit.

**`flutter clean` made it worse, and that is worth stating plainly.** After it
had removed `build/` down to 294 MB from 2.6 GB, free space had gone
**5.9 → 4.71 GiB**. On this host every delete routes to the Recycle Bin, which
lives on `C:`. A "clean" therefore relocates bytes into the Bin, frees nothing,
and destroys the incremental cache the next build depends on. I interrupted it
once the measurement showed the direction of travel.

The reclaim that worked: the Bin held **21,206 files / 4.27 GiB of this project's
own build output** — `.so`, `.apk` and `.dill` payloads from the interrupted
clean and earlier builds. I parsed each `$I` record's original path and truncated
only the `$R` payloads pointing back inside the project, so files deleted by hand
were never touched.

> **13,780 records scanned · 7,385 payloads truncated · 4.26 GiB freed ·
> `C:` 4.70 → 8.97 GB**

A Recycle Bin watchdog was then armed for the build; free space never fell below
**6.29 GiB** and the build finished with the Bin drained.

---

## 4. What the build proved that `flutter analyze` could not

This is the verification deferred from Phase 6.

- **The adaptive launcher icon is valid.** `ic_launcher_background` and
  `ic_launcher_foreground` both resolve into the compiled `resources.arsc`, so
  the AAPT2 inline gradient (`aapt:attr` + `<gradient>`) compiled cleanly. A
  malformed resource fails the build, so `EXIT=0` is the proof.
- **The icon reference is correct** — `roundIcon` is absent from the shipped
  manifest, as intended after the fix below.

**A real defect was found and fixed in the process.** `minSdk` is **24**, but
`mipmap-anydpi-v26` only applies from API 26 — so Android 7.0/7.1 falls back to
the legacy `mipmap-*dpi` PNGs. There is **no `ic_launcher_round.png` at any
density**, which meant `android:roundIcon="@mipmap/ic_launcher_round"` had no
resource to resolve on API 24–25. I removed the attribute: the round variant was
byte-identical to the normal icon, and adaptive icons are launcher-masked anyway,
so the separate round resource was redundant. The legacy PNGs are on-brand
(`#FF2D55` with white artwork), so API 24–25 still renders correct artwork.

**APK structure verified:**

- zip integrity OK on all three
- exactly **one** `libflutter.so` and **one** `libapp.so` per APK
- each APK split cleanly to a single ABI (847 / 847 / 846 entries)

---

## 5. Permission audit of the shipped manifest

The standing decision to keep the C2 / surveillance stack removed **holds in the
built artifact**:

| permission | present |
| --- | --- |
| `BIND_ACCESSIBILITY_SERVICE` | **absent** |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | **absent** |
| `BIND_DEVICE_ADMIN` | **absent** |
| `SYSTEM_ALERT_WINDOW` | **absent** |
| `QUERY_ALL_PACKAGES` | **absent** |

`FOREGROUND_SERVICE[_MICROPHONE]`, `WAKE_LOCK` and `RECEIVE_BOOT_COMPLETED` **are**
present, and that is correct rather than a regression: they are declared in this
app's own manifest for the ongoing-call notification, the WebRTC audio session
and notification rescheduling respectively, with `tools:node="remove"` guards
stripping the C2 permissions inherited from libraries.

---

## 6. Unfinished work — stated honestly

Known, recorded gaps rather than surprises:

1. **Firestore rules are still wide open** (`if request.auth != null` on
   `/{document=**}`). Any signed-in user can read and write every document. This
   remains **the biggest outstanding risk in the project**, and it is not a code
   change — it is a deploy that needs your authorisation.
2. **WebRTC calls are UNPROVEN on mobile data.** The default Metered Open Relay is
   a rate-limited public test service and could not be validated; `stun:` alone
   covers only same-Wi-Fi. I will not claim calls work.
3. **No deployed FCM sender** → a killed callee is never notified.
   `notifyIncomingCall` is not deployed and should not be.
4. **`r2PublicBaseUrl` is empty** → second-device media needs
   `--dart-define=R2_PUBLIC_BASE_URL=…`.
5. **Accessibility is partial.** All interactive icon buttons are labelled, but
   only 4 of 59 screens use `Semantics(` — no heading structure, no live regions
   for call/typing state.
6. **110 `fontSize:` literals remain** (94 of them on-scale).

---

## 7. Phases 1–9

| phase | outcome |
| --- | --- |
| 1 | banner/native ad widgets removed; interstitial + rewarded kept |
| 2 | WebRTC teardown audited; video-call leak fixed |
| 3 | chats + channels merged into one sorted list; admin/visitor modes; unread via `lastReadAt` |
| 4 | full audit → `AUDIT_REPORT_V2.md`; crashes, dead buttons, broken sync fixed |
| 5 | page transitions, list stagger, shimmer skeletons, haptics, micro-interactions |
| 6 | SVG-only brand art; adaptive launcher icon added → validated in Phase 9 |
| 7 | gesture-driven video player; **two dead features fixed** — thumbnails and durations had never been written |
| 8 | light-theme contrast fixed (was failing AA at 1.83–3.65:1); type scale snapped; labels added → `POLISH_REPORT.md` |
| 9 | clean, resolve, analyze, test, release build, publish, verify |

Test count grew **370 → 398** across the phases, entirely from new regression
guards rather than edits to existing tests.
