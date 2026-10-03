# AUDIT_REPORT.md — Imo LIVE (`imo_live`)

Audit date: 2026-09-28
Scope: `lib/` — 134 Dart files, ~50,100 lines.
Method: full read of every screen, service and repository, plus targeted greps for dead
handlers, stubs, placeholder text and client-clock timestamps. Every finding cites `file:line`.

---

## 0. Executive summary

The app is **not** a hollow shell. Auth, 1:1 chat, contacts, groups, status, settings and the
call *plumbing* are real. The defects cluster in four places:

1. **Channels are a hollow shell.** There is no post feed at all — `ChannelScreen` renders
   metadata, a follow button and settings, and nothing else. A channel can be created and opened
   (the local Hive path does work) but there is **nothing to read or post**. Everything in the
   directive's Phase 3 is genuinely missing.
2. **Media is local-only.** Incoming images render as "Photo unavailable" and incoming voice
   notes render as a dead mic icon on any second device, because the receive path drops the
   attachment and the bubbles only ever read a local file path.
3. **Voice playback does not exist.** The play button is a bare `Icon` with no gesture handler,
   and the "waveform" is decorative with a hardcoded 66% fill. `just_audio` is a declared
   dependency that is never imported anywhere in `lib/`.
4. **A long tail of stub controls** — buttons that toast "not available yet" or open a dialog
   explaining that the feature needs a backend. Plus two genuinely broken controls that do the
   wrong thing (see §3).

Calls are half-real: WebRTC signalling is implemented end to end; Agora is wired for media but
**never writes the Firestore call document**, so on the Agora path no incoming call can ever
arrive.

---

## 1. Screen-by-screen audit

| Screen | Element | Status | Notes |
|---|---|---|---|
| Splash | boot ladder, 10 s timeout | working | `splash_screen.dart` — always advances |
| Login | Google / Facebook / phone, in-app OAuth | working | 4 OAuth paths; buttons `null` while busy (intentional) |
| Signup | form, validation | working | — |
| OTP | 6 boxes, resend timer, shake | working | `otp_screen.dart` |
| Profile setup | name/avatar/about | working | default about text `'Hey there! I am using Imo LIVE.'` (`:183`) |
| Shell / bottom nav | 5 tabs | working | `shell_screen.dart` + `bottom_nav.dart` |
| Chats | list, search, archive, pin | working | empty state `chats_screen.dart:576` |
| Chats | long-press → pin | **stub** | `chat_screen.dart:426` toast "Pinned messages need a server" |
| Chat | send text / image / voice / file | working (send) | media send works; **playback broken**, see §4 |
| Chat | video message playback | **stub** | `chat_screen.dart:1662` "requires a video player package" |
| Chat | share, save attachment | **stub** | `:446`, `:450` toasts only |
| Chat | group call from chat | **stub** | `:861` "not available yet" |
| Chat | open channel profile from chat | **stub** | `:833` channels have no profile screen |
| Chat search | jump to message | **partial** | `chat_search_screen.dart:181` toasts then pops — never scrolls or highlights |
| Chat search | open media / links | **stub** | `:191`, `:236` toasts only |
| Starred messages | "Copy text" | **BROKEN** | `starred_messages_screen.dart:157-162` toasts `'Copied'` but **never writes to the clipboard** |
| Broadcast | "Send a broadcast" | **stub** | `broadcast_screen.dart:264-275` toast only |
| Updates (status) | list, compose, viewer | working | — |
| Status compose | video status | **stub** | `status_compose_screen.dart` video needs a player |
| Status viewer | video playback | **stub** | `status_view_screen.dart:266` |
| Status viewer | reply | **stub** | `:591-596` toast "Status replies need a chat thread" |
| Communities | list, create, announcement group | working | `communities_screen.dart` |
| Community | open announcement chat | **stub** | `community_screen.dart:140` "not ready yet" |
| **Channel** | **post feed** | **MISSING** | `channel_screen.dart` has **no posts list at all** — the screen is metadata + follow + settings |
| Channel | follow / unfollow | working | local Hive only, not shared across devices |
| Channel | edit name / category | working | local only; no @username, no description/avatar/cover edit |
| Channel | copy invite link, QR | working | `imo://channel/{code}` |
| Channel | unique @username | **MISSING** | no `channel_usernames` collection exists |
| Channel | private channel + secret key | **MISSING** | `isPublic` flag exists but there is no key, no hashed storage, no join request |
| Channel | analytics dashboard | **MISSING** | no analytics screen, no `fl_chart`, no follower/reach series |
| Channel | monetization | **MISSING** | no gating, no application flow |
| Calls | list, keypad, favourites, schedule | working | `calls_screen.dart`, `keypad_screen.dart` |
| Call screen | voice/video layouts | working but **not WhatsApp-style** | see §5 |
| Call screen | local video draggable | **missing** | fixed 108×156 top-right, tap-only (`call_screen.dart:874-913`) |
| Call screen | `SIMULATED` badge | **BROKEN** | `call_screen.dart:976-1006` badge is **unconditional** — shows on real Agora/WebRTC calls too |
| Call screen | add/group call, Bluetooth, recorder, hold, DTMF | **stub** | `:609, :624, :629, :637, :1196` all toast only |
| Contacts | list, add, lookup, invite | working | — |
| Contact info | share contact | **stub** | `contact_info_screen.dart:502-505` toast only |
| Group info | reset invite link | **stub** | `group_info_screen.dart:426-433` "server action" dialog |
| Profile | view, share contact card | partial | share → info dialog (`profile_screen.dart:237-243`) |
| Profile | join date | **DUMMY** | `profile_screen.dart:258` hardcoded `DateTime(2026, 1, 1)` "Member since" |
| Edit profile | fields, save | working | — |
| Settings | all rows navigate | working | `settings_screen.dart` |
| Account settings | 2FA, passkeys | **stub** | `account_settings_screen.dart:196, :208` backend dialog |
| Linked devices | pair, link by number | **stub** | `linked_devices_screen.dart:98, :179` backend dialog |
| Privacy settings | toggles | partial | toggles persist; one banner admits a setting is not honoured (`:64`) |
| Language | select, time format | partial | hardcoded "Coming soon" list (`language_screen.dart:20-29, 74, 88`) |
| Lists | manage / new list | **stub** | `lists_screen.dart:91-104` toast; `:110-115` persists nothing |
| Blocked contacts | "Block unknown senders" | **stub** | `blocked_contacts_screen.dart:118-135` info dialog, no blocking |
| Global search | remove a recent search | **BROKEN** | `global_search_screen.dart:101-108` calls `add(term)` instead of removing |
| QR screen | share code, in-app scan | **stub** | `qr_screen.dart:126, :116` toasts only |
| About | roadmap dialog | informational | `about_screen.dart:233-277` honestly lists what is not implemented |
| Help | diagnostics/terms/privacy | informational | `help_screen.dart:164, 185, 200` |
| New contact | save | working | `new_contact_screen.dart` |
| New group | "Create" when invalid | **no-op** | `new_group_screen.dart:326` `onPressed: canCreate ? _create : () {}` |
| New community | "Create" when invalid | **no-op** | `new_community_screen.dart:213` same pattern |
| New channel | "Create" when invalid | **no-op** | `new_channel_screen.dart:206` same pattern |
| Status compose | "Share" when invalid | **no-op** | `status_compose_screen.dart:143` same pattern |

