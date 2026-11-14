/// Central application constants for Imo LIVE.
///
/// Every string, key and default that is shared across features lives here so
/// that the app has a single source of truth and remains easy to re-brand.
class AppConstants {
  const AppConstants._();

  // ---------------------------------------------------------------- branding
  static const String appName = 'Imo LIVE';
  static const String appTagline = 'Fast. Private. Yours.';
  static const String appVersion = '1.0.0';

  // ------------------------------------------------------------ storage keys
  static const String boxSettings = 'imo_settings';
  static const String boxChats = 'imo_chats';
  static const String boxMessages = 'imo_messages';
  static const String boxContacts = 'imo_contacts';
  static const String boxGroups = 'imo_groups';
  static const String boxCommunities = 'imo_communities';
  static const String boxChannels = 'imo_channels';
  static const String boxStatuses = 'imo_statuses';
  static const String boxCalls = 'imo_calls';
  static const String boxProfile = 'imo_profile';
  static const String boxMisc = 'imo_misc';

  // ------------------------------------------------------------ local folders
  static const String dirImages = 'images';
  static const String dirVideos = 'videos';
  static const String dirThumbnails = 'thumbnails';
  static const String dirAudio = 'audio';
  static const String dirDocuments = 'documents';
  static const String dirVoiceNotes = 'voice_notes';
  static const String dirProfile = 'profile';
  static const String dirWallpapers = 'wallpapers';
  static const String dirStatus = 'status';

  // ------------------------------------------------------------------ timings
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
  static const Duration splashDuration = Duration(milliseconds: 1800);

  // --------------------------------------------------------- default profile
  //
  // The app ships with **no** seeded content. A brand-new install starts with
  // an empty chat list, an empty contact list and a blank profile, so nothing
  // on screen is fabricated. These two values describe the *placeholder* the
  // UI shows until the user fills the field in themselves — they are never
  // written into storage as if they were real data.

  /// Shown in place of a name before the user sets one.
  static const String defaultDisplayName = 'You';

  /// Shown in place of a phone number before the user sets one.
  static const String unsetPhoneLabel = 'Add phone number';

  /// Shown in place of an "about" line before the user sets one.
  static const String unsetAboutLabel = 'Tap to add an about';

  // -------------------------------------------------------- phone identity
  //
  // Phone sign-in does not use Firebase's SMS flow. It creates an ordinary
  // email/password account whose address is *derived from the number*, so the
  // number is the credential the user types and the derived address is what the
  // backend sees.
  //
  // ### Why derive an address instead of using SMS OTP
  //
  // * Firebase phone auth bills per verification and needs the paid plan; the
  //   email/password provider is free on Spark.
  // * It needs a reCAPTCHA/Play Integrity handshake and a real device, so it
  //   cannot be exercised in a test or on an emulator reliably.
  // * The user asked for a PIN, not an SMS code — a 6-digit PIN is the same
  //   secret length as an OTP, but it is *reusable*, so it must be a password
  //   and must be stored as one.
  //
  // The derived address is a pure function of the digits, which is what lets a
  // **signed-out** client sign in without reading Firestore first: it computes
  // the address locally and hands it to the auth SDK. That matters because the
  // deployed rules require `request.auth != null`, so a signed-out lookup would
  // be denied — an index-based phone login cannot work under those rules.

  /// Domain used for the derived address. Never a real mailbox.
  static const String phoneAuthEmailDomain = 'phone.imolive.app';

  /// The value written to `users/{uid}.signupMethod`.
  ///
  /// `email` was the third value until 2026-10-06; email sign-up is gone, so
  /// the only two writers left are the phone flow and the Google flow. The
  /// field is descriptive metadata — nothing reads it back — so it is written
  /// honestly rather than inferred.
  static const String signupMethodPhone = 'phone';
  static const String signupMethodGoogle = 'google';

