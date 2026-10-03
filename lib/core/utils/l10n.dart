import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

/// `context.l10n.tabChats` — the accessor every screen should use.
///
/// ### Why this exists
///
/// The generated [AppLocalizations] was wired into `MaterialApp` from the start,
/// but **no screen ever read it**. Every label in the app was a hardcoded
/// English literal, so changing the language in Settings rebuilt `Localizations`
/// and changed nothing the user could see — the reported "language switch does
/// nothing" bug. The ARB files were dead weight: ~180 keys translated into
/// Bengali and consumed by nobody.
///
/// The fix is not in the locale plumbing, which was already correct; it is in
/// reading the strings. This extension makes that a one-liner so the conversion
/// is mechanical rather than a judgement call at each site.
extension AppLocalizationsX on BuildContext {
  /// The app's localisations.
  ///
  /// Falls back to English rather than throwing when no [Localizations]
  /// ancestor is present — which is the normal situation in a widget test that
  /// pumps a widget directly, and would otherwise turn every converted label
  /// into a crash in tests that have nothing to do with language.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}

/// The active [AppLocalizations], for code that has no [BuildContext].
///
/// ### Why a global, rather than a parameter
///
/// The service layer produces user-visible text — a refused permission, a failed
/// upload, a points error — and a service has no `BuildContext` to read
/// `context.l10n` from. Threading an `AppLocalizations` argument through every
/// such method would change ~10 signatures, every call site and every test, to
/// serve 27 strings.
///
/// Instead the root widget publishes the live localisations here on every build
/// ([ImoLiveApp]'s `builder`), so the value follows a locale change with no
/// extra plumbing and cannot drift from what the widgets are rendering.
///
/// It defaults to English, which is also what a unit test sees — so a service
/// under test behaves exactly as it did before this existed.
class L10nRef {
  L10nRef._();

  static AppLocalizations _current = AppLocalizationsEn();

  static AppLocalizations get current => _current;

  /// Called from the root `builder`, which sits below `Localizations`.
  static void publish(AppLocalizations value) => _current = value;
}
