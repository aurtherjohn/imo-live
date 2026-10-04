# SETTINGS_AUDIT.md

**Scope:** the whole Settings tree reachable from the gear icon — `SettingsScreen`
and all 12 destination screens it links to.
**Date:** 2026-10-04
**Method:** read every screen in `lib/features/settings/presentation/`, traced each
row to its `AppRoutes` constant and its `GoRouter` entry, and checked the data
source behind each displayed value against the provider that supplies it. Nothing
below is inferred from the screen's own labels.

---

## 1. Route inventory

Every row navigates to a declared route with a real screen behind it. There are
no dead links, no "coming soon" stubs and no placeholder screens — the smallest
destination is 185 lines and the largest 414, and each one reads live providers.

| Group | Row | Route | Screen | Backing data |
| --- | --- | --- | --- | --- |
| Account | Account | `/settings/account` | `AccountSettingsScreen` | `selfProfileProvider`, `authStateProvider`, `chatCountProvider`, `contactCountProvider`, `starCountProvider` |
| Account | Privacy | `/settings/privacy` | `PrivacySettingsScreen` | `privacySettingsProvider` |
| Account | Linked devices | `/settings/devices` | `LinkedDevicesScreen` | `linkedDevicesProvider` |
| Account | Favourites | `/call/favorites` | `FavoritesScreen` | `favoritesProvider` |
| Account | Blocked contacts | `/settings/blocked` | `BlockedContactsScreen` | `blockedContactsProvider` |
| **Premium** | **Go Premium** | `/settings/premium` | **`PremiumScreen`** | `pointsAccountProvider`, `premiumRequestsProvider` — **added this pass** |
| Chats | Chat settings | `/settings/chats` | `ChatSettingsScreen` | `chatSettingsProvider` |
| Chats | Wallpaper | `/settings/wallpaper` | `WallpaperScreen` | `wallpaperProvider` |
| Chats | Lists | `/settings/lists` | `ListsScreen` | `chatsProvider`, `chatFilterProvider` |
| Chats | Starred messages | `/starred` | `StarredMessagesScreen` | `starredMessagesProvider` |
| Chats | Archived chats | `/archived` | `ArchivedChatsScreen` | `archivedChatsProvider` |
| Chats | Broadcast lists | `/broadcast` | `BroadcastScreen` | `broadcastListsProvider` |
| Notifications | Notifications | `/settings/notifications` | `NotificationSettingsScreen` | `notificationSettingsProvider` |
| Notifications | Storage and data | `/settings/storage` | `StorageScreen` | `storageUsageProvider`, `totalStorageProvider` |
| App experience | Dark mode (switch) | — | inline | `appearanceProvider.notifier.setDark` |
| App experience | Theme mode | `/settings/appearance` | `AppearanceScreen` | `themeModeProvider` |
| App experience | Appearance | `/settings/appearance` | `AppearanceScreen` | `appearanceProvider` |
| App experience | Language | `/settings/language` | `LanguageScreen` | `languageProvider` |
| Support | Help | `/settings/help` | `HelpScreen` | static content |
| Support | Subscriptions | `/settings/subscriptions` | `SubscriptionsScreen` | `channelsProvider`, `communitiesProvider` |
| Support | About | `/settings/about` | `AboutScreen` | `AppConstants` |
| Reviewer | Monetization review | `/admin/monetization` | `MonetizationAdminScreen` | gated on `isAppAdminProvider` |

The reviewer group is hidden unless `users/{uid}.isAdmin` is true, which the client
cannot write — so it cannot be self-granted by a tampered build. Verified against
the rules: `noServerFields()` in `firestore.rules` strips `isAdmin` from any client
update.

---

## 2. Defects found and fixed

### D1 — "Storage and data" displayed the starred-message count *(fixed)*

```dart
// before
value: ref.watch(totalStorageProvider) == 0
    ? 'No media yet'
    : '${ref.watch(starCountProvider)} starred',
```

The row read **"3 starred"** under a storage label. It says nothing about storage
usage and it actively hid the thing the row exists to show — that media was
accumulating. Replaced with `SizeFormatter.format(totalStorageProvider)` so it
reads e.g. `12.4 MB`.

### D2 — "Lists" displayed the same number twice *(fixed)*

```dart
// before
final int occupied = ref.watch(chatCountProvider);   // == chatsProvider.length
...
value: '${chats.length} chats, $occupied indexed',
```

`chatCountProvider` is defined as `chatsProvider.valueOrNull.length`, so
`chats.length` and `occupied` are the same integer by construction. Every user saw
**"5 chats, 5 indexed"** — a redundant second figure dressed up as a distinct
metric. Reduced to `'${chats.length} chats'`.

