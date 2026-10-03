import 'package:flutter/services.dart';

/// A single place for touch feedback, so the app does not sound like it was
/// built by eight different people.
///
/// ### Why a wrapper
///
/// `HapticFeedback` calls were scattered bare across the chat surface — some
/// `lightImpact`, some `selectionClick`, chosen by whoever wrote that line. The
/// result is inconsistent: the same "a row was tapped" gesture felt different in
/// two screens. Naming the *semantic event* instead of the physical pulse keeps
/// it consistent and makes it reviewable.
///
/// ### Reduced motion is not the same switch
///
/// The platform offers no way to query the haptics preference, so these always
/// fire. They are all sub-10ms taps, which the OS itself silences in silent
/// mode — that is the contract, and it is the right one to lean on.
abstract final class Haptics {
  /// A light tick. Use for a discrete choice: selecting a chip, toggling a
  /// switch, stepping through options.
  static void tick() => HapticFeedback.selectionClick();

  /// A single soft tap. Use for an action the user just committed: sending,
  /// tapping a row, opening a sheet.
  static void tap() => HapticFeedback.lightImpact();

  /// A firmer knock. Use for something finishing or arriving: a message lands,
  /// a payment succeeds, a call connects.
  static void thud() => HapticFeedback.mediumImpact();

  /// The heaviest pulse. Reserved for destructive confirmation — a delete that
  /// just happened, a call ending. Rare on purpose; if it fires often it stops
  /// meaning anything.
  static void warn() => HapticFeedback.heavyImpact();
}
