import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../features/chats/domain/repositories.dart';
import 'local_database.dart';

/// Hive-backed implementation of [SettingsRepository].
class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({LocalDatabase? db}) : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;

  static const String _kAppearance = 'appearance';
  static const String _kNotifications = 'notifications';
  static const String _kPrivacy = 'privacy';
  static const String _kChat = 'chat_settings';
  static const String _kWallpaper = 'wallpaper';
  static const String _kLanguage = 'language';
  static const String _kRecentSearches = 'recent_searches';
  static const String _kSyncContacts = 'sync_contacts_save';
  static const String _kDevices = 'linked_devices';
  static const String _kBroadcasts = 'broadcast_lists';

  static const String box = AppConstants.boxSettings;

  // ------------------------------------------------------------- appearance

  @override
  Future<AppearanceSettings> getAppearance() async {
    final Map<String, dynamic>? json = _db.readJson(box, _kAppearance);
    if (json == null) return const AppearanceSettings();
    return AppearanceSettings.fromJson(json);
  }

  @override
  Future<void> saveAppearance(AppearanceSettings settings) =>
      _db.writeJson(box, _kAppearance, settings.toJson());

  // ---------------------------------------------------------- notifications

  @override
  Future<NotificationSettings> getNotifications() async {
    final Map<String, dynamic>? json = _db.readJson(box, _kNotifications);
    if (json == null) return const NotificationSettings();
    return NotificationSettings.fromJson(json);
  }

  @override
  Future<void> saveNotifications(NotificationSettings settings) =>
      _db.writeJson(box, _kNotifications, settings.toJson());

  // ---------------------------------------------------------------- privacy

  @override
  Future<PrivacySettings> getPrivacy() async {
    final Map<String, dynamic>? json = _db.readJson(box, _kPrivacy);
    if (json == null) return const PrivacySettings();
    return PrivacySettings.fromJson(json);
  }

  @override
  Future<void> savePrivacy(PrivacySettings settings) =>
      _db.writeJson(box, _kPrivacy, settings.toJson());

  // ----------------------------------------------------------- chat prefs

  @override
  Future<ChatSettings> getChatSettings() async {
    final Map<String, dynamic>? json = _db.readJson(box, _kChat);
    if (json == null) return const ChatSettings();
    return ChatSettings.fromJson(json);
  }

  @override
  Future<void> saveChatSettings(ChatSettings settings) =>
      _db.writeJson(box, _kChat, settings.toJson());

  // -------------------------------------------------------------- wallpaper

  @override
  Future<Wallpaper> getWallpaper() async {
    final Map<String, dynamic>? json = _db.readJson(box, _kWallpaper);
    if (json == null) return defaultWallpaper;
    return Wallpaper.fromJson(json);
  }

  @override
  Future<void> saveWallpaper(Wallpaper wallpaper) =>
      _db.writeJson(box, _kWallpaper, wallpaper.toJson());

  /// The built-in default dark pattern.
  static const Wallpaper defaultWallpaper = Wallpaper(
    id: 'default',
    name: 'Default',
    kind: WallpaperKind.defaultPattern,
    colors: <int>[0xFF0B0B0D, 0xFF141417],
  );

  /// Every wallpaper offered by the picker.
  static const List<Wallpaper> wallpapers = <Wallpaper>[
    defaultWallpaper,
    Wallpaper(
      id: 'solid_charcoal',
      name: 'Charcoal',
      kind: WallpaperKind.solid,
      colors: <int>[0xFF1C1C20],
    ),
    Wallpaper(
      id: 'solid_black',
      name: 'Midnight',
      kind: WallpaperKind.solid,
      colors: <int>[0xFF000000],
    ),
    Wallpaper(
      id: 'solid_pink',
      name: 'Rose',
      kind: WallpaperKind.solid,
      colors: <int>[0xFF3A1020],
    ),
    Wallpaper(
      id: 'solid_teal',
      name: 'Deep Teal',
      kind: WallpaperKind.solid,
      colors: <int>[0xFF0D2A2A],
    ),
    Wallpaper(
      id: 'grad_dusk',
      name: 'Dusk',
      kind: WallpaperKind.gradient,
      colors: <int>[0xFF1B1B2F, 0xFF3A1030],
    ),
    Wallpaper(
      id: 'grad_ember',
      name: 'Ember',
      kind: WallpaperKind.gradient,
      colors: <int>[0xFF2A0F14, 0xFF4A1420],
    ),
    Wallpaper(
      id: 'grad_ocean',
      name: 'Ocean',
      kind: WallpaperKind.gradient,
      colors: <int>[0xFF0A1A2A, 0xFF10303A],
    ),
    Wallpaper(
      id: 'grad_forest',
      name: 'Forest',
      kind: WallpaperKind.gradient,
      colors: <int>[0xFF0C1F16, 0xFF14301F],
    ),
    Wallpaper(
      id: 'pattern_dots',
      name: 'Dots',
      kind: WallpaperKind.pattern,
      patternIndex: 0,
      colors: <int>[0xFF0B0B0D, 0xFF1C1C20],
    ),
    Wallpaper(
      id: 'pattern_grid',
      name: 'Grid',
      kind: WallpaperKind.pattern,
      patternIndex: 1,
      colors: <int>[0xFF0B0B0D, 0xFF1C1C20],
    ),
    Wallpaper(
      id: 'pattern_waves',
      name: 'Waves',
      kind: WallpaperKind.pattern,
      patternIndex: 2,
      colors: <int>[0xFF101018, 0xFF201028],
    ),
    Wallpaper(
      id: 'pattern_bubbles',
      name: 'Bubbles',
      kind: WallpaperKind.pattern,
      patternIndex: 3,
      colors: <int>[0xFF0F1418, 0xFF14202A],
    ),
  ];

  // --------------------------------------------------------------- language

  @override
  Future<String> getLanguage() async =>
      _db.readString(box, _kLanguage) ?? 'en';

  @override
  Future<void> setLanguage(String code) => _db.writeString(box, _kLanguage, code);

  // -------------------------------------------------------- recent searches

  @override
  Future<List<String>> getRecentSearches() async {
    final Object? raw = _db.box(box).get(_kRecentSearches);
    if (raw is! List) return <String>[];
    return raw.cast<String>();
  }

  @override
  Future<void> addRecentSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    final List<String> list = await getRecentSearches();
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    await _db.box(box).put(
      _kRecentSearches,
      list.take(8).toList(),
    );
  }

  @override
  Future<void> removeRecentSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    final List<String> list = await getRecentSearches();
    final int before = list.length;
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    if (list.length == before) return;
    if (list.isEmpty) {
      await _db.delete(box, _kRecentSearches);
      return;
    }
    await _db.box(box).put(_kRecentSearches, list);
  }

  @override
  Future<void> clearRecentSearches() => _db.delete(box, _kRecentSearches);

  // -------------------------------------------------------- contact syncing

  @override
  Future<bool> getSyncContactsOnSave() async =>
      _db.readBool(box, _kSyncContacts) ?? false;

  @override
  Future<void> setSyncContactsOnSave(bool value) =>
      _db.writeBool(box, _kSyncContacts, value);

  // -------------------------------------------------------- linked devices

  @override
  Future<List<LinkedDevice>> getLinkedDevices() async =>
      _db.readList<LinkedDevice>(box, _kDevices, LinkedDevice.fromJson);

  @override
  Future<void> saveLinkedDevices(List<LinkedDevice> devices) =>
      _db.writeList<LinkedDevice>(box, _kDevices, devices, (d) => d.toJson());

  // ------------------------------------------------------ broadcast lists

  @override
  Future<List<BroadcastList>> getBroadcastLists() async =>
      _db.readList<BroadcastList>(box, _kBroadcasts, BroadcastList.fromJson);

  @override
  Future<void> saveBroadcastLists(List<BroadcastList> lists) =>
      _db.writeList<BroadcastList>(box, _kBroadcasts, lists, (l) => l.toJson());

  // ------------------------------------------------------------------ reset

  @override
  Future<void> resetAll() => _db.clearBox(box);
}

/// Media repository. Local mode returns the path untouched so the UI can treat
/// local and remote attachments identically.
class LocalMediaRepository implements MediaRepository {
  const LocalMediaRepository();

  @override
  Future<String> upload(String localPath) async {
    // LOCAL MODE: nothing to upload — the file already lives in app storage.
    // REMOTE MODE: a `RemoteMediaRepository` would push to cloud storage and
    // return the resulting CDN URL here.
    return localPath;
  }

  @override
  Future<void> delete(String identifier) async {}

  @override
  Future<Map<String, int>> usageBreakdown() async => <String, int>{};

  @override
  Future<int> totalUsage() async => 0;
}