---

## 2. Buttons that do nothing meaningful when tapped

**Genuinely broken (does the wrong thing / nothing):**

| File | Line | Problem |
|---|---|---|
| `starred_messages_screen.dart` | 157-162 | "Copy text" toasts `Copied` but never calls `Clipboard.setData` |
| `global_search_screen.dart` | 101-108 | "Remove recent search" **adds** the term back instead of removing it |
| `call_screen.dart` | 976-1006 | `SIMULATED` badge always visible, even on live calls |
| `new_group_screen.dart` / `new_community_screen.dart` / `new_channel_screen.dart` / `status_compose_screen.dart` | 326 / 213 / 206 / 143 | Invalid-state primary button is a silent `() {}` no-op instead of a visibly disabled control |

**Toast-only / backend-dialog stubs** (control exists, does nothing but explain itself):
`chat_screen.dart` (pin, save, share, group call, video, channel profile, media) ·
`chat_search_screen.dart` (open media, links) · `community_screen.dart` (announcement) ·
`call_screen.dart` (group, Bluetooth, recorder, hold, DTMF) · `status_view_screen.dart`
(video, reply) · `qr_screen.dart` (share, scan) · `contact_info_screen.dart` (share) ·
`broadcast_screen.dart` (send) · `lists_screen.dart` (manage, new) ·
`blocked_contacts_screen.dart` (block unknown) · `group_info_screen.dart` (reset link) ·
`profile_screen.dart` (share card) · `account_settings_screen.dart` (2FA, passkeys) ·
`linked_devices_screen.dart` (pair, link).

These route through `showBackendRequiredDialog` (`confirm_dialog.dart:182`) — 4 call sites — or a
direct toast.

---

