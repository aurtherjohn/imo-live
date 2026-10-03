# BUG_AUDIT.md — full app walk

**Date:** 2026-10-04
**Scope:** every screen, button, toggle, menu, list, dialog and navigation call in `lib/**`.
**Method:** mechanical Python sweeps over the whole tree (empty-handler, resource-lifecycle,
`AsyncValue` error branches, Firestore-listener error handling, `await`→`setState`/`context`
`mounted` guards, route-target resolution, raw literals, image error handling, permissions),
cross-checked by reading every hit. Static analysis only — see *Limitations*.

**Totals:** 14 fixed · 1 partially fixed (the l10n residual) · 5 deferred (root-caused, out of the 30-min/bug budget) · 7 classes verified clean.
*(14 = 13 app defects + 1 release-pipeline defect found while verifying the push — see the section below.)*

---

## Findings

| Screen | Element | Status | Notes |
|---|---|---|---|
| Chats | `ChatActionsSheet` → "Chat info" row | FIXED | Pushed `'${AppRoutes.chatInfo}/${chat.id}'` → `/chat/info/:id`, which **is not a registered route** — tapping it stranded the user on the router's "That screen doesn't exist." page. Replaced with `_openChatInfo()`, mirroring `ChatScreen._openChatInfo`: group/community → `groupInfo/:id`, channel/broadcast → toast, 1:1 → `contactInfo/:peerUid`. The dead `AppRoutes.chatInfo` constant was removed. |
| Chats | `_EmptyChats` (Unread / Favorites / Groups / Work tabs) | FIXED | 10 hardcoded strings with no ARB keys. Now `noChatsMessage`, `emptyChats{Unread,Favorites,Groups,Work}{Title,Message}`, `startAChat`. |
| Chats | `ChatActionsSheet` action rows + result toasts | FIXED | ~18 hardcoded labels (mark read/unread, pin/unpin, mute/unmute, archive/unarchive, add/remove favourite, disappearing-message labels). Localised; `hoursCount`/`minutesCount`/`secondsCount` added with `int` placeholders. |
| Chats | `ChatScreen._startReply` sender label | FIXED | Hardcoded `'You'` → `context.l10n.you` (key already existed). |
| Chats | `ChatScreen` star toasts | FIXED | `'Removed from starred'` / `'Added to starred'` → `starredRemoved` / `starredAdded`. |
| Chats | `MessageComposer` location share | FIXED | `'Location unavailable.'` → `locationUnavailable`. |
| Channels | `ChannelSettingsScreen._pickCategory` | FIXED | `setState` ran after the `showChoiceSheet` await with **no `mounted` guard** — dismissing the screen while the sheet was open threw on a defunct element. Guard added. |
| Channels | `ChannelSettingsScreen` monetization | FIXED | `'Channel approved'` / `'Application rejected'` → `channelApproved` / `applicationRejected`. |
| Channels | `isAppAdminProvider` (Firestore listener) | FIXED | The listener error was silently swallowed — a `try/catch` wrapped a **synchronous** call, so it could never catch the async stream error, and an unhandled stream error *closes the stream* (admin UI would silently stop updating). Added `.handleError(...)` + `debugPrint`. |
| Earn | `EarnScreen` rewarded-ad failure | FIXED | `'Could not load an ad'` → `couldNotLoadAnAd`. |
| Settings | `AccountSettingsScreen` | FIXED | `'App lock enabled'` → `appLockEnabled`; `'App lock disabled'` → `appLockDisabled` (new); `'Not available yet'` → `notAvailableYet` (new). |
| All screens | `ErrorState` raw exception dumps + hardcoded default title | FIXED | 8 screens fed `message: '$e'` into `ErrorState` — a **raw Dart exception rendered to the user** — and `ErrorState`'s default title was a hardcoded English `'Something went wrong'`, so the title stayed English in every locale. Added a shared `errorStateFor(context, error)` helper that `debugPrint`s the exception and renders a localised message, and a `somethingWentWrong` key for the title default. The 9th raw dump (`iToast(context, '$error')` in `login_screen`) was localised too. |
| All screens | Hardcoded user-facing literals (l10n) | PARTIALLY FIXED | **Three different numbers were reported for this and the first two were wrong — both retracted.** "628" was a crude sweep that counted log lines and field names. "13, of which 4 are untranslatable" came from the skill's slot-anchored scanner, which only matches a literal sitting *immediately* after the slot (`Text('x')`) and is therefore **blind to ternaries and `??` fallbacks** (`Text(flag ? 'Retry' : 'Retrying…')`). Scanning the *first argument expression* instead gave the real figure: **279 occurrences / 229 distinct values across ~50 files**. This session rewired the 67 occurrences (48 distinct values) whose English text already had an ARB key — pure reuse, no new translations. **~181 distinct values still need new keys: that is the honest residual**, and the scanner blind spot is the reason it was missed twice. The 9 raw-exception sites are fixed (row above). |
| Security | `e2ee_service.dart` | DEFERRED | `TODO`: static shared secret; no key handshake or safety-number verification. Needs protocol design — not a code fix. |
| Config | `app_secrets.dart` | DEFERRED | `TODO`: development keys. Production Firebase/R2 keys not supplied. |
| Ads | `ad_service.dart`, `rewarded_ad_service.dart` | DEFERRED | Google **test** ad unit IDs. Needs the AdMob account's real unit IDs. |
| Search | `directory_search_service.dart` | DEFERRED | `TODO`: prefix-range queries only; no Algolia/Typesense. Scalability limitation, not a defect. |
| Data | `repositories.dart` (`Remote*`) | DEFERRED | `TODO(remote)`: repositories are local-only; remote sync not implemented. |

