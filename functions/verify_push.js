/**
 * Verifies the push contracts without credentials, an emulator or a test
 * runner.
 *
 *   cd functions && node verify_push.js
 *
 * The contracts are not ours to invent: `PushPayload.fromData` in the app
 * parses these exact keys, and `NotificationChannels` names the Android
 * channels. Get one wrong and the push either arrives and is silently ignored,
 * or is rejected by FCM outright — and neither shows up until a real device
 * fails to ring or notify.
 *
 * The Dart constants are read out of the app source rather than retyped here,
 * so a rename on either side fails this check instead of failing in the field.
 */
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const {
  CALL_CHANNEL,
  RING_TTL_MS,
  shouldRing,
  buildCallMessage,
  deadTokens,
} = require("./call_push");

const {
  CHANNEL_CHANNEL,
  MAX_RECIPIENTS,
  PREVIEW_LIMIT,
  shouldNotifyPost,
  recipientsOf,
  ownerOf,
  previewOf,
  buildPostMessage,
} = require("./channel_push");

let checks = 0;

/**
 * Runs one named check and reports it.
 *
 * @param {string} name What is being verified.
 * @param {function(): void} body The assertions.
 * @return {void}
 */
function check(name, body) {
  body();
  checks += 1;
  console.log("  ok  " + name);
}

/**
 * Reads a file from the repository root.
 *
 * @param {string} relative Path relative to the repository root.
 * @return {string} The file contents.
 */
function readRepoFile(relative) {
  return fs.readFileSync(path.join(__dirname, "..", relative), "utf8");
}

/**
 * Pulls a `static const String <name> = '<value>'` out of Dart source.
 *
 * @param {string} source The Dart file contents.
 * @param {string} name The constant's identifier.
 * @return {string} Its value.
 */
function dartConst(source, name) {
  const pattern = new RegExp(
      "static\\s+const\\s+String\\s+" + name + "\\s*=\\s*'([^']+)'",
  );
  const match = pattern.exec(source);
  assert.ok(match, "could not find Dart constant `" + name + "`");
  return match[1];
}

const pushSource = readRepoFile(
    "lib/core/services/push_notification_service.dart",
);
const notificationSource = readRepoFile(
    "lib/core/services/notification_service.dart",
);

const RINGING = {
  status: "ringing",
  callerId: "uid-caller",
  callerName: "Ayesha",
  receiverId: "uid-callee",
  calleeId: "uid-callee",
  isVideo: false,
  type: "voice",
  channelName: "imo_uid-callee_uid-caller",
};

console.log("call_push contract:");

check("the channel id matches NotificationChannels.calls", () => {
  assert.strictEqual(CALL_CHANNEL, dartConst(notificationSource, "calls"));
});

check("a ringing document rings, and terminal ones do not", () => {
  assert.strictEqual(shouldRing(RINGING), true);
  for (const status of ["accepted", "ended", "declined", "missed", "active"]) {
    assert.strictEqual(
        shouldRing(Object.assign({}, RINGING, {status})),
        false,
        "status " + status + " must not ring a phone",
    );
  }
  assert.strictEqual(shouldRing(null), false);
  assert.strictEqual(shouldRing(undefined), false);
});

check("a call missing a caller or a callee is not sent", () => {
  assert.strictEqual(
      shouldRing(Object.assign({}, RINGING, {callerId: ""})),
      false,
  );
  assert.strictEqual(
      shouldRing(Object.assign({}, RINGING, {receiverId: "", calleeId: ""})),
      false,
  );
});

check("calleeId alone is accepted, for documents from an older client", () => {
  const older = Object.assign({}, RINGING, {receiverId: undefined});
  assert.strictEqual(shouldRing(older), true);
});

check("every data value is a string, as FCM requires", () => {
  const message = buildCallMessage(RINGING, "call-1");
  const keys = Object.keys(message.data);
  assert.ok(keys.length > 0, "data must not be empty");
  for (const key of keys) {
    assert.strictEqual(
        typeof message.data[key],
        "string",
        "data." + key + " must be a string",
    );
  }
});

