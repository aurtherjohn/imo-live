import 'package:flutter/foundation.dart';

/// Theme mode preference.
enum AppThemeMode { system, light, dark }

/// A chat wallpaper choice.
enum WallpaperKind { defaultPattern, solid, gradient, pattern, image }

/// A selectable wallpaper.
@immutable
class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.name,
    required this.kind,
    this.colors = const <int>[0xFF0B0B0D],
    this.imagePath,
    this.patternIndex = 0,
    this.isDark = true,
  });

  final String id;
  final String name;
  final WallpaperKind kind;
  final List<int> colors;
  final String? imagePath;
  final int patternIndex;
  final bool isDark;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'colors': colors,
        'imagePath': imagePath,
        'patternIndex': patternIndex,
        'isDark': isDark,
      };

  factory Wallpaper.fromJson(Map<String, dynamic> json) => Wallpaper(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: WallpaperKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => WallpaperKind.defaultPattern,
        ),
        colors: (json['colors'] as List<dynamic>?)?.cast<int>() ??
            const <int>[0xFF0B0B0D],
        imagePath: json['imagePath'] as String?,
        patternIndex: (json['patternIndex'] as num?)?.toInt() ?? 0,
        isDark: json['isDark'] as bool? ?? true,
      );
}

/// Appearance-related preferences.
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = AppThemeMode.dark,
    this.accentColor = 0xFFFF2D55,
    this.chatTheme = 'default',
    this.fontScale = 1.0,
    this.appIcon = 'default',
  });

  final AppThemeMode themeMode;
  final int accentColor;
  final String chatTheme;
  final double fontScale;
  final String appIcon;

  AppearanceSettings copyWith({
    AppThemeMode? themeMode,
    int? accentColor,
    String? chatTheme,
    double? fontScale,
    String? appIcon,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        accentColor: accentColor ?? this.accentColor,
        chatTheme: chatTheme ?? this.chatTheme,
        fontScale: fontScale ?? this.fontScale,
        appIcon: appIcon ?? this.appIcon,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'themeMode': themeMode.name,
        'accentColor': accentColor,
        'chatTheme': chatTheme,
        'fontScale': fontScale,
        'appIcon': appIcon,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) =>
      AppearanceSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == json['themeMode'],
          orElse: () => AppThemeMode.dark,
        ),
        accentColor: (json['accentColor'] as num?)?.toInt() ?? 0xFFFF2D55,
        chatTheme: json['chatTheme'] as String? ?? 'default',
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        appIcon: json['appIcon'] as String? ?? 'default',
      );
}

/// Notification preferences.
@immutable
class NotificationSettings {
  const NotificationSettings({
    this.messageNotifications = true,
    this.groupNotifications = true,
    this.callNotifications = true,
    this.statusNotifications = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.popupEnabled = true,
    this.showPreview = true,
    this.inAppSounds = true,
    this.inAppVibrate = false,
    this.reactionsEnabled = true,
    this.soundTone = 'Default',
  });

  final bool messageNotifications;
  final bool groupNotifications;
  final bool callNotifications;
  final bool statusNotifications;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool popupEnabled;
  final bool showPreview;
  final bool inAppSounds;
  final bool inAppVibrate;
  final bool reactionsEnabled;
  final String soundTone;

  NotificationSettings copyWith({
    bool? messageNotifications,
    bool? groupNotifications,
    bool? callNotifications,
    bool? statusNotifications,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? popupEnabled,
    bool? showPreview,
    bool? inAppSounds,
    bool? inAppVibrate,
    bool? reactionsEnabled,
    String? soundTone,
  }) =>
      NotificationSettings(
        messageNotifications: messageNotifications ?? this.messageNotifications,
        groupNotifications: groupNotifications ?? this.groupNotifications,
        callNotifications: callNotifications ?? this.callNotifications,
        statusNotifications: statusNotifications ?? this.statusNotifications,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        popupEnabled: popupEnabled ?? this.popupEnabled,
        showPreview: showPreview ?? this.showPreview,
        inAppSounds: inAppSounds ?? this.inAppSounds,
        inAppVibrate: inAppVibrate ?? this.inAppVibrate,
        reactionsEnabled: reactionsEnabled ?? this.reactionsEnabled,
        soundTone: soundTone ?? this.soundTone,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'messageNotifications': messageNotifications,
        'groupNotifications': groupNotifications,
        'callNotifications': callNotifications,
        'statusNotifications': statusNotifications,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'popupEnabled': popupEnabled,
        'showPreview': showPreview,
        'inAppSounds': inAppSounds,
        'inAppVibrate': inAppVibrate,
        'reactionsEnabled': reactionsEnabled,
        'soundTone': soundTone,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        messageNotifications: json['messageNotifications'] as bool? ?? true,
        groupNotifications: json['groupNotifications'] as bool? ?? true,
        callNotifications: json['callNotifications'] as bool? ?? true,
        statusNotifications: json['statusNotifications'] as bool? ?? true,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
        popupEnabled: json['popupEnabled'] as bool? ?? true,
        showPreview: json['showPreview'] as bool? ?? true,
        inAppSounds: json['inAppSounds'] as bool? ?? true,
        inAppVibrate: json['inAppVibrate'] as bool? ?? false,
        reactionsEnabled: json['reactionsEnabled'] as bool? ?? true,
        soundTone: json['soundTone'] as String? ?? 'Default',
      );
}

