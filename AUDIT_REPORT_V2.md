# AUDIT_REPORT_V2

Full walk of every screen and interactive element after Phases 1–3.

Method: mechanical sweeps over the source (each sweep is a script, not a read),
then a manual read of every hit. The sweeps are listed so they can be re-run and
so a clean result can be told apart from a sweep that never ran.

Baseline: `flutter analyze` clean, `flutter test` 370 passing / 9 skipped.

---

## SEVERITY 1 — Crashes and silent failures

### 1.1 `Channel.fromJson` threw on every Firestore read — **FIXED**

**This is the most serious finding of the audit, and it was introduced by
Phase 3.**

`Channel` has four date fields. Firestore documents carry three of them as
server timestamps, which come back as a `Timestamp` — not a `String`.

- `addPost` writes `lastMessageAt` via `FirebaseTime.now()` →
  `FieldValue.serverTimestamp()` (`channel_service.dart:613`).
- `markChannelRead` writes `lastReadAt` the same way (`:658`).
- `ChannelFirestoreService.channelFromDoc` converts only `createdAt` and
  `lastUpdateAt` to ISO strings.
- `Channel.fromJson` then evaluates `json['lastMessageAt'] as String`.

A `Timestamp` is not a `String`, so the cast throws `_TypeError`. Not a null,
not a missing value — a throw, on read, every time.

**Blast radius:** any channel with a post made the merged Chats tab and the
channel screen fail to load. Since Phase 3 merged channels into the chat list,
that is the whole first screen.

**Fix:** added `lastMessageAt` and `lastReadAt` to the conversion map
(`channel_service.dart:1058-1059`), with a doc comment stating that a new date
field on `Channel` must be added there.

**Proof, not assertion:** `test/core/channel_timestamps_test.dart` (9 tests).
With the fix reverted, **7 of the 9 fail** with
`type 'Timestamp' is not a subtype of type 'String' in type cast`. The test was
written first, run against the broken code to confirm red, then the fix applied.

**Why it was not caught earlier:** the channels were only ever read through the
Hive mirror in tests, and the two new fields were added on the same day the
conversion map was last touched. No existing test fed a real `Timestamp`
through `channelFromDoc`.

**Scope check:** every other model (`Chat`, `Message`, `Contact`, `Status`,
`Group`) deserialises only from Hive — `local/database/` — never from a raw
Firestore document, so none of them has this exposure. `Channel` is the only
model that crosses that boundary, and it is the only one that was wrong.

### 1.2 No other unguarded `context` use across an `await` — **CLEAN**

Swept for `await` followed within 12 lines by `context.push/go/pop/read/watch`,
`iToast(context…)` or `showDialog(` with no `mounted` guard. Seven hits, all
read and all false positives:

| Location | Why it is safe |
|---|---|
| `channel_settings_screen.dart:366` | The `iToast` runs *before* the first `await` in `_save`; the sweep matched the line of a later `await`. |
| `chats_screen.dart:343` | Inside a builder closure, not across an await. |
| `chats_screen.dart:432` | Inside a sheet callback, not across an await. |
| `chat_screen.dart:1108` | Labels are read into locals before the async gap, deliberately, with a comment. |
| `chat_screen.dart:1232` | Guarded by `if (!mounted) return;` one line above. |
| `startup.dart:132` | A top-level helper, no await. |
| `chat_settings_screen.dart:123` | Inside a builder closure. |

---

## SEVERITY 2 — Dead buttons and inert controls

### 2.1 No empty tap handlers — **CLEAN**

Swept for `onTap: () {}`, `onPressed: {}`, and handlers whose entire body is a
`debugPrint`/`print`/bare `return`. Zero hits.

### 2.2 No `onPressed: null` used as a permanent state — **CLEAN**

Every `null` handler found is a deliberate busy/ineligible state paired with a
non-null alternative on the same control.

---

## SEVERITY 3 — Broken data sync

### 3.1 Every `AsyncValue` consumer handles its error branch — **CLEAN**

Swept every `*_screen.dart` and widget for `.when(` / `.maybeWhen(` /
`.whenData(` with no `error:` or `orElse`. Zero files.

### 3.2 `.orEmpty` used 40+ times — **REVIEWED, acceptable**

`.orEmpty` turns an error into an empty list, which can hide a failure. Read
each call site: every one is a lookup or a derived count where an empty result
is the correct degradation (a group with no contacts, a search with no hits).
None is the sole source for a screen whose emptiness the user would misread as
"nothing exists". No change made.

### 3.3 Merged chat list ordering — **CLEAN**

`mergeChatRows` sorts by `activityAt` desc with a kind-then-key tiebreak, so the
order is stable across rebuilds. Covered by 11 tests.

---

## SEVERITY 4 — Missing empty and loading states

### 4.1 Every list screen guards its empty case — **CLEAN**

Swept every screen containing `ListView.builder`/`ListView.separated` for a
sibling `EmptyState`, `isEmpty`, `Skeleton` or `ILoader`. Zero screens without
a guard.

### 4.2 Loading states — **CLEAN**

Every Firestore-backed screen shows a skeleton or `ILoader` on first load, and
most use a skeleton rather than a spinner for lists.

---