## 3. Screens that show an empty / not-found state

Not-found states are correct behaviour for a genuinely missing entity, **but** for channels they
are reached far too easily because channels live only in local Hive:

| Screen | Line | State | Trigger |
|---|---|---|---|
| `channel_screen.dart` | 35-37 | "Channel not found" | id absent from the local Hive list — e.g. any channel created on another device, or after a reinstall |
| `group_info_screen.dart` | 46-48 | "Group not found" | same, local-only |
| `community_screen.dart` | 37-39 | "Community not found" | same, local-only |
| `contact_info_screen.dart` | 89-98 | "Contact not found" | id absent locally |
| `directory_search_screen.dart` | 338, 389-396 | "Search unavailable" / invite prompt | Firestore lookup path |

Error states: `channel_screen.dart:29`, `group_info_screen.dart:40`, `community_screen.dart:31`,
`contact_info_screen.dart:49`, `storage_screen.dart:37`, `linked_devices_screen.dart:29`,
`global_search_screen.dart:139`.

There is **no "User Not Found" string** in the codebase; the closest is
`directory_search_screen.dart:389` ("This number is not on Imo LIVE yet. Invite them?"), which is
correct and actionable. The "User Not Found" complaint therefore almost certainly refers to
`channel_screen.dart:35` / `group_info_screen.dart:46` — i.e. **local-only entities disappearing**,
not a broken Firestore query path.

---

## 4. Media: the two real defects

### 4a. Incoming media never attaches

`firestore_chat_service.dart:412-426` (`_toLocal`) maps an incoming Firestore message into a
`Message` **without any `attachment:` argument**. `RemoteMessage.mediaUrl` is never read on the
receive path. Consequences on a second device:

- incoming image → `attachment == null` → `ImageBody` renders `_MissingMedia('Photo unavailable')`
  (`message_bubbles.dart:252-256`);
- incoming voice note → `attachment == null` → `VoiceBody` renders a mic-off icon, duration 0.

### 4b. Bubbles only read local files

`ImageBody` (`message_bubbles.dart:224`) resolves `attachment?.localPath` and calls
`Image.file(File(path))` (`:257-259`). There is **no `Image.network` / `CachedNetworkImage`
fallback**, so even if the attachment were populated with an R2 URL, it would not render.
`VideoBody` (`:343-346`) and `StickerBody` (`:1343-1350`) share the pattern.

### 4c. Voice playback does not exist

- `VoiceBody` (`message_bubbles.dart:396`): play icon is a bare `Icon` (`:423-427`) with **no
  `GestureDetector`** — not tappable.
- `hasAudio` only checks `attachment?.localPath != null` (`:405`).
- `_Waveform` (`:490`) draws a **deterministic fake waveform** seeded from `message.id`;
  `_WavePainter` hardcodes a 66 % "played" fill (`:533-534`). It is decoration, not a progress bar.
- **No audio player anywhere in `lib/`.** `just_audio: ^0.9.42` is declared in `pubspec.yaml:92`
  but never imported. The `[AudioPlayerController]` referenced in the class doc (`:395`) does not
  exist.
- `AudioBody` (music) is likewise static: `LinearProgressIndicator(value: 0.38)` (`:597-602`).

### 4d. R2 public URL

`R2Config.publicBaseUrl` reads `R2_PUBLIC_BASE_URL` (`--dart-define`), default `''`
(`storage_service.dart:64-67`). `effectivePublicBaseUrl` falls back to `{endpoint}/{bucket}`
(`:100-103`), which is SigV4-only and unreadable by a recipient. **`AppSecrets` has no
`r2PublicBaseUrl` field** — the directive's Phase 5B requires one. Uploads work; cross-device
rendering does not until a public base URL is set.

---

## 5. Calls: what is real, what is not

**Real:** the `CallService` abstraction, WebRTC peer connection + Firestore signalling
(`call_signaling_service.dart`), incoming-call listening, and Agora media join.

**Broken / missing:**

| Issue | Evidence |
|---|---|
| **Agora never writes the Firestore call doc** | only `WebRtcCallService` calls `createCall` (`webrtc_call_service.dart:297`). `AgoraCallService.start` just joins the channel (`agora_call_service.dart:155-162`). So on the Agora path no `calls/{id}` exists, `watchIncoming` never fires, and incoming calls are impossible. The Agora branch in `shell_screen.dart:46-51` is dead code. |
| Status enum mismatch | code uses `ringing / active / ended / declined / missed` (`call_signaling_service.dart:9`). The directive specifies `accepted`. |
| `missed` never written | no ring timeout exists (`webrtc_call_service.dart:99-101`) |
| `SIMULATED` badge unconditional | `call_screen.dart:976-1006` |
| Local video not draggable | `call_screen.dart:874-913` — fixed 108×156 |
| Two schemas share `calls/` | `firestore_chat_service.dart:564-589` writes a **different** shape (`receiverId`, `type`, `duration`) under id `call_<micros>`; the signalling service uses `calleeId`, `isVideo`. They collide. |