check("the payload carries exactly the keys PushPayload reads", () => {
  const message = buildCallMessage(RINGING, "call-1");
  const expected = [
    dartConst(pushSource, "keyKind"),
    dartConst(pushSource, "keyCallerId"),
    dartConst(pushSource, "keyIsVideo"),
    dartConst(pushSource, "keyTitle"),
    dartConst(pushSource, "keyBody"),
  ].sort();
  assert.deepStrictEqual(Object.keys(message.data).sort(), expected);
});

check("type is PushKind.call, so the app routes it as a call", () => {
  const message = buildCallMessage(RINGING, "call-1");
  assert.strictEqual(message.data.type, dartConst(pushSource, "call"));
});

check("isVideo round-trips as the strings the app accepts", () => {
  const video = buildCallMessage(
      Object.assign({}, RINGING, {isVideo: true}), "call-1");
  assert.strictEqual(video.data.isVideo, "true");

  const videoByType = buildCallMessage(
      Object.assign({}, RINGING, {type: "video"}), "call-1");
  assert.strictEqual(videoByType.data.isVideo, "true");

  const voice = buildCallMessage(RINGING, "call-1");
  assert.strictEqual(voice.data.isVideo, "false");
});

check("a nameless caller still produces a usable title", () => {
  const message = buildCallMessage(
      Object.assign({}, RINGING, {callerName: ""}), "call-1");
  assert.strictEqual(message.data.title, "Someone");
  assert.strictEqual(message.notification.title, "Someone");
  assert.ok(message.notification.body.length > 0);
});

check("the notification is tagged per call and expires with the ring", () => {
  const message = buildCallMessage(RINGING, "call-abc");
  assert.strictEqual(message.android.notification.tag, "call-abc");
  assert.strictEqual(message.android.notification.channel_id, CALL_CHANNEL);
  assert.strictEqual(message.android.ttl, RING_TTL_MS);
  assert.strictEqual(message.android.priority, "high");
});

check("dead tokens are pruned, transient failures are not", () => {
  const tokens = ["good", "uninstalled", "transient", "malformed"];
  const response = {
    responses: [
      {success: true},
      {
        success: false,
        error: {code: "messaging/registration-token-not-registered"},
      },
      {success: false, error: {code: "messaging/internal-error"}},
      {
        success: false,
        error: {code: "messaging/invalid-registration-token"},
      },
    ],
  };
  assert.deepStrictEqual(deadTokens(tokens, response), [
    "uninstalled",
    "malformed",
  ]);
});

check("an all-successful send prunes nothing", () => {
  const tokens = ["a", "b"];
  const response = {responses: [{success: true}, {success: true}]};
  assert.deepStrictEqual(deadTokens(tokens, response), []);
});

// --------------------------------------------------------------- channel push

const GROUPS_CHANNEL = dartConst(notificationSource, "groups");

const CHANNEL_DOC = {name: "Dhaka News", ownerId: "uid-owner"};

const POST_IMAGE = {
  authorId: "uid-owner",
  text: "",
  mediaUrl: "https://cdn.example/p.jpg",
  mediaType: "image",
};

console.log("\nchannel_push contract:");

check("the channel id matches NotificationChannels.groups", () => {
  assert.strictEqual(CHANNEL_CHANNEL, GROUPS_CHANNEL);
});

check("a post with text or media notifies, an empty one does not", () => {
  assert.strictEqual(shouldNotifyPost({text: "hello"}), true);
  assert.strictEqual(shouldNotifyPost(POST_IMAGE), true);
  assert.strictEqual(shouldNotifyPost({text: "", mediaUrl: ""}), false);
  assert.strictEqual(shouldNotifyPost(null), false);
  assert.strictEqual(shouldNotifyPost(undefined), false);
});

check("the author is not notified about their own post", () => {
  const docs = [
    {id: "uid-owner"},
    {id: "uid-a"},
    {id: "uid-b"},
  ];
  assert.deepStrictEqual(recipientsOf(docs, "uid-owner"), ["uid-a", "uid-b"]);
});

