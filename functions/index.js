/**
 * Push delivery for Imo LIVE.
 *
 * Scope: **sending** only. The client owns the other half — it registers its
 * FCM token on `users/{uid}.fcmTokens` (an array, so a second device does not
 * overwrite the first) and routes the tap.
 *
 * Why server-side: a client must never hold an FCM server credential, or
 * anyone who unpacked the APK could push to every user.
 *
 * Why it exists at all: the in-app ring is a Firestore listener, so it only
 * runs while the callee's app is alive. A backgrounded or killed app is never
 * told a call is happening, so the caller hears it ring out and the callee's
 * phone never makes a sound. This closes that gap.
 *
 * The second trigger, `notifyChannelPost`, covers the other case where the app
 * being closed loses information: a channel post reaching a follower who is not
 * looking at the app. It has different fan-out (many followers, not one callee),
 * so it lives in its own module.
 *
 * The message contracts themselves live in `call_push.js` and `channel_push.js`
 * so they can be verified without credentials — run `node verify_push.js`.
 */
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions, logger} = require("firebase-functions");
const admin = require("firebase-admin");

const {
  calleeOf,
  shouldRing,
  buildCallMessage,
  deadTokens,
} = require("./call_push");

const {
  shouldNotifyPost,
  recipientsOf,
  ownerOf,
  buildPostMessage,
  MAX_RECIPIENTS,
} = require("./channel_push");

admin.initializeApp();

/**
 * Must match the Firestore database's location or the trigger will not deploy.
 *
 * Verified against the project rather than guessed:
 * `firebase firestore:databases:list --json` reports
 * `"locationId": "asia-southeast1"` for `imo-live-inc`. Re-check that if the
 * database is ever recreated.
 */
const REGION = "asia-southeast1";

setGlobalOptions({maxInstances: 10, region: REGION});

const CALLS = "calls";
const CHANNELS = "channels";
const POSTS = "posts";
const USERS = "users";
const TOKEN_FIELD = "fcmTokens";

/** FCM accepts at most 500 tokens per multicast send. */
const MAX_TOKENS_PER_SEND = 500;

exports.notifyIncomingCall = onDocumentCreated(
    {document: `${CALLS}/{callId}`, region: REGION},
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) return;

      const call = snapshot.data();
      const callId = event.params.callId;

      if (!shouldRing(call)) return;

      const calleeId = calleeOf(call);
      const tokens = await tokensFor(calleeId);
      if (tokens.length === 0) {
        // Not an error: the callee may never have granted notification
        // permission, or may have no device registered yet.
        logger.info("callee has no registered push token", {callId, calleeId});
        return;
      }

      const message = buildCallMessage(call, callId);

      for (let i = 0; i < tokens.length; i += MAX_TOKENS_PER_SEND) {
        const batch = tokens.slice(i, i + MAX_TOKENS_PER_SEND);
        const response = await admin
            .messaging()
            .sendEachForMulticast(Object.assign({tokens: batch}, message));

        logger.info("ring push sent", {
          callId,
          calleeId,
          sent: response.successCount,
          failed: response.failureCount,
        });

        await pruneDeadTokens(calleeId, batch, response);
      }
    },
);

/**
 * Every registered device token for an account.
 *
 * The field is an array because the same account on two phones would otherwise
 * overwrite one slot and the older device would silently stop receiving.
 *
 * @param {string} uid The account id.
 * @return {Promise<Array<string>>} The usable tokens, possibly empty.
 */
async function tokensFor(uid) {
  const snap = await admin.firestore().collection(USERS).doc(uid).get();
  const raw = snap.get(TOKEN_FIELD);
  if (!Array.isArray(raw)) return [];
  return raw.filter((token) => typeof token === "string" && token.length > 0);
}

/**
 * Rings every device belonging to a set of accounts, once each.
 *
 * A channel with N followers needs N accounts' tokens, and FCM's multicast
 * takes up to 500 at a time — but tokens are per *device*, so one call per
 * account would be N reads and N sends. This reads the accounts in chunks and
 * flattens the tokens into a single multicast per chunk, which is what keeps a
 * post to a large channel inside the function's time budget.
 *
 * @param {Array<string>} uids The follower account ids.
 * @param {object} message The message, minus tokens.
 * @return {Promise<void>} Resolves once every batch has been sent.
 */