/// Privacy preferences.
@immutable
class PrivacySettings {
  const PrivacySettings({
    this.lastSeenVisibility = 'everyone',
    this.profilePhotoVisibility = 'everyone',
    this.aboutVisibility = 'everyone',
    this.statusVisibility = 'contacts',
    this.readReceipts = true,
    this.groupsVisibility = 'everyone',
    this.callsVisibility = 'contacts',
    this.liveLocation = false,
    this.appLock = false,
    this.blockUnknownSenders = false,
    this.defaultDisappearingSeconds = 0,
  });

  /// 'everyone' | 'contacts' | 'nobody'
  final String lastSeenVisibility;
  final String profilePhotoVisibility;
  final String aboutVisibility;
  final String statusVisibility;
  final bool readReceipts;
  final String groupsVisibility;
  final String callsVisibility;
  final bool liveLocation;
  final bool appLock;

  /// Drop messages from senders who are not in the contact list.
  ///
  /// Off by default: silently discarding messages is the kind of thing a user
  /// should have opted into, not discovered after wondering why nobody replied.
  final bool blockUnknownSenders;

  final int defaultDisappearingSeconds;

  PrivacySettings copyWith({
    String? lastSeenVisibility,
    String? profilePhotoVisibility,
    String? aboutVisibility,
    String? statusVisibility,
    bool? readReceipts,
    String? groupsVisibility,
    String? callsVisibility,
    bool? liveLocation,
    bool? appLock,
    bool? blockUnknownSenders,
    int? defaultDisappearingSeconds,
  }) =>
      PrivacySettings(
        lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
        profilePhotoVisibility:
            profilePhotoVisibility ?? this.profilePhotoVisibility,
        aboutVisibility: aboutVisibility ?? this.aboutVisibility,
        statusVisibility: statusVisibility ?? this.statusVisibility,
        readReceipts: readReceipts ?? this.readReceipts,
        groupsVisibility: groupsVisibility ?? this.groupsVisibility,
        callsVisibility: callsVisibility ?? this.callsVisibility,
        liveLocation: liveLocation ?? this.liveLocation,
        appLock: appLock ?? this.appLock,
        blockUnknownSenders:
            blockUnknownSenders ?? this.blockUnknownSenders,
        defaultDisappearingSeconds:
            defaultDisappearingSeconds ?? this.defaultDisappearingSeconds,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lastSeenVisibility': lastSeenVisibility,
        'profilePhotoVisibility': profilePhotoVisibility,
        'aboutVisibility': aboutVisibility,
        'statusVisibility': statusVisibility,
        'readReceipts': readReceipts,
        'groupsVisibility': groupsVisibility,
        'callsVisibility': callsVisibility,
        'liveLocation': liveLocation,
        'appLock': appLock,
        'blockUnknownSenders': blockUnknownSenders,
        'defaultDisappearingSeconds': defaultDisappearingSeconds,
      };

