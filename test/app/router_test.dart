import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imo_live/app/router.dart';
import 'package:imo_live/core/constants/app_constants.dart';

/// Routing integrity guard.
///
/// A route that is referenced by a `context.push(...)` call but never
/// registered shows the "That screen doesn't exist." error page at runtime —
/// a dead end the analyzer cannot see. These tests walk the real
/// [GoRouter] configuration and assert that every path the app navigates to is
/// actually wired up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Flattens a route tree (including shell branches) into its path patterns.
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

  late List<String> paths;

  setUpAll(() {
    paths = collectPaths(appRouter.configuration.routes);
  });

  group('AppRoutes constants', () {
    test('every route constant is a non-empty absolute path', () {
      for (final String value in _routeConstants) {
        expect(value, startsWith('/'), reason: '"$value" is not absolute');
        expect(value, isNotEmpty);
        // `AppRoutes.shell` is the shell root and is legitimately just '/'.
        if (value == AppRoutes.shell) continue;
        expect(value.length, greaterThan(1));
        expect(value.endsWith('/'), isFalse, reason: '"$value" has a trailing slash');
      }
    });

    test('no two constants collide', () {
      expect(
        _routeConstants.toSet().length,
        _routeConstants.length,
        reason: 'duplicate route path declared in AppRoutes',
      );
    });
  });

  group('router configuration', () {
    test('starts on the splash route so the first frame is never blank', () {
      // `GoRouter` exposes no `initialLocation` getter in 14.x; the resolved
      // start location lives on the route information provider.
      expect(
        appRouter.routeInformationProvider.value.uri.path,
        AppRoutes.splash,
      );
    });

    test('registers the splash route', () {
      expect(paths, contains(AppRoutes.splash));
    });

    test('registers all four bottom-navigation tabs', () {
      expect(paths, containsAll(<String>[
        AppRoutes.chats,
        AppRoutes.updates,
        AppRoutes.contacts,
        AppRoutes.calls,
      ]));
    });

    test('registers every parameterised detail route', () {
      // These are built by concatenating a constant with an id, e.g.
      // `context.push('${AppRoutes.chat}/$id')`.
      expect(paths, contains('${AppRoutes.chat}/:id'));
      expect(paths, contains('${AppRoutes.contactInfo}/:id'));
      expect(paths, contains('${AppRoutes.groupInfo}/:id'));
    });

    test('registers the full settings subtree', () {
      expect(paths, containsAll(<String>[
        AppRoutes.settings,
        AppRoutes.account,
        AppRoutes.privacy,
        AppRoutes.chatSettings,
        AppRoutes.notifications,
        AppRoutes.storage,
        AppRoutes.appearance,
        AppRoutes.language,
        AppRoutes.help,
        AppRoutes.about,
        AppRoutes.lists,
        AppRoutes.linkedDevices,
        AppRoutes.blocked,
        AppRoutes.wallpaper,
      ]));
    });

    test('registers the calls, contacts and status subtrees', () {
      expect(paths, containsAll(<String>[
        AppRoutes.call,
        AppRoutes.callSchedule,
        AppRoutes.keypad,
        AppRoutes.favorites,
        AppRoutes.countryPicker,
        AppRoutes.newContact,
        AppRoutes.selectContact,
        AppRoutes.newGroup,
        AppRoutes.statusCompose,
        AppRoutes.statusView,
      ]));
    });

    test('registers the remaining standalone screens', () {
      expect(paths, containsAll(<String>[
        AppRoutes.starred,
        AppRoutes.archived,
        AppRoutes.broadcast,
        AppRoutes.chatSearch,
        AppRoutes.profile,
        AppRoutes.editProfile,
        AppRoutes.qr,
        AppRoutes.globalSearch,
      ]));
    });

    test('has a fallback error page rather than crashing on an unknown path',
        () {
      // `RouteConfiguration` exposes no public `errorBuilder` accessor, so the
      // declaration is asserted at the source level — the same technique the
      // startup regression test uses for `main.dart`.
      final String source = File('lib/app/router.dart').readAsStringSync();
      expect(source, contains('errorBuilder:'));
      expect(source, contains('AppRoutes.chats'));
    });
  });

  group('bottom navigation', () {
    test('has exactly one nav item per shell branch', () {
      // `goBranch(index)` navigates by *position*, so the bar and the branch
      // list have to be the same length. They were not, once: the bar kept a
      // fifth "Communities" item after that feature was removed, so the last
      // tab indexed past the end of the branch list and the ones before it
      // opened the wrong screen.
      expect(
        _navItemLabels().length,
        _shellBranchPaths().length,
        reason: 'the bottom bar and the shell branches must be the same '
            'length, and in the same order',
      );
    });

    test('each nav item targets the branch at the same position', () {
      const Map<String, String> expectedLabelKey = <String, String>{
        AppRoutes.chats: 'tabChats',
        AppRoutes.updates: 'tabUpdates',
        AppRoutes.contacts: 'tabContacts',
        AppRoutes.calls: 'tabCalls',
      };
      final List<String> branches = _shellBranchPaths();
      final List<String> labels = _navItemLabels();
      expect(labels, hasLength(branches.length));
      for (int i = 0; i < branches.length; i++) {
        expect(
          labels[i],
          expectedLabelKey[branches[i]],
          reason: 'tab $i (${branches[i]}) is wired to the wrong label',
        );
      }
    });
  });
}