async function sendToUsers(uids, message) {
  const accounts = uids || [];
  if (accounts.length === 0) return;

  // Firestore's `getAll` is capped; keep the read batch well under it.
  const READ_BATCH = 250;

  for (let i = 0; i < accounts.length; i += READ_BATCH) {
    const batch = accounts.slice(i, i + READ_BATCH);

    const snaps = await admin
        .firestore()
        .collection(USERS)
        .where(admin.firestore.FieldPath.documentId(), "in", batch)
        .get();

    // uid -> tokens, so a dead token can be pruned from the right account.
    const byUid = new Map();
    const tokens = [];
    snaps.forEach((snap) => {
      const raw = snap.get(TOKEN_FIELD);
      if (!Array.isArray(raw)) return;
      const usable = raw.filter(
          (token) => typeof token === "string" && token.length > 0,
      );
      if (usable.length === 0) return;
      byUid.set(snap.id, usable);
      tokens.push(...usable);
    });

    if (tokens.length === 0) continue;

    for (let j = 0; j < tokens.length; j += MAX_TOKENS_PER_SEND) {
      const slice = tokens.slice(j, j + MAX_TOKENS_PER_SEND);
      const response = await admin
          .messaging()
          .sendEachForMulticast(Object.assign({tokens: slice}, message));

      logger.info("channel post pushed", {
        sent: response.successCount,
        failed: response.failureCount,
      });

      await pruneFromAccounts(slice, response, byUid);
    }
  }
}

/**
 * Removes the permanently dead tokens from whichever account owned them.
 *
 * `deadTokens` returns the dead token strings without saying whose they are;
 * the `byUid` map is what turns them back into per-account updates.
 *
 * @param {Array<string>} slice The batch that was just sent, in order.
 * @param {object} response The `sendEachForMulticast` response for it.
 * @param {Map<string, Array<string>>} byUid Account id to its tokens.
 * @return {Promise<void>} Resolves once the dead tokens are removed.
 */
async function pruneFromAccounts(slice, response, byUid) {
  const dead = new Set(deadTokens(slice, response));
  if (dead.size === 0) return;

  for (const [uid, tokens] of byUid) {
    const mine = tokens.filter((token) => dead.has(token));
    if (mine.length === 0) continue;
    await admin
        .firestore()
        .collection(USERS)
        .doc(uid)
        .update({
          [TOKEN_FIELD]: admin.firestore.FieldValue.arrayRemove(...mine),
        });
  }

  logger.info("pruned dead push tokens", {count: dead.size});
}

/**
 * Notifies a channel's followers that a new post was published.
 *
 * The follower list is the `followers` subcollection, whose document id is the
 * follower's uid. The author is excluded inside `recipientsOf` — an owner does
 * not need telling about their own post.
 */
exports.notifyChannelPost = onDocumentCreated(
    {document: `${CHANNELS}/{channelId}/${POSTS}/{postId}`, region: REGION},
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) return;

      const post = snapshot.data();
      if (!shouldNotifyPost(post)) return;

      const channelId = event.params.channelId;
      const authorId = post.authorId || "";

      const channelSnap =
          await admin.firestore().collection(CHANNELS).doc(channelId).get();
      const channel = channelSnap.exists ? channelSnap.data() : {};

      // Never notify a channel's own posts back to its owner.
      const author = authorId || ownerOf(channel);

      const followers = await admin
          .firestore()
          .collection(CHANNELS)
          .doc(channelId)
          .collection("followers")
          .limit(MAX_RECIPIENTS)
          .get();

      const uids = recipientsOf(
          followers.docs.map((doc) => ({id: doc.id})),
          author,
      );

      if (uids.length === 0) {
        // Normal for a channel nobody follows yet, or a solo broadcast.
        logger.info("channel has no followers to notify", {channelId});
        return;
      }

      await sendToUsers(uids, buildPostMessage(channel, channelId, post));

      logger.info("channel post fan-out complete", {
        channelId,
        recipients: uids.length,
      });
    },
);

/**
 * Removes the tokens FCM has reported as permanently dead.
 *
 * Without this the array grows forever and every send pays for tokens that can
 * never work again — a reinstall or a cleared app is the usual cause.
 *
 * @param {string} uid The account id.
 * @param {Array<string>} batch The batch that was just sent.
 * @param {object} response The `sendEachForMulticast` response for that batch.
 * @return {Promise<void>} Resolves once the dead tokens are removed.
 */
async function pruneDeadTokens(uid, batch, response) {
  const dead = deadTokens(batch, response);
  if (dead.length === 0) return;

  await admin
      .firestore()
      .collection(USERS)
      .doc(uid)
      .update({
        [TOKEN_FIELD]: admin.firestore.FieldValue.arrayRemove(...dead),
      });

  logger.info("pruned dead push tokens", {uid, count: dead.length});
}
