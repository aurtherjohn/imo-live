import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../domain/chat_rows.dart';
import '../../../core/models/message.dart';
import '../../../core/models/settings.dart';
import '../../../core/models/status.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/audio_location_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/call_signaling_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/services/file_service.dart';
import '../../../core/services/in_app_logger.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/r2_media_repository.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../local/database/local_chat_repository.dart';
import '../../../local/database/local_contact_repository.dart';
import '../../../local/database/local_database.dart';
import '../../../local/database/local_group_repository.dart';
import '../../../local/database/local_message_repository.dart';
import '../../../local/database/local_settings_repository.dart';
import '../../../local/database/local_status_repository.dart';
import '../../../local/storage/file_storage_service.dart';
import '../../../core/services/webrtc_call_service.dart';
import '../../../core/services/video_thumbnailer.dart';
import '../domain/repositories.dart';
import '../../../core/utils/l10n.dart';

// ============================================================================
// Infrastructure
// ============================================================================

/// The result of `LocalDatabase.init()`, published by `StartupService`.
///
/// Seeded from the database itself so a hot restart that reuses an already
/// open store reports the truth on the very first read.
final StateProvider<bool> storageReadyStateProvider =
    StateProvider<bool>((Ref ref) => LocalDatabase.instance.isReady);

/// True once [LocalDatabase.init] has completed successfully.
///
/// `main()` no longer opens storage before `runApp`, so on a cold start this
/// is `false` for the first frames. Screens must read it as "not ready yet"
/// and render an empty state rather than blocking on it.
final Provider<bool> storageReadyProvider =
    Provider<bool>((Ref ref) => ref.watch(storageReadyStateProvider));

/// True when storage opened but some collections are unavailable.
final Provider<bool> storageDegradedProvider = Provider<bool>((Ref ref) {
  // Depend on the readiness flag so this recomputes once startup finishes.
  ref.watch(storageReadyStateProvider);
  return LocalDatabase.instance.isDegraded;
});

final Provider<FileStorageService> fileStorageProvider =
    Provider<FileStorageService>((Ref ref) => FileStorageService());

final Provider<PermissionService> permissionServiceProvider =
    Provider<PermissionService>((Ref ref) => const PermissionService());

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((Ref ref) {
  final ConnectivityService service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

/// Streams the current network status.
final StreamProvider<NetworkStatus> networkStatusProvider =
    StreamProvider<NetworkStatus>((Ref ref) async* {
  final ConnectivityService service = ref.watch(connectivityServiceProvider);
  yield await service.init();
  yield* service.stream;
});

/// True when the device has any usable connection.
final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  return ref.watch(networkStatusProvider).maybeWhen(
        data: (NetworkStatus s) => s.isOnline,
        orElse: () => true,
      );
});

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((Ref ref) => LocalNotificationService());

final Provider<MediaService> mediaServiceProvider =
    Provider<MediaService>((Ref ref) => MediaService(
          storage: ref.watch(fileStorageProvider),
          permissions: ref.watch(permissionServiceProvider),
        ));

/// Renders the chat-bubble poster for a video, on the sending device.
final Provider<VideoThumbnailer> videoThumbnailerProvider =
    Provider<VideoThumbnailer>(
  (Ref ref) => VideoThumbnailer(storage: ref.watch(fileStorageProvider)),
);

final Provider<FileService> fileServiceProvider =
    Provider<FileService>((Ref ref) => FileService(
          storage: ref.watch(fileStorageProvider),
          permissions: ref.watch(permissionServiceProvider),
        ));

final Provider<ShareService> shareServiceProvider =
    Provider<ShareService>((Ref ref) => const ShareService());

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => LocationService(
          permissions: ref.watch(permissionServiceProvider),
        ));

final Provider<DeviceContactService> deviceContactServiceProvider =
    Provider<DeviceContactService>((Ref ref) => DeviceContactService(
          permissions: ref.watch(permissionServiceProvider),
        ));