### D3 — No premium entry existed *(fixed)*

Added a Premium group above Account, showing either `$9.90 / month · no ads` or
`Active · N days left` so a paying user is told they are covered rather than
nagged again.

---

## 3. Defects found, not fixed

### D4 — 15 hardcoded English strings in the settings tree *(open)*

`settings_screen.dart` passes raw literals where every other screen uses
`context.l10n`. The prose values:

| Literal | Row |
| --- | --- |
| `'Manage'` | Linked devices |
| `'Lock, last seen, blocked'` | Privacy |
| `'Theme, enter key, auto-download'` | Chat settings |
| `'Accent, text size, chat theme, icon'` | Appearance |
| `'FAQ, contact us, terms'` | Help |
| `'Channels & communities'` | Subscriptions |
| `'Approve or reject channel applications'` | Monetization review |
| `'Go Premium'`, `'$9.90 / month · no ads'`, `'Active · N days left'` | Premium |

Plus the state words `'On'` / `'Off'`, `'Dark'` / `'Light'` / `'System'`,
`'Default'`, `'No media yet'`, and the `' contacts'` suffix.

**Why not fixed here:** each needs a new key in **both** `app_en.arb` and
`app_bn.arb`, and the ARB files must stay key-for-key symmetric (1408 keys today).
That is a mechanical but wide change — it needs a `pub get` to regenerate
`app_localizations*.dart`, and it is the same job `BUG_AUDIT.md` already tracks
(~181 distinct values app-wide). Doing it half-way, for one screen, would leave
the codebase in a *less* consistent state than it is now, because a partly-migrated
screen is harder to audit than an unmigrated one.

**Consequence:** the settings tree is not translatable to Bengali today. A Bengali
user sees the labels translated and the values in English. This is a real,
user-visible defect and should be the next piece of work.

### D5 — Descriptive values can drift from the feature *(open)*

`'Lock, last seen, blocked'`, `'Theme, enter key, auto-download'` and
`'Accent, text size, chat theme, icon'` are marketing summaries typed by hand.
They are not derived from the settings objects they describe, so adding a toggle
to `PrivacySettingsScreen` will not update the row. Low severity (cosmetic) but
they will go stale silently.

### D6 — "No media yet" conflates empty with unavailable *(open)*

`totalStorageProvider` returns `0` both when there is genuinely no media and when
`storageUsageProvider` has not resolved. The row therefore says **"No media yet"**
during the loading window and after a failure. Correct behaviour is a third state
(`'Calculating…'` / `'Unavailable'`). Not fixed because it needs
`totalStorageProvider` to become an `AsyncValue`, which changes its two other
consumers.

### D7 — Two rows open the same screen *(open, intentional)*

"Theme mode" and "Appearance" both push `/settings/appearance`. Kept, because
`AppearanceScreen` is long and the theme-mode row is a shortcut to its first
section. Worth knowing when reading the route table — it is not a copy-paste bug.

### D8 — Favourites is filed under Account but routes to the calls feature *(open)*

The row lives in the Account group but its route is `/call/favorites` and its
screen is `FavoritesScreen` in the calls feature. Functionally correct; the
grouping is a judgement call. Flagged so it is a decision rather than an accident.

---

## 4. Verified working (no action)

* Every `SettingsValueRow.onTap` resolves to a declared route — checked against
  `AppRoutes` and `router.dart`. No route is missing, and no static path is
  shadowed by the parameterised detail routes at the bottom of the route list
  (`test/app/route_resolution_test.dart` guards that ordering).
* The dark-mode switch writes through `appearanceProvider.notifier.setDark` and
  reads back from `themeModeProvider`, so the switch and the "Theme mode" row
  cannot disagree.
* The reviewer group is genuinely gated: `isAppAdminProvider` reads
  `users/{uid}.isAdmin`, and the rules refuse a client write to that field.
* `AccountSettingsScreen`'s destructive actions (clear chats, delete account)
  call the real repository `clear()` methods, not a UI-only reset.

---

## 5. Summary

| | Count |
| --- | --- |
| Rows in the settings tree | 22 |
| Routes with a real screen behind them | 22 / 22 |
| Dead links or placeholder screens | 0 |
| Defects found | 8 |
| Fixed this pass | 3 (D1, D2, D3) |
| Open, needs a wider change | 5 (D4–D8) |

The tree is structurally sound — nothing is fake. The outstanding work is
localisation (D4) and making the two descriptive rows derive their text from the
settings they describe (D5).
