/**
 * Pure helpers for the new-channel-post push.
 *
 * Same split as `call_push.js`: no Firebase import, so
 * `verify_channel_push.js` can exercise the message contract with plain
 * `node` and no credentials.
 *
 * ### Fan-out, not a token list
 *
 * A call has exactly one recipient, so `notifyIncomingCall` can look up one
 * account's tokens and send. A channel post has a *follower set*, which fan-out
 * over thousands of accounts, so this function returns the recipient uids and
 * the caller batches. That keeps the pure part pure and testable.
 */

/** Mirrors NotificationChannels.groups in the app's notification service. */
const CHANNEL_CHANNEL = "imo_groups";

/**
 * How many follower uids one post will notify.
 *
 * A cap exists because the followers subcollection is unbounded and a single
 * post to a 50 000-follower channel would burn the function's memory and time
 * budget enumerating the list. The fan-out is truncated rather than the whole
 * trigger failing; the first N followers are the ones who joined earliest.
 */
const MAX_RECIPIENTS = 2000;

/**
 * Longest post preview carried in the notification body.
 *
 * A notification body is a couple of lines; sending the whole post is wasteful
 * and truncated by the OS anyway.
 */
const PREVIEW_LIMIT = 120;

/**
 * The channel's owner, under either spelling.
 *
 * @param {object} channel The `channels/{channelId}` document data.
 * @return {string} The owner uid, or an empty string.
 */
function ownerOf(channel) {
  if (!channel) return "";
  return channel.ownerId || channel.owner || "";
}

/**
 * Whether a newly created post should notify the followers.
 *
 * Only posts notify. The `posts` subcollection also carries nothing else today,
 * but the guard keeps a future non-post document from paging every follower.
 *
 * @param {object} post The `channels/{id}/posts/{postId}` document data.
 * @return {boolean} True when this post should be pushed.
 */
function shouldNotifyPost(post) {
  if (!post) return false;
  // A post with neither text nor media would produce an empty notification.
  return Boolean(post.text) || Boolean(post.mediaUrl);
}

/**
 * The follower uids to notify, capped and de-duplicated.
 *
 * The author is removed: notifying an owner about their own post is noise, and
 * it is the single most common case for a small channel.
 *
 * @param {Array<object>} followerDocs The `followers` snapshot documents.
 * @param {string} authorId The uid that published, excluded from the result.
 * @return {Array<string>} Up to [MAX_RECIPIENTS] uids.
 */
function recipientsOf(followerDocs, authorId) {
  const seen = new Set();
  const out = [];
  const docs = followerDocs || [];
  for (const doc of docs) {
    if (out.length >= MAX_RECIPIENTS) break;
    // The document id is the uid; `id` is only set by the client mirror.
    const uid = (doc && (doc.id || doc.uid)) || "";
    if (!uid || uid === authorId || seen.has(uid)) continue;
    seen.add(uid);
    out.push(uid);
  }
  return out;
}

/**
 * The one-line summary of a post, for the notification body.
 *
 * Mirrors `ChannelFirestoreService._previewOf` so the notification and the
 * chat-list row describe the same post the same way.
 *
 * @param {object} post The post document data.
 * @return {string} A short, single-line preview.
 */
function previewOf(post) {
  const raw = post && post.text ? String(post.text) : "";
  const text = raw.replace(/\s+/g, " ").trim();
  if (text) {
    return text.length <= PREVIEW_LIMIT ?
      text :
      text.slice(0, PREVIEW_LIMIT) + "\u2026";
  }
  switch (post && post.mediaType) {
    case "image": return "Photo";
    case "video": return "Video";
    case "file": return "Document";
    case "voice": return "Voice message";
    default: return "New post";
  }
}

/**
 * The FCM message for a new channel post, minus the tokens.
 *
 * The `data` keys are the ones `PushPayload.fromData` reads. `type` is
 * `"message"` rather than a new kind, because the app already knows how to
 * route that — adding a `"channel"` kind would need an app release before any
 * push could be delivered, and would be dropped as `unknown` until then.
 *
 * @param {object} channel The channel document data.
 * @param {string} channelId The channel document id.
 * @param {object} post The post document data.
 * @return {object} A message suitable for `sendEachForMulticast`.
 */
function buildPostMessage(channel, channelId, post) {
  const name = (channel && channel.name) || "Channel";
  const body = previewOf(post);

  return {
    notification: {title: name, body},
    data: {
      type: "message",
      // The row key the tap opens. The app's `RowKeys.locationOf` reads this
      // prefix to choose between the channel view and a conversation; a bare
      // id would open the conversation route and render a chat that is not
      // there. Keep in sync with `RowKeys.channelPrefix`.
      chatId: "channel:" + String(channelId),
      title: String(name),
      body,
    },
    android: {
      priority: "normal",
      notification: {
        channel_id: CHANNEL_CHANNEL,
        // One notification per channel, replaced rather than stacked: a busy
        // channel would otherwise fill the shade with stale previews.
        tag: "channel_" + String(channelId),
      },
    },
    apns: {
      headers: {"apns-priority": "5", "apns-push-type": "alert"},
      payload: {aps: {sound: "default"}},
    },
  };
}

module.exports = {
  CHANNEL_CHANNEL,
  MAX_RECIPIENTS,
  PREVIEW_LIMIT,
  ownerOf,
  shouldNotifyPost,
  recipientsOf,
  previewOf,
  buildPostMessage,
};