  /// Derives the sign-in address for an E.164 number given as digits only.
  ///
  /// `8801712345678` becomes `p8801712345678@phone.imolive.app`. The `p` prefix
  /// keeps the local part from ever starting with a digit-only run that could
  /// collide with a real address at the same domain.
  static String phoneAuthEmailFor(String phoneDigits) {
    final String digits = phoneDigits.replaceAll(RegExp(r'[^0-9]'), '');
    return 'p$digits@$phoneAuthEmailDomain';
  }

  /// True when [email] is one of our derived phone addresses.
  ///
  /// This is how the auth gate tells a phone account from an email one: both
  /// are `password`-provider accounts, so `providerData` cannot distinguish
  /// them, and a phone account can never verify its address — the OTP screen
  /// would trap it forever.
  ///
  /// Takes the address rather than a `User` so this file stays free of a
  /// `firebase_auth` import; the router reads `user.email` and calls this.
  static bool isPhoneAuthEmail(String? email) {
    if (email == null) return false;
    return email.toLowerCase().trim().endsWith('@$phoneAuthEmailDomain');
  }
}

/// Every route path name used by GoRouter.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String shell = '/';
  static const String chats = '/chats';
  static const String updates = '/updates';
  static const String contacts = '/contacts';
  static const String calls = '/calls';

  static const String chat = '/chat';
  // NOTE: there is deliberately no `chatInfo` constant here. One existed —
  // `/chat/info` — and was never backed by a registered route, so the
  // long-press "Chat info" tile pushed the user onto the router's "That screen
  // doesn't exist." page. A direct chat's info lives at
  // `contactInfo/:peerUid`; see `ChatActionsSheet._openChatInfo`.
  static const String chatSearch = '/chat/search';
  static const String contactInfo = '/contact';
  static const String starred = '/starred';
  static const String archived = '/archived';
  static const String broadcast = '/broadcast';
  static const String newContact = '/contact/new';
  static const String selectContact = '/contact/select';
  static const String newGroup = '/group/new';
  static const String groupInfo = '/group/info';

  static const String statusCompose = '/status/compose';
  static const String statusView = '/status/view';

  static const String settings = '/settings';
  static const String account = '/settings/account';
  static const String privacy = '/settings/privacy';
  static const String chatSettings = '/settings/chats';
  static const String notifications = '/settings/notifications';
  static const String storage = '/settings/storage';
  static const String appearance = '/settings/appearance';
  static const String language = '/settings/language';
  static const String help = '/settings/help';
  static const String about = '/settings/about';
  /// Phone sign-in / sign-up, as a real route so the auth redirect and the
  /// visible screen stay in agreement (see `login_screen.dart::_phone`).
  static const String phoneLogin = '/auth/phone';
  static const String lists = '/settings/lists';
  static const String linkedDevices = '/settings/devices';
  static const String blocked = '/settings/blocked';
  static const String wallpaper = '/settings/wallpaper';
  static const String premium = '/settings/premium';

  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String qr = '/qr';

  static const String notificationsCenter = '/notifications';

  static const String call = '/call';
  static const String callSchedule = '/call/schedule';
  static const String keypad = '/call/keypad';
  static const String favorites = '/call/favorites';
  static const String countryPicker = '/country';

  static const String globalSearch = '/search';

  /// Smart search across the shared Imo LIVE directory — phone, email,
  /// @username and uid all resolve here.
  static const String directorySearch = '/search/directory';

  // ---------------------------------------------------------------- auth
  // The auth screens live outside the shell, so they cover the whole screen
  // with no bottom navigation — the standard shape for a sign-in flow.
  //
  // NOTE: `/auth/verify` was removed on 2026-10-06 with email sign-in. There is
  // no verification step left, so no route for one exists.
  static const String login = '/auth/login';
  static const String signup = '/auth/signup';
  static const String profileSetup = '/auth/profile';

  /// Screens that must never be reachable while signed in, and vice versa.
  static const Set<String> authRoutes = <String>{
    login,
    signup,
    profileSetup,
  };
}