---

## Release-pipeline defect (found while verifying the push)

| Component | Element | Status | Notes |
|---|---|---|---|
| CI / push tooling | `push_via_api.mjs` blob upload | FIXED | **The branding commit never actually built.** The GitHub API push path uploaded every changed file with `readFileSync(path, 'utf8')` + `encoding: 'utf8'` — it had no binary handling at all. Two consequences: (1) **22 binary assets were silently destroyed** — every launcher PNG and both `assets/images/` files, with each invalid byte replaced by `U+FFFD`, inflating them ~1.8× (e.g. `mipmap-mdpi/ic_launcher.png` 3110b → 5648b); (2) **32 text files were stored as CRLF instead of LF**, because `core.autocrlf=true` means the working tree holds CRLF while the committed blob holds LF. **Symptom:** `:app:mergeReleaseResources` → `AAPT: error: file failed to compile` on `mipmap-mdpi/ic_launcher.png`, so runs `99a499de`, `5e914c1b` and `26d5dab0` all failed; the last green build predates this work. **Why it was missed:** the icon verifier and every local check passed, because the local files were never wrong — the corruption existed only server-side, and the API push returns 200. **Detection:** compare `git rev-parse HEAD:<path>` against the blob sha in the remote tree; a size ratio near 1.8× on a binary is the tell. **Fix:** the script now reads exact committed bytes via `git cat-file blob HEAD:<path>` and uploads `encoding: 'base64'`; a repair commit restored all 54 blobs. Verified by the invariant **remote tree sha == `git rev-parse HEAD^{tree}`** and by re-walking all 376 remote blobs against the local commit (0 mismatches). |

---

## Verified clean (swept, no action needed)

| Area | Element | Status | Notes |
|---|---|---|---|
| All | Empty / dead button handlers | CLEAN | 0 hits for `onPressed/onTap/onChanged/…: () {}` no-ops. |
| All | Stray `print()` in `lib/` | CLEAN | 0 hits (logging goes through `debugPrint`). |
| All | Firestore `snapshots()` without error handling | CLEAN | 20 listener files; all have `handleError`/`onError`. |
| All | `setState` after `await` without a `mounted` guard | CLEAN | 1 real defect found & fixed (channel-settings category picker); every other candidate verified guarded. |
| All | Image loading without an error widget | CLEAN | Only `channel_post_card.dart` flagged; it uses `CachedNetworkImage.errorWidget`. |
| All | Navigation targets | CLEAN | New `test/app/route_targets_test.dart` resolves ~200 `push`/`go`/`replace` call sites against the registered route table (regression guard for the `chatInfo` bug above). |
| All | `Navigator.of(context).push` sites | CLEAN | MaterialPageRoute (media viewer, pickers), not named routes — correct. |

---

## Limitations

- **Static analysis, not a device walk.** Findings come from source sweeps plus reading every hit.
  Runtime-only behaviour (camera release on call teardown, WebRTC relay connectivity) is **not**
  covered here — see the project memory for what remains unproven.
- The l10n figure is **measured**, not estimated: the skill's scanner matches on the *argument
  site* (`Text(…)`, `label:`, `hint:`, `iToast(…)`), which is what keeps route paths, Firestore
  field names and asset paths out without a blocklist. A cruder "any prose-looking literal" sweep
  over-reported ~628; that number was wrong and is retracted.