  factory PrivacySettings.fromJson(Map<String, dynamic> json) =>
      PrivacySettings(
        lastSeenVisibility: json['lastSeenVisibility'] as String? ?? 'everyone',
        profilePhotoVisibility:
            json['profilePhotoVisibility'] as String? ?? 'everyone',
        aboutVisibility: json['aboutVisibility'] as String? ?? 'everyone',
        statusVisibility: json['statusVisibility'] as String? ?? 'contacts',
        readReceipts: json['readReceipts'] as bool? ?? true,
        groupsVisibility: json['groupsVisibility'] as String? ?? 'everyone',
        callsVisibility: json['callsVisibility'] as String? ?? 'contacts',
        liveLocation: json['liveLocation'] as bool? ?? false,
        appLock: json['appLock'] as bool? ?? false,
        blockUnknownSenders: json['blockUnknownSenders'] as bool? ?? false,
        defaultDisappearingSeconds:
            (json['defaultDisappearingSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// Per-chat behaviour preferences.
@immutable
class ChatSettings {
  const ChatSettings({
    this.enterKeySends = false,
    this.mediaVisibility = true,
    this.keepArchived = false,
    this.backupEnabled = false,
    this.backupFrequency = 'daily',
    this.fontSize = 1.0,
    this.autoDownloadPhotos = true,
    this.autoDownloadAudio = true,
    this.autoDownloadVideos = false,
    this.autoDownloadDocuments = false,
  });

  final bool enterKeySends;
  final bool mediaVisibility;
  final bool keepArchived;
  final bool backupEnabled;
  final String backupFrequency;
  final double fontSize;
  final bool autoDownloadPhotos;
  final bool autoDownloadAudio;
  final bool autoDownloadVideos;
  final bool autoDownloadDocuments;

  ChatSettings copyWith({
    bool? enterKeySends,
    bool? mediaVisibility,
    bool? keepArchived,
    bool? backupEnabled,
    String? backupFrequency,
    double? fontSize,
    bool? autoDownloadPhotos,
    bool? autoDownloadAudio,
    bool? autoDownloadVideos,
    bool? autoDownloadDocuments,
  }) =>
      ChatSettings(
        enterKeySends: enterKeySends ?? this.enterKeySends,
        mediaVisibility: mediaVisibility ?? this.mediaVisibility,
        keepArchived: keepArchived ?? this.keepArchived,
        backupEnabled: backupEnabled ?? this.backupEnabled,
        backupFrequency: backupFrequency ?? this.backupFrequency,
        fontSize: fontSize ?? this.fontSize,
        autoDownloadPhotos: autoDownloadPhotos ?? this.autoDownloadPhotos,
        autoDownloadAudio: autoDownloadAudio ?? this.autoDownloadAudio,
        autoDownloadVideos: autoDownloadVideos ?? this.autoDownloadVideos,
        autoDownloadDocuments: autoDownloadDocuments ?? this.autoDownloadDocuments,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enterKeySends': enterKeySends,
        'mediaVisibility': mediaVisibility,
        'keepArchived': keepArchived,
        'backupEnabled': backupEnabled,
        'backupFrequency': backupFrequency,
        'fontSize': fontSize,
        'autoDownloadPhotos': autoDownloadPhotos,
        'autoDownloadAudio': autoDownloadAudio,
        'autoDownloadVideos': autoDownloadVideos,
        'autoDownloadDocuments': autoDownloadDocuments,
      };

  factory ChatSettings.fromJson(Map<String, dynamic> json) => ChatSettings(
        enterKeySends: json['enterKeySends'] as bool? ?? false,
        mediaVisibility: json['mediaVisibility'] as bool? ?? true,
        keepArchived: json['keepArchived'] as bool? ?? false,
        backupEnabled: json['backupEnabled'] as bool? ?? false,
        backupFrequency: json['backupFrequency'] as String? ?? 'daily',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 1.0,
        autoDownloadPhotos: json['autoDownloadPhotos'] as bool? ?? true,
        autoDownloadAudio: json['autoDownloadAudio'] as bool? ?? true,
        autoDownloadVideos: json['autoDownloadVideos'] as bool? ?? false,
        autoDownloadDocuments: json['autoDownloadDocuments'] as bool? ?? false,
      );
}

/// A linked companion device (UI-only — pairing requires a backend).
@immutable
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActive,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime lastActive;
  final bool isCurrent;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'platform': platform,
        'lastActive': lastActive.toIso8601String(),
        'isCurrent': isCurrent,
      };

  factory LinkedDevice.fromJson(Map<String, dynamic> json) => LinkedDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        lastActive:
            DateTime.tryParse(json['lastActive'] as String? ?? '') ?? DateTime.now(),
        isCurrent: json['isCurrent'] as bool? ?? false,
      );
}

/// A broadcast list — a saved set of recipients.
@immutable
class BroadcastList {
  const BroadcastList({
    required this.id,
    required this.name,
    this.recipientIds = const <String>[],
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> recipientIds;
  final DateTime? createdAt;

  BroadcastList copyWith({
    String? id,
    String? name,
    List<String>? recipientIds,
    DateTime? createdAt,
  }) =>
      BroadcastList(
        id: id ?? this.id,
        name: name ?? this.name,
        recipientIds: recipientIds ?? this.recipientIds,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'recipientIds': recipientIds,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory BroadcastList.fromJson(Map<String, dynamic> json) => BroadcastList(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        recipientIds:
            (json['recipientIds'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );
}

/// A country entry for the dial-code picker.
@immutable
class Country {
  const Country({
    required this.name,
    required this.iso,
    required this.dialCode,
    this.nativeName = '',
  });

  final String name;
  final String iso;
  final String dialCode;
  final String nativeName;

  /// Regional-indicator emoji derived from the ISO code — avoids shipping a
  /// flag asset pack while still rendering properly everywhere.
  String get flagEmoji {
    if (iso.length != 2) return '🏳️';
    const int base = 0x1F1E6;
    final int first = iso.toUpperCase().codeUnitAt(0) - 65 + base;
    final int second = iso.toUpperCase().codeUnitAt(1) - 65 + base;
    return String.fromCharCodes(<int>[first, second]);
  }

  String get display => nativeName.isEmpty ? name : '$name ($nativeName)';
}

/// The mode in which permissions are requested.
enum PermissionMode { allAtOnce, justInTime }

/// Onboarding state persisted across launches.
///
/// Keeps track of whether the welcome flow has completed, the language and
/// country the user picked, and which permission-grant mode they chose.
@immutable
class OnboardingSettings {
  const OnboardingSettings({
    this.complete = false,
    this.languageCode = 'en',
    this.countryCode = 'BD',
    this.countryName = 'Bangladesh',
    this.userName = '',
    this.permissionMode = PermissionMode.justInTime,
  });

  /// Whether the welcome flow (language, country, name, permissions) finished.
  final bool complete;

  /// The language code selected during onboarding, e.g. `en` or `bn`.
  final String languageCode;

  /// The ISO country code selected during onboarding, e.g. `BD`.
  final String countryCode;

  /// The display name of the selected country.
  final String countryName;

  /// The name the user entered during onboarding.
  final String userName;

  /// Whether permissions are requested all at once or just-in-time.
  final PermissionMode permissionMode;

  OnboardingSettings copyWith({
    bool? complete,
    String? languageCode,
    String? countryCode,
    String? countryName,
    String? userName,
    PermissionMode? permissionMode,
  }) =>
      OnboardingSettings(
        complete: complete ?? this.complete,
        languageCode: languageCode ?? this.languageCode,
        countryCode: countryCode ?? this.countryCode,
        countryName: countryName ?? this.countryName,
        userName: userName ?? this.userName,
        permissionMode: permissionMode ?? this.permissionMode,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'complete': complete,
        'languageCode': languageCode,
        'countryCode': countryCode,
        'countryName': countryName,
        'userName': userName,
        'permissionMode': permissionMode.index,
      };

  factory OnboardingSettings.fromJson(Map<String, dynamic> json) {
    final int modeIndex = (json['permissionMode'] as int?) ?? 1;
    return OnboardingSettings(
      complete: json['complete'] as bool? ?? false,
      languageCode: json['languageCode'] as String? ?? 'en',
      countryCode: json['countryCode'] as String? ?? 'BD',
      countryName: json['countryName'] as String? ?? 'Bangladesh',
      userName: json['userName'] as String? ?? '',
      permissionMode: PermissionMode.values[modeIndex],
    );
  }
}

/// The list of countries offered during onboarding, with flag emojis and dial
/// codes derived from the shared [Country] model.
final List<Country> onboardingCountries = <Country>[
  Country(name: 'Bangladesh', iso: 'BD', dialCode: '+880', nativeName: 'বাংলাদেশ'),
  Country(name: 'India', iso: 'IN', dialCode: '+91', nativeName: 'भारत'),
  Country(name: 'Pakistan', iso: 'PK', dialCode: '+92', nativeName: 'پاکستان'),
  Country(name: 'United States', iso: 'US', dialCode: '+1', nativeName: 'United States'),
  Country(name: 'United Kingdom', iso: 'GB', dialCode: '+44', nativeName: 'United Kingdom'),
  Country(name: 'Canada', iso: 'CA', dialCode: '+1', nativeName: 'Canada'),
  Country(name: 'Australia', iso: 'AU', dialCode: '+61', nativeName: 'Australia'),
  Country(name: 'Germany', iso: 'DE', dialCode: '+49', nativeName: 'Deutschland'),
  Country(name: 'France', iso: 'FR', dialCode: '+33', nativeName: 'France'),
  Country(name: 'United Arab Emirates', iso: 'AE', dialCode: '+971', nativeName: 'الإمارات'),
  Country(name: 'Saudi Arabia', iso: 'SA', dialCode: '+966', nativeName: 'المملكة العربية السعودية'),
  Country(name: 'Malaysia', iso: 'MY', dialCode: '+60', nativeName: 'Malaysia'),
  Country(name: 'Singapore', iso: 'SG', dialCode: '+65', nativeName: 'Singapore'),
  Country(name: 'Nepal', iso: 'NP', dialCode: '+977', nativeName: 'नेपाल'),
  Country(name: 'Sri Lanka', iso: 'LK', dialCode: '+94', nativeName: 'ශ්‍රී ලංකාව'),
];

/// The languages offered during onboarding.
final List<({String code, String name, String nativeName})> onboardingLanguages =
    <({String code, String name, String nativeName})>[
  (code: 'en', name: 'English', nativeName: 'English'),
  (code: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
  (code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
  (code: 'ur', name: 'Urdu', nativeName: 'اردو'),
  (code: 'ar', name: 'Arabic', nativeName: 'العربية'),
];
