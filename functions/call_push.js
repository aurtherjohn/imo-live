/**
 * Pure helpers for the incoming-call push.
 *
 * Deliberately free of any Firebase import: `verify_call_push.js` exercises
 * these with plain `node`, so the message contract can be checked without
 * credentials, an emulator or a test runner. `index.js` holds the I/O.
 */

/** Mirrors NotificationChannels.calls in the app's notification service. */
const CALL_CHANNEL = "imo_calls";

/**
 * Mirrors the app's ring timeout. A ring push that lands after the caller has
 * already given up is worse than no push: it rings a phone for a call that no
 * longer exists.
 */
const RING_TTL_MS = 45000;

/**
 * Failure codes that mean "this token will never work again".
 *
 * Only these are pruned. A transient failure — an internal FCM error, a quota,
 * a momentary outage — must NOT remove a token, or one bad minute would
 * silently unsubscribe a working device until it next opened the app.
 */
const PERMANENT_FAILURES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
];

/**
 * The callee's account id, under either spelling.
 *
 * The document carries both `receiverId` and `calleeId` so older clients keep
 * working; either is acceptable here.
 *
 * @param {object} call The `calls/{callId}` document data.
 * @return {string} The callee uid, or an empty string.
 */
function calleeOf(call) {
  if (!call) return "";
  return call.receiverId || call.calleeId || "";
}

/**
 * Whether a call document is one that should ring a phone.
 *
 * Only `ringing` qualifies. `calls/` also holds the terminal states, and
 * notifying on one of those would ring a phone for a call that is already over.
 *
 * @param {object} call The `calls/{callId}` document data.
 * @return {boolean} True when this document should produce a ring.
 */
function shouldRing(call) {
  if (!call || call.status !== "ringing") return false;
  return Boolean(calleeOf(call)) && Boolean(call.callerId);
}

/**
 * The FCM message for a ringing call, minus the tokens.
 *
 * Every value in `data` is a string: FCM rejects the whole message otherwise,
 * and the app's `PushPayload.fromData` reads strings anyway.
 *
 * @param {object} call The `calls/{callId}` document data.
 * @param {string} callId The document id, used to tag the notification.
 * @return {object} A message suitable for `sendEachForMulticast`.
 */
function buildCallMessage(call, callId) {
  const isVideo = call.isVideo === true || call.type === "video";
  const callerName = call.callerName || "Someone";
  const body = isVideo ? "Incoming video call" : "Incoming voice call";

  return {
    notification: {title: callerName, body},
    data: {
      type: "call",
      callerId: String(call.callerId || ""),
      isVideo: isVideo ? "true" : "false",
      title: String(callerName),
      body,
    },
    android: {
      // High priority so the message is delivered promptly rather than batched:
      // a call that rings ten minutes late is not a call.
      priority: "high",
      ttl: RING_TTL_MS,
      notification: {
        channel_id: CALL_CHANNEL,
        // One notification per call, replaced rather than stacked.
        tag: callId,
      },
    },
    apns: {
      headers: {"apns-priority": "10", "apns-push-type": "alert"},
      payload: {aps: {sound: "default"}},
    },
  };
}

/**
 * The tokens FCM has reported as permanently dead.
 *
 * @param {Array<string>} tokens The batch that was sent, in order.
 * @param {object} response The `sendEachForMulticast` response for that batch.
 * @return {Array<string>} The tokens to remove from the account.
 */
function deadTokens(tokens, response) {
  const dead = [];
  const responses = (response && response.responses) || [];

  responses.forEach((result, index) => {
    if (!result || result.success) return;
    // `?.` is ES2020 and this project lints at ecmaVersion 2018.
    const error = result.error;
    const code = error && error.code ? error.code : "";
    if (PERMANENT_FAILURES.indexOf(code) !== -1) dead.push(tokens[index]);
  });

  return dead;
}

module.exports = {
  CALL_CHANNEL,
  RING_TTL_MS,
  PERMANENT_FAILURES,
  calleeOf,
  shouldRing,
  buildCallMessage,
  deadTokens,
};