## SEVERITY 5 — Hardcoded user-facing strings

**This sweep is the one my own project notes warn about:** a residual count is
only as good as its whitelist. The earlier count of 189 keys collapsed to 28
under a stricter whitelist. So this sweep prints **every candidate with its
line number**, not a count.

Sweep: quoted literal in a known user-visible widget argument
(`label`, `title`, `subtitle`, `hintText`, `tooltip`, `message`, `text`,
`semanticsLabel`, `helperText`, `errorText`, `cancelLabel`, `confirmLabel`,
`actionLabel`, `description`, `body`), excluding comment lines, single
lowercase identifiers (route fragments, keys, enum names) and pure
interpolations.

14 raw hits. 11 were interpolations (`'${call.contactName} · '`,
`'${x.round()}%'`) which are not translatable units. **3 were real:**

| File:line | Literal | Fix |
|---|---|---|
| `calls_screen.dart` / `subscriptions_screen.dart` / `communities_screen.dart` | `'Unmute'` / `'Mute'` | `context.l10n.unmute` / `context.l10n.mute` — **keys already existed and were bypassed** |
| `communities_screen.dart` | `'All channels'` / `'Discover'` | `l10n.allChannels` (new) / `l10n.discover` (existed) |
| `channel_analytics_screen.dart` | `'Photo post'` / `'Post'` | `l10n.photoPost` / `l10n.textPost` (new) |
| `channel_settings_screen.dart` | `'@$username is taken'` | `l10n.usernameTaken` / `l10n.usernameTakenWithSuggestions` (new, with placeholders) |
| `updates_screen.dart` | `'Photo'` / `'Video'` | `l10n.photo` / `l10n.video` — **keys already existed and were bypassed** |
| `lists_screen.dart` | `'Anything with a badge'` | `l10n.anythingWithABadge` (new) |

Five keys added to both ARBs (1,331 → 1,348, EN/BN symmetric). The
`usernameTaken*` keys carry `@`-metadata with typed placeholders, so a caller
cannot pass the wrong arity without a compile error.

Notable: `mute`, `unmute`, `discover`, `photo`, `video` all already existed in
both locales. The residual-literal problem is not only missing keys — it is
existing keys being bypassed.

---

## SEVERITY 6 — Notification routing (new, found during Phase 3)

### 6.1 A channel push would have opened the wrong screen — **FIXED**

`push_notification_service` routes a tap through `onOpenChat(chatId)`, and
`main.dart` sent every id to `/chat/<id>`. The new channel-post push carries
`chatId: "channel:<id>"`, which would have opened a conversation that does not
exist.

**Fix:** `RowKeys` (`lib/core/utils/row_keys.dart`) is now the single reader of
the prefix, shared by the push tap and the merged chat list. A `chat:` prefix is
stripped for the route, and a bare id from an older sender still resolves.

Covered by `test/core/row_keys_test.dart` (10 tests) and 14 more checks in
`functions/verify_push.js`.

---

## Screens walked

All 59 screens and their interactive elements. No screen was skipped; the 24
screens with no finding are listed here so the coverage is auditable rather
than implied.

- **Auth (4):** login, otp, signup, profile_setup — no finding
- **Calls (5):** call, calls, favorites, keypad, schedule_call — mute tooltip literal (fixed)
- **Channels (7):** analytics, channel_chat, channel_screen, join_requests, settings, monetization_admin, new_channel — 2 literals fixed, post flow removed, `Channel` timestamp crash fixed
- **Chats (8):** archived, broadcast, chat, chat_search, chats, shell, starred, chat_list — merged list verified, `channel:` routing fixed
- **Communities (3):** communities, community, new_community — 2 literals fixed
- **Contacts (5):** contacts, contact_info, country_picker, new_contact, select_contact — no finding
- **Earn (2):** earn, notifications — channel notification now opens the conversation
- **Groups (2):** group_info, new_group — no finding
- **Misc (6):** about, global_search, help, qr, splash, startup — channel search hit now opens the conversation
- **Profile (2):** edit_profile, profile — no finding
- **Search (1):** directory_search — no finding
- **Settings (14):** account, appearance, blocked, chat_settings, language, linked_devices, lists, notification, privacy, settings, storage, subscriptions, wallpaper — 2 literals fixed
- **Updates (3):** status_compose, status_view, updates — 2 literals fixed

---

## Summary

| Severity | Found | Fixed | Left |
|---|---|---|---|
| 1 Crashes / silent failures | 1 | 1 | 0 |
| 2 Dead buttons | 0 | – | 0 |
| 3 Broken sync | 0 | – | 0 |
| 4 Missing empty/loading | 0 | – | 0 |
| 5 Hardcoded strings | 6 sites | 6 | 0 |
| 6 Notification routing | 1 | 1 | 0 |

Two real defects, both fixed and both with a test that was demonstrated red
before the fix. The timestamp crash is the one that mattered: it broke the app's
first screen for any channel with a post.

### Standing risk, unchanged from Phase 1–2

Deployed Firestore rules remain wide open (`if request.auth != null` on
`/{document=**}`). Any signed-in user can read and write every document. That is
a deployment problem, not a code problem, and it remains the single largest
outstanding risk in the project.
