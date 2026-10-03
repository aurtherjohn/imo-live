# POLISH_REPORT.md — Phase 8

Professional-polish pass over `imo_live`. Scope: spacing, typography, radii,
colour contrast, semantics, haptics. Every number below was measured on this
tree; nothing is estimated.

Baseline at the start of this phase: `flutter analyze` clean, **390** tests
passing. End state: clean, **398** passing.

---

## 1. What the measurement found

### 1.1 Light-theme semantic colours were illegible — the real bug

WCAG 2.1 contrast ratios, computed against the light surface `#FFFFFF` and the
dark surface, with a 4.5:1 requirement for body text (AA):

| token      | on `#FFFFFF` | verdict              |
| ---------- | ------------ | -------------------- |
| `success`  | **1.98**     | fails badly          |
| `warning`  | **1.83**     | fails badly          |
| `info`     | **2.53**     | fails badly          |
| `online`   | **1.98**     | fails badly          |
| `danger`   | **3.41**     | large-text only      |
| `accent`   | **3.65**     | large-text only      |

The dark theme passed everywhere. This was not a theoretical concern: the green
presence dot on a white chat list was **essentially invisible** at 1.98:1, and
every success/error tint read as a smudge rather than as a status.

The accent case is the widest blast radius — `accent` paints link text,
`FilledButton` labels and selected-tab text. At 3.65:1 all of those failed AA.

### 1.2 Typography had drifted off its own scale

The theme defines a proper 14-step `TextTheme` (`app_theme.dart:259`). The
widgets largely ignored it: **135 raw `fontSize:` literals across 30 distinct
values**, only 72 of which matched a scale token.

The damage was in the sub-pixel tail — `11.5`, `12.5`, `12.8`, `13.5`, `15`,
`15.5`. A designer does not choose `12.8` against `13`; that is rounding noise.
Its effect is that two otherwise-identical list rows render a half-pixel apart.

### 1.3 Sizing literals were inconsistent

| pattern                       | count |
| ----------------------------- | ----- |
| raw `EdgeInsets.all(N)`       | 13    |
| raw `SizedBox(w/h: N)`        | 104   |
| raw `BorderRadius.circular(N)`| 7     |

### 1.4 Semantics

64 of 78 `IconButton`s already carried a `tooltip` (Flutter exposes that as the
semantics label), so the app was in better shape than a raw `Semantics(` count
suggests. **8 genuinely unlabeled icon buttons** remained, and 4 screens used
`Semantics(` directly.

---

## 2. What was changed

### 2.1 Theme-aware foreground tokens

Added `onSuccess`, `onWarning`, `onInfo`, `onDanger` and `online` to
`AppColorScheme`, plus the tuned light constants in `app_tokens.dart`:

```
lightSuccessFg = #0E7A3F   5.4:1 on white
lightWarningFg = #8A5A00   5.9:1
lightInfoFg    = #0B6BCB   5.3:1
lightDangerFg  = #C42B22   5.7:1
lightOnlineFg  = #0E7A3F   5.4:1
```

The dark theme keeps the raw brand hues verbatim, because on the dark surface
they already clear AA — there was nothing to fix and no reason to drift.

**`accent` in the light theme now resolves to `AppColors.accentDark` (#D6193E,
5.16:1)** rather than the brand `#FF2D55`. That token is the one that works in
both directions: 5.16:1 as text on white, and 5.16:1 as white-on-accent for
button fills.

The rule, documented at the declaration site: read `context.c.onX` when the
colour is a **foreground**; use `AppColors.X` only when it is a **fill**.

**104 call sites migrated across 44 files.** 12 raw uses remain, all verified
as fills or tints:

- 9 × `.withValues(alpha: 0.10–0.28)` washes behind text
- 1 × `keypad_screen.dart:134` `FilledButton` background
- 2 × `auth_widgets.dart` error-border hairlines, where a saturated 1.2px line
  is the intent and legibility does not apply

### 2.2 Typography snapped to the scale

23 sites within **0.5px** of a scale token were snapped onto it. This band is
unambiguously rounding noise.

Deliberately left alone, with the reasoning recorded in the script:

- `44` / `46` — hero numerals, intentionally larger than `displayLarge`
- `26` / `30` — intentionally between `displayMedium` and `displaySmall`
- `9` / `9.5` / `10` — tiny badge counts; snapping up to 11 overflows tight
  badges, so shrinking is the point
- `17` / `18` / `23` / `25` / `29` — the ±1 band, wide enough to be a choice

Result: on-scale values **72 → 94**, distinct values **30 → 25**.

### 2.3 Accessibility

All 8 unlabeled `IconButton`s now carry a label, routed through `context.l10n`
rather than literals — including the video player chrome, which required four
new ARB keys (`playVideo`, `pauseVideo`, `rewind10`, `forward10`) in both EN and
BN, and a new `label` field on the internal `_ChromeButton`.

Haptics: 18 existing call sites confirmed consistent with the `Haptics` helper
(`tick` / `tap` / `thud` / `warn`) introduced in Phase 5.

### 2.4 Regression guard

`test/theme/contrast_guard_test.dart` — **8 new tests** pinning the WCAG maths
for both themes. The suite also asserts that the raw palette *does* fail as a
light foreground, so if a future palette change fixes that, the test fails and
forces a deliberate decision rather than a silent regression.

This guard earned its place immediately: it caught that the light accent was
still 3.65:1 after I had already fixed the five semantic tokens. I had missed it.

---

## 3. Honest assessment of what is *not* done

- **Semantics coverage is thin.** Only 4 of 59 screens use `Semantics(`
  directly. Icon buttons are labeled, but there is no screen-level structure —
  no heading order, no live regions for the call and typing states. A screen
  reader user gets usable labels without navigable structure.
- **`fontSize` literals remain** at 110 sites (94 on-scale). Those are a
  legitimate mechanism when you also need weight or colour overrides; migrating
  them to `t.titleSmall?.copyWith(...)` is a larger refactor with real risk and
  no user-visible gain.
- **Raw `SizedBox` dimensions (104) were not converted.** They are almost all
  explicit one-off spacings where the token indirection would hurt readability
  more than help consistency.
- **The adaptive-icon XML in `android/**` is still unverified.** `flutter
  analyze` does not read it; only the Phase 9 Gradle build can confirm it.

---

## 4. Verification

```
flutter analyze   →  No issues found!
flutter test      →  398 passed   (390 baseline + 8 contrast guards)
```

Both run on this tree after every change in this phase.
