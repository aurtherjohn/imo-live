import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imo_live/app/router.dart';

/// Guards the *navigation targets*, not just the route table.
///
/// `router_test.dart` asserts that the `AppRoutes` constants are well formed,
/// and its header claims to check "every path the app navigates to is actually
/// wired up" — but it only ever looked at a hand-maintained mirror list. It
/// therefore passed while `ChatActionsSheet` pushed `'${AppRoutes.chatInfo}/…'`
/// — a path with no registered route, which drops the user onto the router's
/// "That screen doesn't exist." page. `flutter analyze` cannot see that either,
/// because the string is well-formed.
///
/// This test closes the gap: it reads every `push`/`go`/`replace` call in
/// `lib/`, resolves the argument where it is statically knowable, and requires
/// the result to be a registered path (or the prefix of one, for the
/// `'/x'` + `'/:id'` shape).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> collectPaths(List<RouteBase> routes) {
    final List<String> paths = <String>[];
    for (final RouteBase route in routes) {
      if (route is GoRoute) {
        paths.add(route.path);
        paths.addAll(collectPaths(route.routes));
      } else if (route is StatefulShellRoute) {
        for (final StatefulShellBranch branch in route.branches) {
          paths.addAll(collectPaths(branch.routes));
        }
      }
    }
    return paths;
  }

  /// `AppRoutes.<name> = '<value>'` → { name: value }
  Map<String, String> readConstants() {
    final String src =
        File('lib/core/constants/app_constants.dart').readAsStringSync();
    final Map<String, String> out = <String, String>{};
    final RegExp re =
        RegExp(r"static const String (\w+)\s*=\s*'([^']*)'");
    for (final RegExpMatch m in re.allMatches(src)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  /// Collapses every dynamic segment to a single `:` so a literal
  /// `'/chat/${chat.id}'` and a registered `'/chat/:id'` compare equal.
  String normalise(String path) => path
      .replaceAll(RegExp(r'\$\{[^}]*\}'), ':')
      .replaceAll(RegExp(r':[A-Za-z_]\w*'), ':');

  // `.push(` / `.go(` / `.replace(` on *any* receiver — `context`, `appRouter`,
  // `router`, `GoRouter.of(context)`, `Navigator.of(context)` …
  //
  // The receiver is deliberately NOT constrained. An earlier version required
  // a prefix before "context"/"router" (`[A-Za-z_]\w*(?:[Cc]ontext|[Rr]outer)`),
  // which silently failed to match the ubiquitous `context.push(...)` — the
  // sweep found 2 call sites out of ~200 and the guard was vacuous.
  final RegExp callRe = RegExp(r"\.\s*(push|go|replace)\s*\(\s*([^,)\n]+)");
  final RegExp interpRe = RegExp(r"^'\$\{AppRoutes\.(\w+)\}");
  final RegExp litRe = RegExp(r"^'([^']*)'");
  final RegExp bareRe = RegExp(r"^AppRoutes\.(\w+)$");

  test('every statically-known navigation target is a registered route', () {
    final List<String> registered = collectPaths(appRouter.configuration.routes);
    final Set<String> registeredNormalised =
        registered.map(normalise).toSet();
    final Map<String, String> consts = readConstants();

    final List<String> unresolved = <String>[];
    final List<String> checked = <String>[];

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String rel = entity.path.replaceAll(r'\', '/');
      if (rel.contains('/l10n/')) continue;

      final String src = entity.readAsStringSync();
      for (final RegExpMatch m in callRe.allMatches(src)) {
        final String expr = m.group(2)!.trim();

        String? target;
        final RegExpMatch? interp = interpRe.firstMatch(expr);
        if (interp != null) {
          target = consts[interp.group(1)!];
        } else {
          final RegExpMatch? bare = bareRe.firstMatch(expr);
          if (bare != null) {
            target = consts[bare.group(1)!];
          } else {
            final RegExpMatch? lit = litRe.firstMatch(expr);
            if (lit != null) target = lit.group(1);
          }
        }
        // A dynamic target (`context.push(route)`) is not statically checkable.
        if (target == null || target.isEmpty) continue;
        // External links go to the platform, not the router.
        if (RegExp(r'^[a-z]+:').hasMatch(target)) continue;

        final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        checked.add('$rel:$line -> $target');

        final String tn = normalise(target);
        final bool ok = registeredNormalised.contains(tn) ||
            registeredNormalised.any((String p) => p.startsWith('$tn/'));
        if (!ok) unresolved.add('$rel:$line -> $target');
      }
    }

    // Sanity floor: if the sweep ever stops matching (as it did before), the
    // list collapses to a handful and the guard would pass while checking
    // nothing. ~200 real call sites exist today.
    expect(
      checked.length,
      greaterThan(100),
      reason: 'the sweep found only ${checked.length} navigation call(s) — far '
          'fewer than the real call sites, so the matcher is broken',
    );
    expect(
      unresolved,
      isEmpty,
      reason: 'these navigation targets have no registered GoRoute, so they '
          'render the "That screen doesn\'t exist." error page:\n'
          '${unresolved.join('\n')}',
    );
  });
}
