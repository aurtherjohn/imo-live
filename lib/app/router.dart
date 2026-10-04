import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import 'auth_gate.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/profile_setup_screen.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/calls/presentation/call_screen.dart';
import '../features/calls/presentation/calls_screen.dart';
import '../features/calls/presentation/favorites_screen.dart';
import '../features/calls/presentation/keypad_screen.dart';
import '../features/calls/presentation/schedule_call_screen.dart';
import '../features/channels/presentation/channel_chat_screen.dart';
import '../features/channels/presentation/channel_screen.dart';
import '../features/channels/presentation/monetization_admin_screen.dart';
import '../features/channels/presentation/new_channel_screen.dart';
import '../features/chats/presentation/archived_chats_screen.dart';
import '../features/chats/presentation/chat_screen.dart';
import '../features/chats/presentation/chat_search_screen.dart';
import '../features/chats/presentation/chats_screen.dart';
import '../features/chats/presentation/shell_screen.dart';
import '../features/chats/presentation/starred_messages_screen.dart';
import '../features/communities/presentation/communities_screen.dart';
import '../features/communities/presentation/community_screen.dart';
import '../features/communities/presentation/new_community_screen.dart';
import '../features/contacts/presentation/contact_info_screen.dart';
import '../features/contacts/presentation/contacts_screen.dart';
import '../features/contacts/presentation/country_picker_screen.dart';
import '../features/contacts/presentation/new_contact_screen.dart';
import '../features/contacts/presentation/select_contact_screen.dart';
import '../features/earn/presentation/earn_screen.dart';
import '../features/earn/presentation/notifications_screen.dart';
import '../features/groups/presentation/group_info_screen.dart';
import '../features/groups/presentation/new_group_screen.dart';
import '../features/misc/presentation/about_screen.dart';
import '../features/chats/presentation/broadcast_screen.dart';
import '../features/misc/presentation/help_screen.dart';
import '../features/misc/presentation/qr_screen.dart';
import '../features/misc/presentation/splash_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/misc/presentation/global_search_screen.dart';
import '../features/premium/presentation/premium_screen.dart';
import '../features/settings/presentation/account_settings_screen.dart';
import '../features/settings/presentation/appearance_screen.dart';
import '../features/settings/presentation/blocked_contacts_screen.dart';
import '../features/settings/presentation/chat_settings_screen.dart';
import '../features/settings/presentation/language_screen.dart';
import '../features/settings/presentation/linked_devices_screen.dart';
import '../features/settings/presentation/lists_screen.dart';
import '../features/settings/presentation/notification_settings_screen.dart';
import '../features/settings/presentation/privacy_settings_screen.dart';
import '../features/updates/presentation/status_compose_screen.dart';
import '../features/updates/presentation/status_view_screen.dart';
import '../features/updates/presentation/updates_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/storage_screen.dart';
import '../features/settings/presentation/subscriptions_screen.dart';
import '../features/settings/presentation/wallpaper_screen.dart';
import '../features/search/presentation/directory_search_screen.dart';
import '../core/utils/l10n.dart';
import 'app.dart' show appPage;