final Provider<AudioRecorderService> audioRecorderProvider =
    Provider<AudioRecorderService>((Ref ref) {
  final AudioRecorderService recorder = AudioRecorderService(
    storage: ref.watch(fileStorageProvider),
    permissions: ref.watch(permissionServiceProvider),
    // Read live, at the moment a recording fails, from whichever call service
    // this build selected. `ref.read` inside the closure rather than a value
    // captured now, because the answer has to describe the device at that
    // instant; `watch`ing the call provider here would also keep a call session
    // alive for as long as any chat is open.
    callHoldsMicrophone: () => ref.read(callServiceProvider).holdsMicrophone,
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// The live auth user, so anything derived from the uid rebinds on sign-in.
///
/// ⚠️ This exists because [callUidProvider] used to read
/// `FirebaseAuth.instance.currentUser` inside a plain `Provider`. A Riverpod
/// `Provider` that watches nothing is computed once and cached for the life of
/// the container — so the uid captured at first read, typically `''` because the
/// SDK had not restored the session yet, was the uid for the whole session. The
/// incoming-call listener then bound to an empty uid, `watchIncoming('')`
/// short-circuited to an empty stream, and the phone could not ring at all for
/// anyone who signed in during that session.
///
/// Watching a stream instead makes the uid a *value that changes*, which is what
/// it always was.
final StreamProvider<User?> _authUserProvider = StreamProvider<User?>((Ref ref) {
  try {
    return FirebaseAuth.instance.authStateChanges();
  } on Object {
    // Firebase not initialised — no session, so no real call.
    return Stream<User?>.value(null);
  }
});

/// The signed-in uid, for call wiring.
///
/// Read from the auth stream rather than `currentUidProvider`: that lives in
/// `auth_providers.dart`, which already imports this file, so reaching back for
/// it would make the dependency circular.
final Provider<String> callUidProvider = Provider<String>((Ref ref) {
  final AsyncValue<User?> auth = ref.watch(_authUserProvider);
  final String fromStream = auth.valueOrNull?.uid ?? '';
  if (fromStream.isNotEmpty) return fromStream;
  try {
    // The stream's first emission can lag a synchronous read on a warm start,
    // where the session is already restored — take whichever answers first.
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  } on Object {
    return '';
  }
});

/// The `calls/{callId}` rendezvous, shared by both call providers.
///
/// One instance for the whole app: the incoming-call listener, the active call
/// and the call history all read and write the same collection, and a second
/// client would only add a second connection without changing the result.
final Provider<CallSignalingService> callSignalingServiceProvider =
    Provider<CallSignalingService>((Ref ref) => CallSignalingService());

/// The call implementation.
///
/// A signed-in user gets a real provider; with no session there is nobody to
/// call, so the local simulator is used instead — it keeps every screen and
/// transition exercisable without an account.
///
/// [WebRtcCallService] is the **only** real provider. Media is peer-to-peer and
/// Firestore carries nothing but the SDP offer/answer and the ICE candidates.
/// Connectivity across mobile networks comes from the TURN relay configured in
/// [AppSecrets] — without it two callers on mobile data negotiate and then
/// never connect, which is the failure the relay exists to prevent.
///
/// `AgoraCallService` is still on disk but is deliberately unreachable from
/// here. The project moved off Agora, and leaving a second live provider behind
/// a config check is how a call silently ends up on the wrong stack after a
/// rebuild. If Agora is ever wanted again, wire it back in explicitly.
final Provider<CallService> callServiceProvider =
    Provider<CallService>((Ref ref) {
  final String uid = ref.watch(callUidProvider);
  if (uid.isEmpty) {
    final LocalCallService service = LocalCallService();
    ref.onDispose(service.dispose);
    return service;
  }
  final WebRtcCallService service = WebRtcCallService(
    selfUid: uid,
    // Shared with every other feature that asks the OS for a permission, so
    // the call path cannot drift from the rest of the app.
    permissions: ref.watch(permissionServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Calls currently ringing for the signed-in user.
///
/// Consumed by the incoming-call UI, which hands the id to
/// [WebRtcCallService.pendingCallId] before accepting.
final StreamProvider<List<CallDocument>> incomingCallsProvider =
    StreamProvider<List<CallDocument>>((Ref ref) {
  final String uid = ref.watch(callUidProvider);
  return ref.watch(callSignalingServiceProvider).watchIncoming(uid);
});

// ============================================================================
// Repositories — the swap points for a future backend
// ============================================================================

// Each repository owns a broadcast StreamController for its `watch*()` stream,
// so the provider is responsible for closing it when the container is torn
// down — the same wiring already used for [CallService] above. Without this the
// controllers outlive their container (visible in tests and on hot restart).

final Provider<ChatRepository> chatRepositoryProvider =
    Provider<ChatRepository>((Ref ref) {
  // The uid is resolved at call time, not captured now: `currentUidProvider`
  // is `''` until the auth stream's first event, and the deletion index is
  // keyed by uid — a value frozen at construction would file every removal
  // under the anonymous key for the whole first session.
  final LocalChatRepository repository = LocalChatRepository(
    uid: () => ref.read(currentUidProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<MessageRepository> messageRepositoryProvider =
    Provider<MessageRepository>((Ref ref) => LocalMessageRepository());

final Provider<ContactRepository> contactRepositoryProvider =
    Provider<ContactRepository>((Ref ref) {
  final LocalContactRepository repository = LocalContactRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<GroupRepository> groupRepositoryProvider =
    Provider<GroupRepository>((Ref ref) {
  final LocalGroupRepository repository = LocalGroupRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<CommunityRepository> communityRepositoryProvider =
    Provider<CommunityRepository>((Ref ref) {
  final LocalCommunityRepository repository = LocalCommunityRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<ChannelRepository> channelRepositoryProvider =
    Provider<ChannelRepository>((Ref ref) {
  final LocalChannelRepository repository = LocalChannelRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<StatusRepository> statusRepositoryProvider =
    Provider<StatusRepository>((Ref ref) {
  final LocalStatusRepository repository = LocalStatusRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<CallRepository> callRepositoryProvider =
    Provider<CallRepository>((Ref ref) {
  final LocalCallRepository repository = LocalCallRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((Ref ref) => LocalSettingsRepository());

/// The media upload boundary.
///
/// [R2MediaRepository] imports the file into app-private storage and returns
/// that local path — which is what the avatar, icon and wallpaper callers
/// render from — while pushing a copy to Cloudflare R2 in the background.
///
/// The identifier therefore stays local (offline-first, no network needed to
/// show a picture the user just picked), and the R2 URL is what the messaging
/// layer attaches to an outgoing message.
final Provider<MediaRepository> mediaRepositoryProvider =
    Provider<MediaRepository>((Ref ref) => R2MediaRepository());

// ============================================================================
// Settings / theme
// ============================================================================

/// Loads persisted appearance settings at startup.
final AsyncNotifierProvider<AppearanceNotifier, AppearanceSettings>
    appearanceProvider =
    AsyncNotifierProvider<AppearanceNotifier, AppearanceSettings>(
  AppearanceNotifier.new,
);

class AppearanceNotifier extends AsyncNotifier<AppearanceSettings> {
  @override
  Future<AppearanceSettings> build() =>
      ref.read(settingsRepositoryProvider).getAppearance();

  Future<void> apply(AppearanceSettings Function(AppearanceSettings) change) async {
    final AppearanceSettings current = state.valueOrNull ?? const AppearanceSettings();
    final AppearanceSettings next = change(current);
    state = AsyncData<AppearanceSettings>(next);
    await ref.read(settingsRepositoryProvider).saveAppearance(next);
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      apply((AppearanceSettings s) => s.copyWith(themeMode: mode));

  /// Flips between light and dark, collapsing "system" onto the opposite of
  /// whatever the platform currently reports. Used by the Settings toggle,
  /// where a two-state switch is clearer than a three-way picker.
  Future<void> setDark(bool dark) => setThemeMode(
        dark ? AppThemeMode.dark : AppThemeMode.light,
      );

  Future<void> setAccent(int color) =>
      apply((AppearanceSettings s) => s.copyWith(accentColor: color));

  Future<void> setFontScale(double scale) =>
      apply((AppearanceSettings s) => s.copyWith(fontScale: scale));

  Future<void> setChatTheme(String theme) =>
      apply((AppearanceSettings s) => s.copyWith(chatTheme: theme));

  Future<void> setAppIcon(String icon) =>
      apply((AppearanceSettings s) => s.copyWith(appIcon: icon));
}

/// Resolved [ThemeMode] for MaterialApp.
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((Ref ref) {
  final AppearanceSettings settings =
      ref.watch(appearanceProvider).valueOrNull ?? const AppearanceSettings();
  return switch (settings.themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
});

/// Resolved accent colour.
final Provider<Color> accentColorProvider = Provider<Color>((Ref ref) {
  final AppearanceSettings settings =
      ref.watch(appearanceProvider).valueOrNull ?? const AppearanceSettings();
  return Color(settings.accentColor);
});

/// Available accent choices for the Appearance screen.
const List<({String name, int value})> accentChoices =
    <({String name, int value})>[
  (name: 'Rose', value: 0xFFFF2D55),
  (name: 'Violet', value: 0xFF7B61FF),
  (name: 'Azure', value: 0xFF3BA9FF),
  (name: 'Emerald', value: 0xFF25D366),
  (name: 'Amber', value: 0xFFFFB020),
  (name: 'Coral', value: 0xFFFF6B4A),
  (name: 'Teal', value: 0xFF14B8A6),
  (name: 'Magenta', value: 0xFFD946EF),
];

/// The built-in default wallpaper, mirrored here for quick UI fallback.
const Wallpaper defaultWallpaper = Wallpaper(
  id: 'default',
  name: 'Default',
  kind: WallpaperKind.defaultPattern,
  colors: <int>[0xFF0B0B0D, 0xFF141417],
);

/// Every wallpaper offered by the picker, plus any custom image in use.
final Provider<List<Wallpaper>> wallpaperChoicesProvider =
    Provider<List<Wallpaper>>((Ref ref) {
  final List<Wallpaper> presets =
      List<Wallpaper>.from(LocalSettingsRepository.wallpapers);
  final Wallpaper? current = ref.watch(wallpaperProvider).valueOrNull;
  if (current != null &&
      current.kind == WallpaperKind.image &&
      !presets.any((Wallpaper w) => w.id == current.id)) {
    presets.insert(0, current);
  }
  return presets;
});

// ------------------------------------------------------------- other settings

final AsyncNotifierProvider<NotificationSettingsNotifier, NotificationSettings>
    notificationSettingsProvider = AsyncNotifierProvider<
        NotificationSettingsNotifier, NotificationSettings>(
  NotificationSettingsNotifier.new,
);

class NotificationSettingsNotifier extends AsyncNotifier<NotificationSettings> {
  @override
  Future<NotificationSettings> build() =>
      ref.read(settingsRepositoryProvider).getNotifications();

  Future<void> apply(NotificationSettings Function(NotificationSettings) change) async {
    final NotificationSettings current =
        state.valueOrNull ?? const NotificationSettings();
    final NotificationSettings next = change(current);
    state = AsyncData<NotificationSettings>(next);
    await ref.read(settingsRepositoryProvider).saveNotifications(next);
  }
}

final AsyncNotifierProvider<PrivacySettingsNotifier, PrivacySettings>
    privacySettingsProvider =
    AsyncNotifierProvider<PrivacySettingsNotifier, PrivacySettings>(
  PrivacySettingsNotifier.new,
);

class PrivacySettingsNotifier extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() =>
      ref.read(settingsRepositoryProvider).getPrivacy();

  Future<void> apply(PrivacySettings Function(PrivacySettings) change) async {
    final PrivacySettings current =
        state.valueOrNull ?? const PrivacySettings();
    final PrivacySettings next = change(current);
    state = AsyncData<PrivacySettings>(next);
    await ref.read(settingsRepositoryProvider).savePrivacy(next);
  }
}

final AsyncNotifierProvider<ChatSettingsNotifier, ChatSettings>
    chatSettingsProvider =
    AsyncNotifierProvider<ChatSettingsNotifier, ChatSettings>(
  ChatSettingsNotifier.new,
);

class ChatSettingsNotifier extends AsyncNotifier<ChatSettings> {
  @override
  Future<ChatSettings> build() =>
      ref.read(settingsRepositoryProvider).getChatSettings();

  Future<void> apply(ChatSettings Function(ChatSettings) change) async {
    final ChatSettings current = state.valueOrNull ?? const ChatSettings();
    final ChatSettings next = change(current);
    state = AsyncData<ChatSettings>(next);
    await ref.read(settingsRepositoryProvider).saveChatSettings(next);
  }
}

final AsyncNotifierProvider<WallpaperNotifier, Wallpaper> wallpaperProvider =
    AsyncNotifierProvider<WallpaperNotifier, Wallpaper>(WallpaperNotifier.new);

class WallpaperNotifier extends AsyncNotifier<Wallpaper> {
  @override
  Future<Wallpaper> build() =>
      ref.read(settingsRepositoryProvider).getWallpaper();

  Future<void> select(Wallpaper wallpaper) async {
    state = AsyncData<Wallpaper>(wallpaper);
    await ref.read(settingsRepositoryProvider).saveWallpaper(wallpaper);
  }
}

/// Application language code (`en` / `bn`).
final AsyncNotifierProvider<LanguageNotifier, String> languageProvider =
    AsyncNotifierProvider<LanguageNotifier, String>(LanguageNotifier.new);

class LanguageNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() => ref.read(settingsRepositoryProvider).getLanguage();

  Future<void> select(String code) async {
    state = AsyncData<String>(code);
    await ref.read(settingsRepositoryProvider).setLanguage(code);
  }
}

/// Whether saving a contact should offer to write it to the device address book.
final AsyncNotifierProvider<SyncContactsNotifier, bool>
    syncContactsOnSaveProvider =
    AsyncNotifierProvider<SyncContactsNotifier, bool>(
  SyncContactsNotifier.new,
);

class SyncContactsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.read(settingsRepositoryProvider).getSyncContactsOnSave();

  Future<void> select(bool value) async {
    state = AsyncData<bool>(value);
    await ref.read(settingsRepositoryProvider).setSyncContactsOnSave(value);
  }
}

// ============================================================================
// Contacts
// ============================================================================

final AsyncNotifierProvider<ContactsNotifier, List<Contact>> contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, List<Contact>>(ContactsNotifier.new);

class ContactsNotifier extends AsyncNotifier<List<Contact>> {
  ContactRepository get _repo => ref.read(contactRepositoryProvider);

  @override
  Future<List<Contact>> build() => _repo.getAll();

  void _set(List<Contact> list) => state = AsyncData<List<Contact>>(list);

  Future<void> refresh() async => _set(await _repo.getAll());

  Future<Contact> create(Contact contact) async {
    final Contact saved = await _repo.save(contact);
    await refresh();
    return saved;
  }

  Future<void> persist(Contact contact) async {
    await _repo.save(contact);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    await refresh();
  }

  Future<void> toggleFavorite(String id) async {
    final Contact? existing = await _repo.findById(id);
    if (existing == null) return;
    await _repo.setFavorite(id, !existing.isFavorite);
    await refresh();
  }

  Future<void> toggleBlocked(String id) async {
    final Contact? existing = await _repo.findById(id);
    if (existing == null) return;
    await _repo.setBlocked(id, !existing.isBlocked);
    await refresh();
  }

  /// Replaces the whole contact list — used by "sync device contacts".
  Future<void> reconcile(List<Contact> deviceContacts) async {
    final List<Contact> current = await _repo.getAll();
    final Set<String> existingPhones = current
        .map((Contact c) => c.phone.replaceAll(RegExp(r'[^0-9]'), ''))
        .where((String p) => p.isNotEmpty)
        .toSet();
    final List<Contact> incoming = deviceContacts
        .where((Contact c) =>
            !existingPhones.contains(c.phone.replaceAll(RegExp(r'[^0-9]'), '')) ||
            c.phone.isEmpty)
        .toList();
    if (incoming.isEmpty) return;
    await _repo.saveAll(incoming);
    await refresh();
  }
}

/// The local user's own profile.
final AsyncNotifierProvider<SelfProfileNotifier, Contact> selfProfileProvider =
    AsyncNotifierProvider<SelfProfileNotifier, Contact>(SelfProfileNotifier.new);

class SelfProfileNotifier extends AsyncNotifier<Contact> {
  @override
  Future<Contact> build() async {
    final ContactRepository repo = ref.read(contactRepositoryProvider);
    final Contact local = await repo.getSelfProfile();

    // The local copy is the user's own — possibly hand-edited — profile, so it
    // always wins. Only fill in from the network when there is nothing here.
    if (selfProfileHasIdentity(local)) return local;

    // Nothing on this device yet: a fresh install, or a new phone.
    //
    // This path matters most for Google and phone sign-ins. `auth_gate`
    // decides whether to detour through profile setup using Firebase Auth's
    // `displayName`, and both of those flows populate that — so those users
    // skip profile setup entirely and, without this lookup, would never get a
    // profile here at all. The profile screen and every "me" avatar would sit
    // on their empty-state placeholders even though `users/{uid}` is complete.
    //
    // `RemoteContactService` is a stateless `const`, and this file cannot reach
    // `remoteContactServiceProvider` without a circular import (that module
    // imports this one), so the service is constructed directly.
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return local;

    final RemoteProfile? remote =
        (await const RemoteContactService().findByUid(uid)).profile;
    if (remote == null) return local;

    final Contact hydrated = mergeDirectoryIntoSelf(local, remote);
    try {
      await repo.saveSelfProfile(hydrated);
    } on Object catch (error) {
      // Best-effort caching: the profile is still correct for this session.
      debugPrint('Caching the directory profile for $uid failed: $error');
    }
    return hydrated;
  }

  Future<void> save(Contact contact) async {
    await ref.read(contactRepositoryProvider).saveSelfProfile(contact);
    state = AsyncData<Contact>(contact);
  }
}

/// True once the local profile holds something the user would recognise as
/// their own — a name, a handle, or a number. A first-run profile is
/// deliberately blank, so this is what tells "never set up" apart from "set up
/// with only an avatar".
@visibleForTesting
bool selfProfileHasIdentity(Contact contact) =>
    contact.fullName.trim().isNotEmpty ||
    contact.username.trim().isNotEmpty ||
    contact.phone.trim().isNotEmpty;

/// Folds a directory document into the local self profile.
///
/// Only the fields the directory actually owns are taken, and each is ignored
/// when the document has nothing to say — so a sparse `users/{uid}` cannot blank
/// out something already known. Local-only presentation state (`avatarPath`,
/// `avatarColor`, favourites, blocks) is deliberately left alone, matching the
/// convention `mirrorRemoteChat` follows.
@visibleForTesting
Contact mergeDirectoryIntoSelf(Contact local, RemoteProfile remote) {
  final List<String> parts = remote.name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .toList();
  final String first = parts.isEmpty ? '' : parts.first;
  final String last = parts.length > 1 ? parts.skip(1).join(' ') : '';

  return local.copyWith(
    firstName: first.isNotEmpty ? first : local.firstName,
    lastName: last.isNotEmpty ? last : local.lastName,
    username: remote.username.isNotEmpty ? remote.username : local.username,
    phone: remote.phone.isNotEmpty ? remote.phone : local.phone,
    bio: remote.bio.isNotEmpty ? remote.bio : local.bio,
    // The directory avatar is what lets a *new device* (or one whose local
    // media was cleared) still show the user's own picture. Local wins when the
    // user picked one here, because that file is already on disk.
    avatarUrl: remote.avatarUrl.isNotEmpty ? remote.avatarUrl : local.avatarUrl,
    isOnline: remote.isOnline,
    lastSeen: remote.lastSeen ?? local.lastSeen,
    isSelf: true,
  );
}

/// Favourite contacts, in the order stored.
final Provider<AsyncValue<List<Contact>>> favoritesProvider =
    Provider<AsyncValue<List<Contact>>>((Ref ref) {
  return ref.watch(contactsProvider).whenData(
        (List<Contact> list) => list.where((Contact c) => c.isFavorite).toList(),
      );
});

/// Blocked contacts.
final Provider<AsyncValue<List<Contact>>> blockedContactsProvider =
    Provider<AsyncValue<List<Contact>>>((Ref ref) {
  return ref.watch(contactsProvider).whenData(
        (List<Contact> list) => list.where((Contact c) => c.isBlocked).toList(),
      );
});

/// Looks up a contact by id.
final contactByIdProvider = Provider.family<AsyncValue<Contact?>, String>((Ref ref, String id) {
  return ref.watch(contactsProvider).whenData(
        (List<Contact> list) =>
            list.where((Contact c) => c.id == id).firstOrNull,
      );
});

/// Filters contacts by a free-text query.
final contactSearchProvider = Provider.family<List<Contact>, String>((Ref ref, String query) {
  final List<Contact> all = ref.watch(contactsProvider).valueOrNull ?? <Contact>[];
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return all
      .where((Contact c) =>
          c.fullName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q))
      .toList();
});

/// The device address book, read once and cached for the session.
///
/// Reading the system contact store is a permission-gated platform call, so it
/// is kept out of the hot path: the Contacts tab and the new-chat sheet both
/// watch this and get an empty list when access has not been granted.
final FutureProvider<List<Contact>> deviceContactsProvider =
    FutureProvider<List<Contact>>((Ref ref) async {
  final DeviceContactService service = ref.watch(deviceContactServiceProvider);
  return service.read();
});

/// Stored contacts plus the people saved on the phone, de-duplicated by number.
///
/// The app's own contact list wins on a collision, so anything the user has
/// edited here (favourite, block, custom avatar) is never replaced by the raw
/// address-book entry. This is what the Contacts tab and the Calls tab list.
final Provider<List<Contact>> allContactsProvider =
    Provider<List<Contact>>((Ref ref) {
  final List<Contact> stored = ref.watch(contactsProvider).valueOrNull ?? <Contact>[];
  final List<Contact> device = ref.watch(deviceContactsProvider).valueOrNull ?? <Contact>[];

  if (device.isEmpty) {
    return stored.where((Contact c) => !c.isSelf).toList(growable: false);
  }

  String digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  final Set<String> knownNumbers = stored
      .map((Contact c) => digits(c.phone))
      .where((String p) => p.isNotEmpty)
      .toSet();
  final Set<String> knownIds = stored.map((Contact c) => c.id).toSet();

  final List<Contact> merged = <Contact>[
    ...stored.where((Contact c) => !c.isSelf),
    ...device.where(
      (Contact c) =>
          !knownIds.contains(c.id) &&
          (digits(c.phone).isEmpty || !knownNumbers.contains(digits(c.phone))),
    ),
  ];
  merged.sort((Contact a, Contact b) => a.sortedKey.compareTo(b.sortedKey));
  return List<Contact>.unmodifiable(merged);
});

/// The merged list split into A–Z buckets, for the indexed contact list.
final Provider<Map<String, List<Contact>>> groupedContactsProvider =
    Provider<Map<String, List<Contact>>>((Ref ref) {
  final Map<String, List<Contact>> grouped = <String, List<Contact>>{};
  for (final Contact contact in ref.watch(allContactsProvider)) {
    final String name = contact.fullName.trim();
    final String letter =
        name.isEmpty ? '#' : name.substring(0, 1).toUpperCase();
    // Anything that is not a letter (digits, emoji) falls into the '#' bucket
    // so the index never grows an unbounded tail of one-off headers.
    final String key = RegExp(r'^[A-Z]$').hasMatch(letter) ? letter : '#';
    grouped.putIfAbsent(key, () => <Contact>[]).add(contact);
  }
  return grouped;
});

// ============================================================================
// Chats
// ============================================================================

final AsyncNotifierProvider<ChatsNotifier, List<Chat>> chatsProvider =
    AsyncNotifierProvider<ChatsNotifier, List<Chat>>(ChatsNotifier.new);

class ChatsNotifier extends AsyncNotifier<List<Chat>> {
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  Future<List<Chat>> build() => _repo.getAll();

  void _set(List<Chat> list) => state = AsyncData<List<Chat>>(list);

  Future<void> refresh() async => _set(await _repo.getAll());

  Future<Chat> create(Chat chat) async {
    await _repo.save(chat);
    await refresh();
    return chat;
  }

  Future<void> save(Chat chat) async {
    await _repo.save(chat);
    await refresh();
  }

  Future<void> markRead(String id) async {
    await _repo.markRead(id);
    await refresh();
  }

  Future<void> markUnread(String id) async {
    await _repo.markUnread(id);
    await refresh();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await refresh();
  }

  Future<void> togglePin(String id) async {
    final Chat? chat = await _repo.findById(id);
    if (chat == null) return;
    await _repo.setPinned(id, !chat.isPinned);
    await refresh();
  }

  Future<void> toggleMute(String id) async {
    final Chat? chat = await _repo.findById(id);
    if (chat == null) return;
    await _repo.setMuted(id, !chat.isMuted);
    await refresh();
  }

  Future<void> toggleArchive(String id) async {
    final Chat? chat = await _repo.findById(id);
    if (chat == null) return;
    await _repo.setArchived(id, !chat.isArchived);
    await refresh();
  }

  Future<void> toggleFavorite(String id) async {
    final Chat? chat = await _repo.findById(id);
    if (chat == null) return;
    await _repo.setFavorite(id, !chat.isFavorite);
    await refresh();
  }

  Future<void> setDraft(String id, String draft) async {
    await _repo.setDraft(id, draft);
    await refresh();
  }

  /// Deletes a conversation from this device's list.
  ///
  /// ### Order, and what is deliberately not awaited
  ///
  /// 1. The local removal is written first and *emits immediately*: the row
  ///    leaves the list before this future completes, online or not.
  /// 2. The message store is cleared for the chat — also local, also immediate.
  /// 3. The remote leg runs **detached**. Nothing about "remove this chat from
  ///    my list" needs the network, and awaiting it is what left the row sitting
  ///    on screen until the round-trip finished: the reported "takes too long".
  ///
  /// The deletion index written by `ChatRepository.delete` is what makes the
  /// removal durable — without it the Firestore mirror re-adds the chat on its
  /// next snapshot, which is the "it comes back after 30 seconds" bug.
  Future<void> deleteChat(String id) async {
    InAppLogger.info('DELETE CHAT START: chatId=$id');
    await _repo.delete(id);
    InAppLogger.success('DELETE CHAT: removed from local Hive');
    await ref.read(messageRepositoryProvider).deleteForChat(id);
    InAppLogger.log('DELETE CHAT: local messages cleared');
    await refresh();
    InAppLogger.success('DELETE CHAT: removed from UI list');

    final String uid = ref.read(currentUidProvider);
    if (uid.isEmpty) return;
    unawaited(_deleteChatRemotely(id, uid));
  }

  /// The remote half of [deleteChat], deliberately detached.
  ///
  /// ⚠️ This never deletes a shared `chats/{chatId}` document while another
  /// participant is still in it. The document is shared by both sides of a 1:1
  /// conversation, so removing it would erase the conversation from the *other*
  /// person's list as well — "delete chat" means "remove it from mine", not
  /// "destroy it for both of us". It is removed only when this user is the last
  /// participant, where nobody else can lose anything.
  Future<void> _deleteChatRemotely(String chatId, String uid) async {
    try {
      final bool removed = await ref
          .read(firestoreChatServiceProvider)
          .deleteChatDocument(chatId: chatId, uid: uid);
      InAppLogger.log(
        removed
            ? 'DELETE CHAT: removed from Firestore'
            : 'DELETE CHAT: Firestore document kept (other participants remain)',
      );
    } on Object catch (error) {
      InAppLogger.warn('DELETE CHAT: remote cleanup failed ($error)');
    }
  }

  /// Clears messages but keeps the conversation entry.
  Future<void> clearChat(String id) async {
    await ref.read(messageRepositoryProvider).deleteForChat(id);
    await _repo.save(
      (await _repo.findById(id))?.copyWith(lastMessage: '') ??
          Chat(
            id: id,
            title: '',
            lastMessage: '',
            lastTimestamp: DateTime.now(),
          ),
    );
    await refresh();
  }

  /// Called after a message is sent so the chat index stays in sync.
  Future<void> touch(String chatId, Message message, {bool incrementUnread = false}) async {
    await _repo.updateLastMessage(chatId, message);
    if (incrementUnread) {
      final Chat? chat = await _repo.findById(chatId);
      if (chat == null) return;
      await _repo.save(
        chat.copyWith(
          unreadCount: chat.isMuted ? chat.unreadCount : chat.unreadCount + 1,
        ),
      );
    }
    await refresh();
  }

  /// Handles an incoming message from someone else.
  ///
  /// Increments the unread badge (unless the chat is muted) and refreshes the
  /// list so the new preview and timestamp appear immediately. This is the
  /// counterpart to [touch], which is used for the user's own outgoing sends —
  /// without it nothing ever raised the unread count.
  ///
  /// Opening a conversation calls [markRead], so a message arriving while the
  /// user is reading it is cleared by that same path rather than being
  /// suppressed here.
  Future<void> receive(String chatId, Message message) async {
    final Chat? chat = await _repo.findById(chatId);
    if (chat == null) return;

    await _repo.updateLastMessage(chatId, message);
    if (!chat.isMuted) {
      await _repo.save(chat.copyWith(unreadCount: chat.unreadCount + 1));
    }
    await refresh();
  }
}

/// Active chat-list filter.
enum ChatFilter { all, unread, favorites, groups, work }

extension ChatFilterX on ChatFilter {
  String get label => switch (this) {
        ChatFilter.all => 'All',
        ChatFilter.unread => 'Unread',
        ChatFilter.favorites => 'Favorites',
        ChatFilter.groups => 'Groups',
        ChatFilter.work => 'Work',
      };
}

final NotifierProvider<ChatFilterNotifier, ChatFilter> chatFilterProvider =
    NotifierProvider<ChatFilterNotifier, ChatFilter>(ChatFilterNotifier.new);

class ChatFilterNotifier extends Notifier<ChatFilter> {
  @override
  ChatFilter build() => ChatFilter.all;

  void select(ChatFilter filter) => state = filter;
}

/// Chats after the active filter is applied. Archived chats are always hidden
/// from the main list.
final Provider<List<Chat>> visibleChatsProvider = Provider<List<Chat>>((Ref ref) {
  return applyChatFilter(
    ref.watch(chatsProvider).valueOrNull ?? <Chat>[],
    ref.watch(chatFilterProvider),
  );
});

/// The chat-list filter, as a pure function.
///
/// Extracted so the Chats tab can filter the live Firestore-backed list with
/// exactly the same rules the local provider uses — one definition, so the two
/// can never drift apart.
List<Chat> applyChatFilter(List<Chat> chats, ChatFilter filter) {
  final List<Chat> active =
      chats.where((Chat c) => !c.isArchived).toList(growable: false);

  return switch (filter) {
    ChatFilter.all => active,
    ChatFilter.unread => active.where((Chat c) => c.hasUnread).toList(),
    ChatFilter.favorites => active.where((Chat c) => c.isFavorite).toList(),
    ChatFilter.groups => active
        .where((Chat c) => c.isGroup || c.isCommunity || c.isBroadcast)
        .toList(),
    ChatFilter.work => active.where((Chat c) => c.isWork).toList(),
  };
}

final Provider<List<Chat>> archivedChatsProvider = Provider<List<Chat>>((Ref ref) {
  final List<Chat> chats = ref.watch(chatsProvider).valueOrNull ?? <Chat>[];
  return chats.where((Chat c) => c.isArchived).toList();
});

final Provider<int> totalUnreadProvider = Provider<int>((Ref ref) {
  final List<Chat> chats = ref.watch(chatsProvider).valueOrNull ?? <Chat>[];
  return chats.fold<int>(0, (int sum, Chat c) => sum + c.unreadCount);
});

/// A single chat by id.
final chatByIdProvider = Provider.family<AsyncValue<Chat?>, String>((Ref ref, String id) {
  return ref.watch(chatsProvider).whenData(
        (List<Chat> list) => list.where((Chat c) => c.id == id).firstOrNull,
      );
});

/// Watches a chat reactively so screens update when metadata changes.
final chatStreamProvider = StreamProvider.family<Chat?, String>((Ref ref, String id) {
  final ChatRepository repo = ref.watch(chatRepositoryProvider);
  return repo.watchAll().map(
        (List<Chat> list) => list.where((Chat c) => c.id == id).firstOrNull,
      );
});

// ============================================================================
// Messages
// ============================================================================

/// Live message list for one conversation.
final messagesProvider = StreamProvider.family<List<Message>, String>((Ref ref, String chatId) {
  return ref.watch(messageRepositoryProvider).watchForChat(chatId);
});

/// Pagination / "jump to message" target used by starred & search results.
final StateProvider<String?> highlightedMessageProvider =
    StateProvider<String?>((Ref ref) => null);

/// All starred messages.
final AsyncNotifierProvider<StarredMessagesNotifier, List<Message>>
    starredMessagesProvider =
    AsyncNotifierProvider<StarredMessagesNotifier, List<Message>>(
  StarredMessagesNotifier.new,
);

class StarredMessagesNotifier extends AsyncNotifier<List<Message>> {
  @override
  Future<List<Message>> build() =>
      ref.read(messageRepositoryProvider).getStarred();

  Future<void> refresh() async =>
      state = AsyncData<List<Message>>(await ref.read(messageRepositoryProvider).getStarred());
}

/// Multi-select state for message selection mode.
final NotifierProvider<MessageSelectionNotifier, Set<String>>
    messageSelectionProvider =
    NotifierProvider<MessageSelectionNotifier, Set<String>>(
  MessageSelectionNotifier.new,
);

class MessageSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  bool get isActive => state.isNotEmpty;

  void toggle(String id) {
    final Set<String> next = Set<String>.from(state);
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void add(String id) => state = <String>{...state, id};

  void clear() => state = <String>{};
}

// ============================================================================
// Groups / communities / channels / statuses / calls
// ============================================================================

final AsyncNotifierProvider<GroupsNotifier, List<Group>> groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<Group>>(GroupsNotifier.new);

class GroupsNotifier extends AsyncNotifier<List<Group>> {
  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  @override
  Future<List<Group>> build() => _repo.getAll();

  Future<void> refresh() async =>
      state = AsyncData<List<Group>>(await _repo.getAll());

  Future<Group> save(Group group) async {
    final Group saved = await _repo.save(group);
    await refresh();
    return saved;
  }

  Future<void> addMembers(String groupId, List<String> contactIds) async {
    await _repo.addMembers(groupId, contactIds);
    await refresh();
  }

  Future<void> removeMember(String groupId, String contactId) async {
    await _repo.removeMember(groupId, contactId);
    await refresh();
  }

  Future<void> setRole(String groupId, String contactId, GroupRole role) async {
    await _repo.setRole(groupId, contactId, role);
    await refresh();
  }

  Future<void> updatePermissions(String groupId, GroupPermissions p) async {
    await _repo.updatePermissions(groupId, p);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await refresh();
  }
}

final groupByIdProvider = Provider.family<AsyncValue<Group?>, String>((Ref ref, String id) {
  return ref.watch(groupsProvider).whenData(
        (List<Group> list) => list.where((Group g) => g.id == id).firstOrNull,
      );
});

final AsyncNotifierProvider<CommunitiesNotifier, List<Community>>
    communitiesProvider =
    AsyncNotifierProvider<CommunitiesNotifier, List<Community>>(
  CommunitiesNotifier.new,
);

class CommunitiesNotifier extends AsyncNotifier<List<Community>> {
  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  Future<List<Community>> build() => _repo.getAll();

  Future<void> refresh() async =>
      state = AsyncData<List<Community>>(await _repo.getAll());

  Future<Community> create(Community community) async {
    final Community saved = await _repo.save(community);
    // Every community gets an announcement group.
    await _repo.createAnnouncementGroup(saved.id);
    await refresh();
    return saved;
  }

  Future<void> persist(Community community) async {
    await _repo.save(community);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await refresh();
  }
}

final communityByIdProvider = Provider.family<AsyncValue<Community?>, String>((Ref ref, String id) {
  return ref.watch(communitiesProvider).whenData(
        (List<Community> list) =>
            list.where((Community c) => c.id == id).firstOrNull,
      );
});

final AsyncNotifierProvider<ChannelsNotifier, List<Channel>> channelsProvider =
    AsyncNotifierProvider<ChannelsNotifier, List<Channel>>(ChannelsNotifier.new);

class ChannelsNotifier extends AsyncNotifier<List<Channel>> {
  ChannelRepository get _repo => ref.read(channelRepositoryProvider);

  @override
  Future<List<Channel>> build() => _repo.getAll();

  Future<void> refresh() async =>
      state = AsyncData<List<Channel>>(await _repo.getAll());

  Future<Channel> create(Channel channel) async {
    final Channel saved = await _repo.save(channel);
    await refresh();
    return saved;
  }

  Future<void> persist(Channel channel) async {
    await _repo.save(channel);
    await refresh();
  }

  Future<void> toggleFollow(String id) async {
    final Channel? channel = await _repo.findById(id);
    if (channel == null) return;
    await _repo.setFollowing(id, !channel.isFollowing);
    await refresh();
  }

  Future<void> toggleMute(String id) async {
    final Channel? channel = await _repo.findById(id);
    if (channel == null) return;
    await _repo.setMuted(id, !channel.isMuted);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await refresh();
  }
}

final Provider<List<Channel>> followedChannelsProvider = Provider<List<Channel>>((Ref ref) {
  final List<Channel> list = ref.watch(channelsProvider).valueOrNull ?? <Channel>[];
  return list.where((Channel c) => c.isFollowing).toList();
});

/// The channels that belong in the merged Chats tab.
///
/// A channel earns a row if the viewer follows it **or** owns it. Ownership is
/// included because an owner who is not listed as a follower of their own
/// channel would lose the only entry point to it — the Communities tab is for
/// discovery and management, not for reading, and the directive's whole point
/// is that a channel is read like a conversation.
///
/// Muted channels are kept. `isMuted` suppresses the *notification*, not the
/// row: hiding a channel the user deliberately muted would be a different
/// feature than the one the mute control promises.
final Provider<List<Channel>> chatListChannelsProvider =
    Provider<List<Channel>>((Ref ref) {
  final String uid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';
  final List<Channel> list = ref.watch(channelsProvider).valueOrNull ?? <Channel>[];
  return list
      .where((Channel c) =>
          c.isFollowing || (uid.isNotEmpty && c.ownerId == uid))
      .toList();
});

/// Conversations and channels as one recency-ordered list.
///
/// The single source for the Chats tab. Kept as a `Provider` over the two
/// existing providers so it recomputes when either changes, and so the merge
/// itself stays a pure function that a test can call directly.
final Provider<List<ChatRow>> mergedChatRowsProvider =
    Provider<List<ChatRow>>((Ref ref) {
  final List<Chat> chats = ref.watch(visibleChatsProvider);
  final List<Channel> channels = ref.watch(chatListChannelsProvider);
  return mergeChatRows(chats: chats, channels: channels);
});

/// Total unread across conversations *and* channels, for the tab badge.
final Provider<int> totalUnreadWithChannelsProvider = Provider<int>((Ref ref) {
  final int fromChats = ref.watch(totalUnreadProvider);
  final int fromChannels = ref
      .watch(chatListChannelsProvider)
      .where((Channel c) => !c.isMuted && c.hasUnread)
      .length;
  return fromChats + fromChannels;
});

final channelByIdProvider = Provider.family<AsyncValue<Channel?>, String>((Ref ref, String id) {
  return ref.watch(channelsProvider).whenData(
        (List<Channel> list) => list.where((Channel c) => c.id == id).firstOrNull,
      );
});

final AsyncNotifierProvider<StatusesNotifier, List<Status>> statusesProvider =
    AsyncNotifierProvider<StatusesNotifier, List<Status>>(StatusesNotifier.new);

class StatusesNotifier extends AsyncNotifier<List<Status>> {
  StatusRepository get _repo => ref.read(statusRepositoryProvider);

  @override
  Future<List<Status>> build() => _repo.getAll();

  Future<void> refresh() async =>
      state = AsyncData<List<Status>>(await _repo.getAll());

  Future<void> add(Status status) async {
    await _repo.save(status);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    await refresh();
  }

  Future<void> markViewed(String id, String viewerId) async {
    await _repo.markViewed(id, viewerId);
    await refresh();
  }
}

/// Statuses grouped by author, newest first.
final Provider<Map<String, List<Status>>> statusGroupsProvider =
    Provider<Map<String, List<Status>>>((Ref ref) {
  final List<Status> all = ref.watch(statusesProvider).valueOrNull ?? <Status>[];
  final Map<String, List<Status>> grouped = <String, List<Status>>{};
  for (final Status status in all) {
    grouped.putIfAbsent(status.authorId, () => <Status>[]).add(status);
  }
  for (final List<Status> list in grouped.values) {
    list.sort((Status a, Status b) =>
        (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
  }
  return grouped;
});

final AsyncNotifierProvider<CallsNotifier, List<CallRecord>> callsProvider =
    AsyncNotifierProvider<CallsNotifier, List<CallRecord>>(CallsNotifier.new);

class CallsNotifier extends AsyncNotifier<List<CallRecord>> {
  CallRepository get _repo => ref.read(callRepositoryProvider);

  @override
  Future<List<CallRecord>> build() => _repo.getAll();

  Future<void> refresh() async =>
      state = AsyncData<List<CallRecord>>(await _repo.getAll());

  Future<void> add(CallRecord record) async {
    await _repo.save(record);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    await refresh();
  }

  Future<void> clearHistory() async {
    await _repo.clearHistory();
    await refresh();
  }
}

final Provider<List<CallRecord>> missedCallsProvider = Provider<List<CallRecord>>((Ref ref) {
  final List<CallRecord> list = ref.watch(callsProvider).valueOrNull ?? <CallRecord>[];
  return list.where((CallRecord c) => c.isMissed).toList();
});

final AsyncNotifierProvider<ScheduledCallsNotifier, List<ScheduledCall>>
    scheduledCallsProvider =
    AsyncNotifierProvider<ScheduledCallsNotifier, List<ScheduledCall>>(
  ScheduledCallsNotifier.new,
);

class ScheduledCallsNotifier extends AsyncNotifier<List<ScheduledCall>> {
  CallRepository get _repo => ref.read(callRepositoryProvider);

  @override
  Future<List<ScheduledCall>> build() => _repo.getScheduled();

  Future<void> refresh() async =>
      state = AsyncData<List<ScheduledCall>>(await _repo.getScheduled());

  Future<void> add(ScheduledCall call) async {
    await _repo.saveScheduled(call);
    await refresh();
    await ref.read(notificationServiceProvider).scheduleCallReminder(
          id: call.id,
          title: call.title,
          body: L10nRef.current.scheduledCallWith(call.contactName),
          at: call.scheduledAt.subtract(
            Duration(minutes: call.remindMinutesBefore),
          ),
        );
  }

  Future<void> remove(String id) async {
    await _repo.deleteScheduled(id);
    await ref.read(notificationServiceProvider).cancel(id);
    await refresh();
  }
}

// ============================================================================
// Global search
// ============================================================================

/// A unified search result row.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.chatId,
    this.timestamp,
    this.avatarPath,
    this.matchQuery,
  });

  final SearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? chatId;
  final DateTime? timestamp;
  final String? avatarPath;
  final String? matchQuery;
}

enum SearchKind { chat, contact, message, group, community, channel }

/// Recent search history.
final AsyncNotifierProvider<RecentSearchesNotifier, List<String>>
    recentSearchesProvider =
    AsyncNotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() =>
      ref.read(settingsRepositoryProvider).getRecentSearches();

  Future<void> add(String query) async {
    await ref.read(settingsRepositoryProvider).addRecentSearch(query);
    state = AsyncData<List<String>>(
      await ref.read(settingsRepositoryProvider).getRecentSearches(),
    );
  }

  Future<void> remove(String query) async {
    await ref.read(settingsRepositoryProvider).removeRecentSearch(query);
    state = AsyncData<List<String>>(
      await ref.read(settingsRepositoryProvider).getRecentSearches(),
    );
  }

  Future<void> clear() async {
    await ref.read(settingsRepositoryProvider).clearRecentSearches();
    state = const AsyncData<List<String>>(<String>[]);
  }
}

/// Runs a global search across every content type.
final globalSearchProvider = FutureProvider.family<List<SearchHit>, String>((Ref ref, String query) async {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return <SearchHit>[];

  final List<SearchHit> hits = <SearchHit>[];

  final List<Chat> chats = await ref.read(chatRepositoryProvider).getAll();
  for (final Chat chat in chats) {
    if (chat.title.toLowerCase().contains(q) ||
        chat.lastMessage.toLowerCase().contains(q)) {
      hits.add(
        SearchHit(
          kind: chat.isGroup
              ? SearchKind.group
              : chat.isCommunity
                  ? SearchKind.community
                  : chat.isChannel
                      ? SearchKind.channel
                      : SearchKind.chat,
          id: chat.id,
          title: chat.title,
          subtitle: chat.lastMessage,
          chatId: chat.id,
          timestamp: chat.lastTimestamp,
          avatarPath: chat.avatarPath,
          matchQuery: query,
        ),
      );
    }
  }

  final List<Contact> contacts = await ref.read(contactRepositoryProvider).getAll();
  for (final Contact contact in contacts) {
    if (contact.fullName.toLowerCase().contains(q) ||
        contact.username.toLowerCase().contains(q) ||
        contact.phone.toLowerCase().contains(q)) {
      hits.add(
        SearchHit(
          kind: SearchKind.contact,
          id: contact.id,
          title: contact.fullName,
          subtitle: contact.aboutText,
          avatarPath: contact.avatarPath,
          matchQuery: query,
        ),
      );
    }
  }

  final List<Message> messages =
      await ref.read(messageRepositoryProvider).search(query);
  for (final Message message in messages.take(40)) {
    final String chatTitle = chats
            .where((Chat c) => c.id == message.chatId)
            .map((Chat c) => c.title)
            .firstOrNull ??
        'Chat';
    hits.add(
      SearchHit(
        kind: SearchKind.message,
        id: message.id,
        title: chatTitle,
        subtitle: message.previewText,
        chatId: message.chatId,
        timestamp: message.timestamp,
        matchQuery: query,
      ),
    );
  }

  return hits;
});

// ============================================================================
// Broadcast lists / linked devices
// ============================================================================

final AsyncNotifierProvider<BroadcastListsNotifier, List<BroadcastList>>
    broadcastListsProvider =
    AsyncNotifierProvider<BroadcastListsNotifier, List<BroadcastList>>(
  BroadcastListsNotifier.new,
);

class BroadcastListsNotifier extends AsyncNotifier<List<BroadcastList>> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  Future<List<BroadcastList>> build() => _repo.getBroadcastLists();

  Future<void> refresh() async =>
      state = AsyncData<List<BroadcastList>>(await _repo.getBroadcastLists());

  Future<void> create(BroadcastList list) async {
    final List<BroadcastList> current = await _repo.getBroadcastLists();
    current.add(list);
    await _repo.saveBroadcastLists(current);
    await refresh();
  }

  Future<void> rename(String id, String name) async {
    final List<BroadcastList> current = await _repo.getBroadcastLists();
    final int index = current.indexWhere((BroadcastList l) => l.id == id);
    if (index == -1) return;
    current[index] = current[index].copyWith(name: name);
    await _repo.saveBroadcastLists(current);
    await refresh();
  }

  Future<void> updateRecipients(String id, List<String> recipientIds) async {
    final List<BroadcastList> current = await _repo.getBroadcastLists();
    final int index = current.indexWhere((BroadcastList l) => l.id == id);
    if (index == -1) return;
    current[index] = current[index].copyWith(recipientIds: recipientIds);
    await _repo.saveBroadcastLists(current);
    await refresh();
  }

  Future<void> remove(String id) async {
    final List<BroadcastList> current = await _repo.getBroadcastLists();
    current.removeWhere((BroadcastList l) => l.id == id);
    await _repo.saveBroadcastLists(current);
    await refresh();
  }
}

final AsyncNotifierProvider<LinkedDevicesNotifier, List<LinkedDevice>>
    linkedDevicesProvider =
    AsyncNotifierProvider<LinkedDevicesNotifier, List<LinkedDevice>>(
  LinkedDevicesNotifier.new,
);

class LinkedDevicesNotifier extends AsyncNotifier<List<LinkedDevice>> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  Future<List<LinkedDevice>> build() async {
    final List<LinkedDevice> existing = await _repo.getLinkedDevices();
    if (existing.isNotEmpty) return existing;

    // The one device the app can honestly report is the one it is running on.
    // No other device is invented: linking is a server-side handshake this
    // build does not perform, so claiming a second device exists would be
    // fabricating content.
    String label = Platform.operatingSystem;
    if (label.isNotEmpty) {
      label = '${label[0].toUpperCase()}${label.substring(1)}';
    }

    final List<LinkedDevice> current = <LinkedDevice>[
      LinkedDevice(
        id: 'current',
        name: label.isEmpty ? 'This device' : label,
        platform: Platform.operatingSystem,
        lastActive: DateTime.now(),
        isCurrent: true,
      ),
    ];
    await _repo.saveLinkedDevices(current);
    return current;
  }

  Future<void> unlink(String id) async {
    final List<LinkedDevice> current =
        await _repo.getLinkedDevices();
    current.removeWhere((LinkedDevice d) => d.id == id && !d.isCurrent);
    await _repo.saveLinkedDevices(current);
    state = AsyncData<List<LinkedDevice>>(current);
  }
}

// ============================================================================
// Storage stats
// ============================================================================

/// Per-folder media usage plus the key-value store footprint.
final FutureProvider<Map<String, int>> storageUsageProvider =
    FutureProvider<Map<String, int>>((Ref ref) async {
  final FileStorageService storage = ref.watch(fileStorageProvider);
  final Map<String, int> media = await storage.usageBreakdown();
  return media;
});

/// Convenience: total media bytes.
final Provider<int> totalStorageProvider = Provider<int>((Ref ref) {
  final Map<String, int>? usage = ref.watch(storageUsageProvider).valueOrNull;
  if (usage == null) return 0;
  return usage.values.fold<int>(0, (int a, int b) => a + b);
});

/// Chat counts used by the settings summary rows.
final Provider<int> chatCountProvider = Provider<int>((Ref ref) =>
    (ref.watch(chatsProvider).valueOrNull ?? <Chat>[]).length);

final Provider<int> contactCountProvider = Provider<int>((Ref ref) =>
    (ref.watch(contactsProvider).valueOrNull ?? <Contact>[]).length);

final Provider<int> starCountProvider = Provider<int>((Ref ref) =>
    (ref.watch(starredMessagesProvider).valueOrNull ?? <Message>[]).length);

/// Small helper used across feature screens.
extension AsyncListX<T> on AsyncValue<List<T>> {
  List<T> get orEmpty => valueOrNull ?? <T>[];
}