check("duplicate followers are collapsed, and empties are skipped", () => {
  const docs = [
    {id: "uid-a"},
    {id: "uid-a"},
    {id: ""},
    {id: "uid-b"},
  ];
  assert.deepStrictEqual(recipientsOf(docs, "uid-owner"), ["uid-a", "uid-b"]);
  assert.deepStrictEqual(recipientsOf([], "uid-owner"), []);
  assert.deepStrictEqual(recipientsOf(null, "uid-owner"), []);
});

check("the fan-out is capped, so one post cannot page unbounded", () => {
  const docs = [];
  for (let i = 0; i < MAX_RECIPIENTS + 50; i += 1) {
    docs.push({id: "uid-" + i});
  }
  assert.strictEqual(recipientsOf(docs, "").length, MAX_RECIPIENTS);
});

check("the owner is found under either spelling", () => {
  assert.strictEqual(ownerOf({ownerId: "a"}), "a");
  assert.strictEqual(ownerOf({owner: "b"}), "b");
  assert.strictEqual(ownerOf({}), "");
  assert.strictEqual(ownerOf(null), "");
});

check("a text post previews its text, truncated with an ellipsis", () => {
  assert.strictEqual(previewOf({text: "  hello   world  "}), "hello world");
  const long = "x".repeat(PREVIEW_LIMIT + 40);
  const preview = previewOf({text: long});
  assert.strictEqual(preview.length, PREVIEW_LIMIT + 1);
  assert.ok(preview.endsWith("\u2026"));
});

check("a media-only post previews its kind, never an empty body", () => {
  assert.strictEqual(previewOf(POST_IMAGE), "Photo");
  assert.strictEqual(previewOf({mediaType: "video", mediaUrl: "u"}), "Video");
  assert.strictEqual(previewOf({mediaType: "file", mediaUrl: "u"}), "Document");
  assert.strictEqual(previewOf({mediaType: "voice", mediaUrl: "u"}), "Voice message");
  assert.strictEqual(previewOf({}), "New post");
});

check("every data value is a string, as FCM requires", () => {
  const message = buildPostMessage(CHANNEL_DOC, "chan-1", POST_IMAGE);
  const keys = Object.keys(message.data);
  assert.ok(keys.length > 0, "data must not be empty");
  for (const key of keys) {
    assert.strictEqual(
        typeof message.data[key],
        "string",
        "data." + key + " must be a string",
    );
  }
});

check("the payload carries exactly the keys PushPayload reads", () => {
  const message = buildPostMessage(CHANNEL_DOC, "chan-1", POST_IMAGE);
  const expected = [
    dartConst(pushSource, "keyKind"),
    dartConst(pushSource, "keyChatId"),
    dartConst(pushSource, "keyTitle"),
    dartConst(pushSource, "keyBody"),
  ].sort();
  assert.deepStrictEqual(Object.keys(message.data).sort(), expected);
});

check("type is PushKind.message, so the app routes it as a chat", () => {
  const message = buildPostMessage(CHANNEL_DOC, "chan-1", POST_IMAGE);
  assert.strictEqual(message.data.type, dartConst(pushSource, "message"));
});

check("the chat id is channel-prefixed, so the tap opens the channel", () => {
  const message = buildPostMessage(CHANNEL_DOC, "chan-1", POST_IMAGE);
  assert.strictEqual(message.data.chatId, "channel:chan-1");
});

check("the title falls back to a usable name", () => {
  const message = buildPostMessage({}, "chan-1", {text: "hi"});
  assert.strictEqual(message.data.title, "Channel");
  assert.strictEqual(message.notification.title, "Channel");
  assert.strictEqual(message.notification.body, "hi");
});

check("the notification is tagged per channel and uses the groups channel", () => {
  const message = buildPostMessage(CHANNEL_DOC, "chan-abc", POST_IMAGE);
  assert.strictEqual(message.android.notification.tag, "channel_chan-abc");
  assert.strictEqual(message.android.notification.channel_id, CHANNEL_CHANNEL);
  // A post is not time-critical the way a ring is: normal priority batches
  // instead of waking the radio immediately.
  assert.strictEqual(message.android.priority, "normal");
});

console.log("\n" + checks + " checks passed.");