/// Application router.
///
/// A single [StatefulShellRoute] keeps the bottom navigation persistent while
/// each tab maintains its own navigation stack — matching the expected
/// messaging-app behaviour.
///
/// ### The auth gate
///
/// [GoRouter]'s `refreshListenable` re-evaluates `redirect` whenever Firebase
/// reports a change, so sign-in, sign-out and email verification are all
/// handled in one place rather than by every screen pushing its own route. The
/// rules are deliberately total — every combination of (signed in?, verified?,
/// profile complete?) maps to exactly one destination:
///
/// | signed in | email verified | profile complete | destination |
/// | --- | --- | --- | --- |
/// | no  | —   | —   | login  |
/// | yes | no  | —   | verify |
/// | yes | yes | no  | profile setup |
/// | yes | yes | yes | the requested route |
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  refreshListenable: authRefreshListenable,
  redirect: authRedirect,
  routes: <RouteBase>[
    // ------------------------------------------------------------- splash
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const SplashScreen()),
    ),

    // --------------------------------------------------------------- auth
    // Declared before the shell so a signed-out user is sent here rather than
    // into the tab structure.
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const LoginScreen()),

      routes: <RouteBase>[
        GoRoute(
          path: 'signup',
          name: 'signup',
          pageBuilder: (BuildContext context, GoRouterState state) =>
              appPage(state, const SignupScreen()),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.signup,
      name: 'signupTopLevel',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const SignupScreen()),
    ),
    GoRoute(
      path: AppRoutes.otp,
      name: 'otp',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const OtpScreen()),
    ),
    GoRoute(
      path: AppRoutes.profileSetup,
      name: 'profileSetup',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ProfileSetupScreen()),
    ),

    // -------------------------------------------------------------- shell
    StatefulShellRoute.indexedStack(
      builder: (
        BuildContext context,
        GoRouterState state,
        StatefulNavigationShell navigationShell,
      ) => ShellScreen(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.chats,
              name: 'chats',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  appPage(state, const ChatsScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.updates,
              name: 'updates',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  appPage(state, const UpdatesScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.communities,
              name: 'communities',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  appPage(state, const CommunitiesScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.contacts,
              name: 'contacts',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  appPage(state, const ContactsScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.calls,
              name: 'calls',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  appPage(state, const CallsScreen()),
            ),
          ],
        ),
      ],
    ),

    // ------------------------------------------------------- full screens
    // NOTE: every static path is declared *before* the parameterised detail
    // routes, which live at the very bottom of this list. GoRouter matches in
    // declaration order and takes the first hit, so a `/:id` route declared
    // first silently swallows its static siblings. That is exactly what made
    // `/contact/select`, `/contact/new` and `/chat/search` open the wrong
    // screen. `test/app/route_resolution_test.dart` guards the ordering.
    GoRoute(
      path: AppRoutes.chatSearch,
      name: 'chatSearch',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        ChatSearchScreen(
          chatId: state.uri.queryParameters['id'] ?? '',
          initialType: state.uri.queryParameters['type'],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.starred,
      name: 'starred',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const StarredMessagesScreen()),
    ),
    GoRoute(
      path: AppRoutes.archived,
      name: 'archived',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ArchivedChatsScreen()),
    ),
    GoRoute(
      path: AppRoutes.broadcast,
      name: 'broadcast',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const BroadcastScreen()),
    ),

    // ----------------------------------------------------------- contacts
    GoRoute(
      path: AppRoutes.newContact,
      name: 'newContact',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        NewContactScreen(contactId: state.uri.queryParameters['id']),
      ),
    ),
    GoRoute(
      path: AppRoutes.selectContact,
      name: 'selectContact',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const SelectContactScreen()),
    ),
    GoRoute(
      path: AppRoutes.newGroup,
      name: 'newGroup',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const NewGroupScreen()),
    ),

    // -------------------------------------------- communities / channels
    GoRoute(
      path: AppRoutes.newCommunity,
      name: 'newCommunity',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const NewCommunityScreen()),
    ),
    GoRoute(
      path: AppRoutes.newChannel,
      name: 'newChannel',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const NewChannelScreen()),
    ),

    // ------------------------------------------------------------ status
    GoRoute(
      path: AppRoutes.statusCompose,
      name: 'statusCompose',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        StatusComposeScreen(
          initialMediaPath: state.uri.queryParameters['media'],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.statusView,
      name: 'statusView',
      builder: (BuildContext context, GoRouterState state) {
        final String raw = state.uri.queryParameters['ids'] ?? '';
        final List<String> ids = raw
            .split(',')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
        return StatusViewScreen(
          statusIds: ids,
          isMine: state.uri.queryParameters['mine'] == '1',
        );
      },
    ),

    // ---------------------------------------------------------- settings
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const SettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.account,
      name: 'account',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const AccountSettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.privacy,
      name: 'privacy',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const PrivacySettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.chatSettings,
      name: 'chatSettings',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ChatSettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.notifications,
      name: 'notifications',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const NotificationSettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.storage,
      name: 'storage',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const StorageScreen()),
    ),
    GoRoute(
      path: AppRoutes.appearance,
      name: 'appearance',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const AppearanceScreen()),
    ),
    GoRoute(
      path: AppRoutes.language,
      name: 'language',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const LanguageScreen()),
    ),
    GoRoute(
      path: AppRoutes.help,
      name: 'help',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const HelpScreen()),
    ),
    GoRoute(
      path: AppRoutes.about,
      name: 'about',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const AboutScreen()),
    ),
    GoRoute(
      path: AppRoutes.lists,
      name: 'lists',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ListsScreen()),
    ),
    GoRoute(
      path: AppRoutes.linkedDevices,
      name: 'linkedDevices',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const LinkedDevicesScreen()),
    ),
    GoRoute(
      path: AppRoutes.blocked,
      name: 'blocked',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const BlockedContactsScreen()),
    ),
    GoRoute(
      path: AppRoutes.wallpaper,
      name: 'wallpaper',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const WallpaperScreen()),
    ),
    GoRoute(
      path: AppRoutes.subscriptions,
      name: 'subscriptions',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const SubscriptionsScreen()),
    ),
    GoRoute(
      path: AppRoutes.premium,
      name: 'premium',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const PremiumScreen()),
    ),

    // ----------------------------------------------------------- profile
    GoRoute(
      path: AppRoutes.profile,
      name: 'profile',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ProfileScreen()),
    ),
    // -------------------------------------------------------------- earn
    // Watch-to-Earn lives outside the shell: it is reached from the drawer, so
    // it should cover the whole screen rather than sit inside a tab.
    GoRoute(
      path: AppRoutes.earn,
      name: 'earn',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const EarnScreen()),
    ),
    GoRoute(
      path: AppRoutes.notificationsCenter,
      name: 'notificationsCenter',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const NotificationsScreen()),
    ),
    // Reviewer-only, and additionally gated inside the screen on
    // `users/{uid}.isAdmin` — the route being reachable is not authorisation.
    GoRoute(
      path: AppRoutes.monetizationAdmin,
      name: 'monetizationAdmin',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const MonetizationAdminScreen()),
    ),
    GoRoute(
      path: AppRoutes.editProfile,
      name: 'editProfile',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const EditProfileScreen()),
    ),
    GoRoute(
      path: AppRoutes.qr,
      name: 'qr',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        QrScreen(
          title: state.uri.queryParameters['title'] ?? AppConstants.appName,
          payload: state.uri.queryParameters['payload'] ?? 'imo://profile',
        ),
      ),
    ),

    // ------------------------------------------------------------- calls
    GoRoute(
      path: AppRoutes.call,
      name: 'call',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        CallScreen(
          contactId: state.uri.queryParameters['id'] ?? '',
          contactName: state.uri.queryParameters['name'] ?? 'Unknown',
          isVideo: switch (state.uri.queryParameters['video']) {
            // Callers build this with `video=$isVideo`, which Dart renders as
            // "true"/"false" — matching only '1' silently downgraded every video
            // call to a voice call. Accept both spellings.
            '1' || 'true' => true,
            _ => false,
          },
          isOutgoing: state.uri.queryParameters['outgoing'] != '0',
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.callSchedule,
      name: 'callSchedule',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const ScheduleCallScreen()),
    ),
    GoRoute(
      path: AppRoutes.keypad,
      name: 'keypad',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const KeypadScreen()),
    ),
    GoRoute(
      path: AppRoutes.favorites,
      name: 'favorites',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const FavoritesScreen()),
    ),
    GoRoute(
      path: AppRoutes.countryPicker,
      name: 'countryPicker',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const CountryPickerScreen()),
    ),

    // ------------------------------------------------------------ search
    GoRoute(
      path: AppRoutes.globalSearch,
      name: 'globalSearch',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const GlobalSearchScreen()),
    ),
    GoRoute(
      path: AppRoutes.directorySearch,
      name: 'directorySearch',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, const DirectorySearchScreen()),
    ),

    // ------------------------------------------------- parameterised detail
    // Declared last, on purpose. These `/:id` patterns match anything in their
    // final segment, so they must not be reachable before the static routes
    // above them — otherwise `/chat/search` resolves as a chat with the id
    // "search", and `/contact/new` as a contact with the id "new".
    GoRoute(
      path: '${AppRoutes.chat}/:id',
      name: 'chat',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          appPage(state, ChatScreen(chatId: state.pathParameters['id'] ?? '')),
    ),
    GoRoute(
      path: '${AppRoutes.contactInfo}/:id',
      name: 'contactInfo',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        ContactInfoScreen(contactId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      path: '${AppRoutes.groupInfo}/:id',
      name: 'groupInfo',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        GroupInfoScreen(groupId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      path: '${AppRoutes.community}/:id',
      name: 'community',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        CommunityScreen(communityId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      path: '${AppRoutes.channel}/:id',
      name: 'channel',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        ChannelScreen(channelId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      // A channel as a conversation. Order matters: this is declared after
      // `/channel/:id`, and GoRouter matches the more specific literal segment
      // ('channelChat' vs 'channel') on the first path segment, so the two do
      // not collide.
      path: '${AppRoutes.channelChat}/:id',
      name: 'channelChat',
      pageBuilder: (BuildContext context, GoRouterState state) => appPage(
        state,
        ChannelChatScreen(channelId: state.pathParameters['id'] ?? ''),
      ),
    ),
  ],
  errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.explore_off_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              context.l10n.thatScreenDoesnTExist,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go(AppRoutes.chats),
              child: Text(context.l10n.goToChats),
            ),
          ],
        ),
      ),
    ),
  ),
);
