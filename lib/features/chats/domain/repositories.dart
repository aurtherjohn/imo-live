import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/models/message.dart';
import '../../../core/models/settings.dart';
import '../../../core/models/status.dart';

/// Contract for every repository in the app.
///
/// The UI depends only on these interfaces. Today they are implemented by
/// `Local*Repository` classes backed by Hive; a Firebase/Supabase/WebSocket
/// implementation can be dropped in later without touching a single widget.
///
/// Each repository also documents its **remote integration point** — the place
/// a real backend would plug in.

// -------------------------------------------------------------------- chats

abstract interface class ChatRepository {
  Future<List<Chat>> getAll();
  Stream<List<Chat>> watchAll();

  /// Inserts or updates a chat.
  Future<void> save(Chat chat);
  Future<void> saveAll(List<Chat> chats);

  Future<Chat?> findById(String id);
  Future<void> delete(String id);
  Future<void> clear();

  /// Marks a chat read locally and clears its counter.
  Future<void> markRead(String id);
  Future<void> markUnread(String id);
  Future<void> markAllRead();
  Future<void> setPinned(String id, bool pinned);
  Future<void> setMuted(String id, bool muted);
  Future<void> setArchived(String id, bool archived);
  Future<void> setFavorite(String id, bool favorite);
  Future<void> setDraft(String id, String draft);
  Future<void> updateLastMessage(String chatId, Message message);

  /// TODO(remote): `RemoteChatRepository` would sync chat metadata and
  /// server-assigned timestamps through the backend's chat collection.
}

// ----------------------------------------------------------------- messages

abstract interface class MessageRepository {
  /// Messages for [chatId], oldest first.
  Future<List<Message>> getForChat(String chatId);
  Stream<List<Message>> watchForChat(String chatId);
  Future<Message?> findById(String id, {String? chatId});

  Future<void> save(Message message);
  Future<void> saveAll(List<Message> messages);

  Future<void> updateStatus(String id, dynamic status);
  Future<void> edit(String id, String newContent);

  /// Removes a message **from this device only**.
  ///
  /// ⚠️ Implementations must not touch the network. "Delete for me" is a
  /// unilateral, local act: the other participant's copy is not theirs to
  /// change, they are not told it happened, and there is nothing to
  /// acknowledge. A `RemoteMessageRepository` that implemented this as a
  /// server write — or worse, as a write *and* a wait for the peer to
  /// confirm — would be a different and much worse feature: the peer may be
  /// offline, may have blocked the user, or may never come back, and the row
  /// would sit in a "deleting…" state that never resolves.
  ///
  /// The implementation is therefore expected to be synchronous with respect
  /// to the network — the removal is durable the moment this future completes.
  ///
  /// [chatId] is a hint, not a requirement: when the caller already knows which
  /// conversation the message belongs to, passing it turns the lookup into a
  /// single read instead of a scan of every conversation on the device. That
  /// scan is what made deleting a message feel slow on an account with a long
  /// chat list.
  ///
  /// Contrast [deleteForEveryone], which *is* meant to reach the other device
  /// and is deliberately bounded by [Message.deleteForEveryoneWindow].
  Future<void> deleteForMe(String id, {String? chatId});

  /// Retracts a message for everyone, replacing it with a "deleted" notice.
  ///
  /// Returns whether the retraction actually happened. It is **refused** — not
  /// silently ignored — when the message is not the author's own, is already
  /// deleted, or is older than [Message.deleteForEveryoneWindow]. The window is
  /// re-checked here rather than trusted from the caller, because the action
  /// sheet is only one way in: a stale menu, a queued tap or a future call site
  /// would otherwise bypass it. See [Message.canDeleteForEveryoneAt].
  Future<bool> deleteForEveryone(String id, {String? chatId});
  Future<void> toggleStar(String id);
  Future<void> starAll(List<String> ids, bool starred);

  /// Flips the pinned flag on one message.
  ///
  /// Pinning is a local-first feature: the flag lives on the message row, so it
  /// survives a restart and needs no server. The UI derives the chat's pinned
  /// banner from [getPinned].
  Future<void> togglePin(String id);

  /// Every pinned, non-deleted message in [chatId], newest first.
  Future<List<Message>> getPinned(String chatId);

  Future<void> addReaction(String id, dynamic reaction);
  Future<void> removeReaction(String id, String emoji, String senderId);
  Future<void> votePoll(String messageId, String optionId, String voterId);
  Future<void> setRsvp(String messageId, String contactId, dynamic status);

  /// Full-text search across locally stored messages.
  Future<List<Message>> search(String query, {String? chatId});

  Future<List<Message>> getStarred();
  Future<List<Message>> getByChats(List<String> chatIds);
  Future<void> deleteForChat(String chatId);
  Future<void> clear();

  /// Removes messages whose disappearing timer elapsed.
  Future<int> purgeExpired();

  /// TODO(remote): `RemoteMessageRepository` would open a realtime channel and
  /// push `Message` payloads, keeping the same method surface.
}

// ---------------------------------------------------------------- contacts