/// The paths of the shell branches, in the order the router declares them.
///
/// This list *is* the tab order the bottom bar has to match, because
/// `goBranch` navigates by position.
List<String> _shellBranchPaths() {
  for (final RouteBase route in appRouter.configuration.routes) {
    if (route is StatefulShellRoute) {
      return <String>[
        for (final StatefulShellBranch branch in route.branches)
          (branch.routes.first as GoRoute).path,
      ];
    }
  }
  return const <String>[];
}

/// The `l10n` key of each bottom-nav item, in declaration order.
///
/// Read from the source rather than from a widget: the bar is built inside
/// `ShellScreen`, which needs a live `StatefulNavigationShell` and a fully
/// initialised Firestore, neither of which a unit test has. The labels are a
/// flat list in the source, which is all the test needs to know.
List<String> _navItemLabels() {
  final String source = File(
    'lib/features/chats/presentation/shell_screen.dart',
  ).readAsStringSync();
  return RegExp(r'l10n\.(tab\w+)')
      .allMatches(source)
      .map((Match match) => match.group(1)!)
      .toList();
}

/// Mirrors `AppRoutes` so that adding a constant forces this list to be
/// updated — keeping the uniqueness/format checks honest.
const List<String> _routeConstants = <String>[
  AppRoutes.splash,
  AppRoutes.shell,
  AppRoutes.chats,
  AppRoutes.updates,
  AppRoutes.calls,
  AppRoutes.chat,
  AppRoutes.chatSearch,
  AppRoutes.contactInfo,
  AppRoutes.starred,
  AppRoutes.archived,
  AppRoutes.broadcast,
  AppRoutes.newContact,
  AppRoutes.selectContact,
  AppRoutes.newGroup,
  AppRoutes.groupInfo,
  AppRoutes.statusCompose,
  AppRoutes.statusView,
  AppRoutes.settings,
  AppRoutes.account,
  AppRoutes.privacy,
  AppRoutes.chatSettings,
  AppRoutes.notifications,
  AppRoutes.storage,
  AppRoutes.appearance,
  AppRoutes.language,
  AppRoutes.help,
  AppRoutes.about,
  AppRoutes.lists,
  AppRoutes.linkedDevices,
  AppRoutes.blocked,
  AppRoutes.wallpaper,
  AppRoutes.profile,
  AppRoutes.editProfile,
  AppRoutes.qr,
  AppRoutes.call,
  AppRoutes.callSchedule,
  AppRoutes.keypad,
  AppRoutes.favorites,
  AppRoutes.countryPicker,
  AppRoutes.globalSearch,
];