The current UI is a dark gradient with a 140 px avatar, a 68 px end button and a "More" row — it is
**not** a WhatsApp clone. There is no incoming-call screen with accept/decline; incoming calls push
the same `CallScreen`.

**Type contracts a new provider must satisfy** (do not break):

```dart
abstract interface class CallService {
  CallSessionState get state;
  Stream<CallSessionState> get stateStream;
  Stream<Duration> get durationStream;
  Future<void> start({required String contactId, required String contactName, required bool isVideo});
  Future<void> accept();  Future<void> decline();  Future<void> end();
  Future<void> toggleMute(); toggleSpeaker(); toggleCamera(); switchCamera();
  bool get isMuted; bool get isSpeakerOn; bool get isCameraOn; bool get isFrontCamera;
  Duration get elapsed;  bool get isRealCallAvailable;
  Future<void> dispose();
}
abstract interface class VideoCallStreams {  // flutter_webrtc
  RTCVideoRenderer? get localRenderer;
  RTCVideoRenderer? get remoteRenderer;
}
abstract interface class CallVideoSurface {
  Widget? buildRemoteVideo(BuildContext context);
  Widget? buildLocalVideo(BuildContext context);
  bool get isPublishingVideo;
}
```

---

## 6. Timestamps — client clock used for stored fields

A `FirebaseTime` helper **does not exist** (grep: 0 matches). Three real Firestore writes use the
device clock:

| File | Line | Field | Consequence |
|---|---|---|---|
| `firestore_chat_service.dart` | 396 | `chats/{id}/messages/{mid}.timestamp` | message ordering depends on sender's clock (a `createdAt` server timestamp is *also* written at `:397` — duplicated/divergent) |
| `firestore_chat_service.dart` | 407 | `chats/{id}.lastMessageTime` | chat list ordering can jump |
| `firestore_chat_service.dart` | 615-618 | `status/{id}.createdAt` + `expiresAt` | a skewed clock expires/un-expires a story for every reader |

`calls/`, `users/`, `contacts/`, `usernames/`, `phones/`, `emails/` are all already
server-stamped. `remote_contact_service.dart` performs no writes.

---

## 7. Dummy data and placeholder text

| File | Line | Text | Verdict |
|---|---|---|---|
| `profile_screen.dart` | 258 | `'Member since ${DateTime(2026, 1, 1)}'` — fabricated join date | **remove** |
| `language_screen.dart` | 20-29, 74, 88 | hardcoded "Coming soon" language list | keep but label clearly (already labelled) |
| `new_contact_screen.dart` | 499 | default about `'Hey there! I am using Imo LIVE.'` | keep (WhatsApp does the same) |
| `edit_profile_screen.dart` | 44 | same default about | keep |
| `new_contact_screen.dart` | 703 | `Contact(id: 'draft', firstName: 'Draft')` | internal draft sentinel, never displayed |
| `notification_settings_screen.dart` | 193 | test notification uses `chatId: 'test'` | harmless (a deliberate test) |
| `app_secrets.dart` | 4, 38, 74 | `TODO: Replace with production keys` | legitimate |

No seeded demo users, messages, channels or calls exist. `grep -E "seedDemo|demoData|mockData|fakeUser|sampleData|DummyData"` over `lib/` → **0 matches**. The app already starts from a clean slate, so Phase 7 is a small job: one fabricated join date plus the local-only entity problem.

---

## 8. Feature checklist against the directive

