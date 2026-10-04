/**
 * OneSignal push relay — Cloudflare Worker.
 *
 * Contract: POST { receiverUid, title, body?, data? } -> OneSignal's own response
 * Requires the ONESIGNAL_REST_API_KEY secret to be set on the Worker. The REST key
 * must never be in the APK, which is the entire reason this Worker exists.
 *
 * ---------------------------------------------------------------------------
 * STATUS: reference implementation, not known to match the deployed Worker
 * ---------------------------------------------------------------------------
 * The Worker at send-notification.akazadfb89.workers.dev could not be read (no
 * Cloudflare credentials on the build host), so it was probed instead. What the
 * probe established:
 *
 *   POST {}                        -> 400 {"error":"receiverUid and title are required"}
 *   POST {receiverUid}             -> 400 {"error":"receiverUid and title are required"}
 *   POST {receiverUid,title,body}  -> 200 {"id":"","errors":["All included players are not subscribed"]}
 *   GET / OPTIONS                  -> 405
 *
 * So: `receiverUid` and `title` are required, `body` is optional, the body is
 * JSON, and the OneSignal response is passed through verbatim. The deployed
 * Worker already satisfies the app's call shape, so this file is NOT a required
 * fix — it exists to (a) version-control the contract, and (b) carry the two
 * changes below, which the deployed Worker may or may not already have.
 *
 * ---------------------------------------------------------------------------
 * CHANGE 1 — address the user by external_id, not by a stored player id
 * ---------------------------------------------------------------------------
 * `OneSignal.login(uid)` sets the subscription's external_id. Targeting that is
 * stateless and always current.
 *
 * The alternative — reading `users/{uid}.oneSignalPlayerId` out of Firestore and
 * sending `include_player_ids` — has a race the app cannot close: on a fresh
 * install `OneSignal.User.pushSubscription.id` is still null when login runs, so
 * the field can be missing or stale, and the push then fails **silently** (the
 * caller is fire-and-forget, and OneSignal reports it as "not subscribed" rather
 * than an error). external_id has no such window.
 *
 * ---------------------------------------------------------------------------
 * CHANGE 2 — set android_channel_id, so messages and calls are separately muteable
 * ---------------------------------------------------------------------------
 * OneSignal renders a *background* push itself, on the channel named by the
 * payload's `android_channel_id`. Omit it and every notification lands on
 * OneSignal's own default channel, where the user can no longer mute messages
 * while keeping calls audible — the app's `imo_messages` / `imo_calls` channels
 * are then only ever used for foreground pushes.
 *
 * This cannot be fixed app-side: the channel of a background push is chosen by
 * the sender. The channel ids here must match `NotificationService` in the app.
 */

const ONESIGNAL_APP_ID = '30f1b1ec-ec2a-4787-8e88-d483e05c6e82';
const ONESIGNAL_ENDPOINT = 'https://api.onesignal.com/notifications';

/**
 * `data.type` -> Android notification channel id.
 *
 * Mirrors the app's `PushKind`: `chat` is an ordinary message (the spelling the
 * app sends), `message` is accepted as its own alias, `call` is a call. Anything
 * unrecognised gets no channel id at all and falls back to OneSignal's default,
 * which is the right degradation — a new server-side category still delivers.
 */
const CHANNEL_BY_TYPE = {
  chat: 'imo_messages',
  message: 'imo_messages',
  call: 'imo_calls',
};

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: 'invalid JSON body' }, 400);
    }

    const receiverUid = String(payload?.receiverUid ?? '').trim();
    const title = String(payload?.title ?? '').trim();
    if (!receiverUid || !title) {
      return json({ error: 'receiverUid and title are required' }, 400);
    }

    const body = String(payload?.body ?? '').trim();
    const data =
      payload?.data && typeof payload.data === 'object' && !Array.isArray(payload.data)
        ? payload.data
        : {};
    const channel = CHANNEL_BY_TYPE[String(data.type ?? '').toLowerCase()];

    const restKey = env.ONESIGNAL_REST_API_KEY;
    if (!restKey) {
      return json({ error: 'ONESIGNAL_REST_API_KEY is not set' }, 500);
    }

    // OneSignal rejects a send with no `contents`, so an empty body falls back to
    // the title rather than producing a 400 the caller never sees.
    const notification = {
      app_id: env.ONESIGNAL_APP_ID ?? ONESIGNAL_APP_ID,
      include_aliases: { external_id: [receiverUid] },
      target_channel: 'push',
      headings: { en: title },
      contents: { en: body || title },
      data,
      ...(channel ? { android_channel_id: channel } : {}),
    };

    try {
      const res = await fetch(ONESIGNAL_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Key ${restKey}`,
        },
        body: JSON.stringify(notification),
      });
      // Pass OneSignal's response through unchanged: the app treats only 200/201
      // as success, and the body is what makes a failure diagnosable.
      return new Response(await res.text(), {
        status: res.status,
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (e) {
      return json({ error: e && e.message ? e.message : String(e) }, 500);
    }
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