abstract interface class ContactRepository {
  Future<List<Contact>> getAll();
  Stream<List<Contact>> watchAll();
  Future<Contact?> findById(String id);
  Future<Contact?> findByPhone(String phone);
  Future<Contact> save(Contact contact);
  Future<void> saveAll(List<Contact> contacts);
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> setFavorite(String id, bool favorite);
  Future<void> setBlocked(String id, bool blocked);
  Future<void> reorderFavorites(List<String> orderedIds);
  Future<List<Contact>> getFavorites();
  Future<List<Contact>> getBlocked();
  Future<Contact> getSelfProfile();
  Future<void> saveSelfProfile(Contact contact);
  Future<List<Contact>> search(String query);

  /// TODO(remote): `RemoteContactRepository` would reconcile with the device
  /// address book and the backend's contact graph.
}

// ------------------------------------------------------------------ groups

abstract interface class GroupRepository {
  Future<List<Group>> getAll();
  Stream<List<Group>> watchAll();
  Future<Group?> findById(String id);
  Future<Group> save(Group group);
  Future<void> delete(String id);
  Future<void> clear();
  Future<Group> addMembers(String groupId, List<String> contactIds);
  Future<Group> removeMember(String groupId, String contactId);
  Future<Group> setRole(String groupId, String contactId, dynamic role);
  Future<Group> updatePermissions(String groupId, dynamic permissions);
  Future<List<Group>> search(String query);
}

// ------------------------------------------------------------- communities

abstract interface class CommunityRepository {
  Future<List<Community>> getAll();
  Stream<List<Community>> watchAll();
  Future<Community?> findById(String id);
  Future<Community> save(Community community);
  Future<void> delete(String id);
  Future<void> clear();
  Future<Community> addGroup(String communityId, String groupId);
  Future<Community> createAnnouncementGroup(String communityId);
}

// ---------------------------------------------------------------- channels

abstract interface class ChannelRepository {
  Future<List<Channel>> getAll();
  Stream<List<Channel>> watchAll();
  Future<Channel?> findById(String id);
  Future<Channel> save(Channel channel);
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> setFollowing(String id, bool following);
  Future<void> setMuted(String id, bool muted);
  Future<List<Channel>> getFollowed();
  Future<List<Channel>> search(String query);
}

// ------------------------------------------------------------------ status

abstract interface class StatusRepository {
  Future<List<Status>> getAll();
  Stream<List<Status>> watchAll();
  Future<Status> save(Status status);
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> markViewed(String id, String viewerId);

  /// Drops statuses older than 24 hours.
  Future<int> purgeExpired();

  Future<List<Status>> getMyUpdates();
  Future<List<Status>> search(String query);
}

// ------------------------------------------------------------------- calls

abstract interface class CallRepository {
  Future<List<CallRecord>> getAll();
  Stream<List<CallRecord>> watchAll();
  Future<CallRecord> save(CallRecord record);
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> clearHistory();
  Future<List<ScheduledCall>> getScheduled();
  Future<ScheduledCall> saveScheduled(ScheduledCall call);
  Future<void> deleteScheduled(String id);
  Future<List<CallRecord>> search(String query);
}

// ---------------------------------------------------------------- settings

abstract interface class SettingsRepository {
  Future<AppearanceSettings> getAppearance();
  Future<void> saveAppearance(AppearanceSettings settings);
  Future<NotificationSettings> getNotifications();
  Future<void> saveNotifications(NotificationSettings settings);
  Future<PrivacySettings> getPrivacy();
  Future<void> savePrivacy(PrivacySettings settings);
  Future<ChatSettings> getChatSettings();
  Future<void> saveChatSettings(ChatSettings settings);
  Future<Wallpaper> getWallpaper();
  Future<void> saveWallpaper(Wallpaper wallpaper);
  Future<String> getLanguage();
  Future<void> setLanguage(String code);
  Future<List<String>> getRecentSearches();
  Future<void> addRecentSearch(String query);
  Future<void> removeRecentSearch(String query);
  Future<void> clearRecentSearches();
  Future<bool> getSyncContactsOnSave();
  Future<void> setSyncContactsOnSave(bool value);
  Future<List<LinkedDevice>> getLinkedDevices();
  Future<void> saveLinkedDevices(List<LinkedDevice> devices);
  Future<List<BroadcastList>> getBroadcastLists();
  Future<void> saveBroadcastLists(List<BroadcastList> lists);
  Future<void> resetAll();
}

// ------------------------------------------------------------------- media

abstract interface class MediaRepository {
  /// Abstract upload boundary. Returns a stable identifier for the stored item.
  ///
  /// TODO(remote): `RemoteMediaRepository` would upload the file and return a
  /// CDN URL. The local implementation returns the path unchanged so callers
  /// need no branching.
  Future<String> upload(String localPath);
  Future<void> delete(String identifier);
  Future<Map<String, int>> usageBreakdown();
  Future<int> totalUsage();
}

// ---------------------------------------------------------- notifications

abstract interface class NotificationRepository {
  Future<void> showMessage({
    required String chatId,
    required String title,
    required String body,
  });
  Future<void> showCall({required String title, required String body});
  Future<void> showStatus({required String title, required String body});
  Future<void> scheduleCallReminder({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  });
  Future<void> cancel(String id);
  Future<void> cancelAll();
}