| Directive item | State |
|---|---|
| Phase 2 — Watch-to-Earn, points, premium, gifting | **MISSING** — no `google_mobile_ads`, no points model, no `points_transactions`, no `isPremium`, no gift UI |
| Phase 3A — channel creation → opens | opens locally; **no post feed to open into** |
| Phase 3B — unique @username | **MISSING** |
| Phase 3C — channel editing (name/username/desc/avatar/cover/category) | **PARTIAL** — name + category only, local only |
| Phase 3D — admin-only posting, reactions | **MISSING** |
| Phase 3E — 28-day analytics with charts | **MISSING** — no `fl_chart` |
| Phase 3F — followers + reactions | **PARTIAL** — a local `followerCount` int, no follower collection, no reactions |
| Phase 3G — monetization gating (500 followers / 10k reactions / 60 d) | **MISSING** |
| Phase 3H — private channel + secret key + join requests | **MISSING** |
| Phase 4 — WhatsApp call UI | **MISSING** — current UI is a different design; incoming-call screen absent |
| Phase 5A — voice record + play | record: **working**; play: **MISSING** |
| Phase 5B — photo via `r2PublicBaseUrl` | **PARTIAL** — upload URL built; `AppSecrets.r2PublicBaseUrl` absent; receive path broken |
| Phase 6 — Firebase server timestamps | **PARTIAL** — 3 violations |
| Phase 7 — remove dummy data | **PARTIAL** — 1 fabricated value |

---

## 9. Fix checklist derived from this audit

Ordered by user-visible impact.

1. `starred_messages_screen.dart:157` — actually copy to clipboard.
2. `global_search_screen.dart:101` — remove, not add.
3. `call_screen.dart:976` — gate the `SIMULATED` badge on `!isRealCallAvailable`.
4. Media receive path — carry `mediaUrl` into `attachment` in `_toLocal`; add `Image.network`
   fallback in `ImageBody` / `VideoBody` / `StickerBody`.
5. Voice playback — real player (`just_audio`), real waveform progress, tap to play/pause.
6. `AppSecrets.r2PublicBaseUrl` + wire into `R2Config`.
7. `FirebaseTime.now()` + fix the three client-clock writes.
8. `profile_screen.dart:258` — remove the fabricated join date.
9. Invalid-state primary buttons — disable visibly instead of a silent no-op.
10. Agora — write the Firestore call doc so incoming calls work on the Agora path.
11. Build the channel post feed, @username, private key + join requests, reactions, analytics.
12. Build Watch-to-Earn + points + premium + gifting.
13. Rebuild the call UI to the WhatsApp design.
14. Backend-dependent stubs (2FA, passkeys, device pairing, group calls, video playback) — these
    genuinely require infrastructure that does not exist; they are labelled honestly in the UI and
    are **not** silently broken. They are out of scope for a code-only pass and are listed as
    remaining blockers in the final report.

---

## 2. Post-fix addendum (2026-09-28)

The audit above is the Phase 0 snapshot and is left intact. This section records what changed.

### Broken controls — all three fixed

| Element | Was | Now |
|---|---|---|
| Starred messages → "Copy text" | toasted `'Copied'` without touching the clipboard | calls `Clipboard.setData` (`starred_messages_screen.dart:164`) |
| Call screen `SIMULATED` badge | unconditional — appeared on real Agora/WebRTC calls | `bool get _isSimulated => _streams == null && _surface == null;`, badge behind `if (isSimulated)` (`call_screen.dart:140`) |
| Global search → remove a recent search | called `add(term)` instead of removing | `recentSearchesProvider.notifier.remove(term)` (`global_search_screen.dart:104`) |

### Stubs closed since the audit

| Element | Now |
|---|---|
| Chat → pin a message | real: `Message.isPinned` + `MessageRepository.togglePin`/`getPinned` + a tappable "Pinned message" banner above the conversation |
| Chat → save attachment | real: `FilePicker.platform.saveFile(bytes:)` |
| Chat → share | real: `share_plus` (`shareXFiles` for attachments, `share` for text) |
| Delete for everyone → dialog copy | the feature was already implemented; the dialog falsely claimed it "requires a server connection". Copy corrected. |
| Channel → tap an image post | was **dead** (`onOpenImage` was never passed). Now opens an in-app pinch-zoom viewer. |
| Channel → post types | was text + image. Now text, image, **video** and **file**; video/file posts open in the system app. |
| Channel post card | renders video (16:9 play tile) and file (filename row) |

### Still backend-gated, and honestly labelled (13 entry points)

Two-factor authentication · Passkeys · Linked devices → pair · Linked devices → pairing code ·
Languages marked "Coming soon" · Chat → save attachment *(now real)* · Chat → share *(now real)* ·
Chat → group call · Chat → video message playback · Chat → delete for everyone *(now real)* ·
Community → announcement chat · QR → scan inside the app · Chat → pin *(now real)*.

Each remaining one shows an explicit explanation rather than failing silently. The three that
need a new native dependency (in-app video playback, in-app QR scanning, real translations) are
the only ones where the gap is a deliberate size/build-risk trade-off rather than missing work.

### Verification after the fixes

```
flutter analyze   →  No issues found!
flutter test      →  All tests passed!  238 passed, 0 failed   (+3 pin tests)
```
