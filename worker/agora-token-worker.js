/**
 * Agora RTC token endpoint — Cloudflare Worker.
 *
 * Implements the AccessToken2 build (version "007") with Web Crypto only:
 * no Node packages, no `Buffer`, no `agora-access-token`.
 *
 * Contract: POST { channelName, uid } -> { token }
 * Requires the AGORA_APP_CERTIFICATE secret to be set on the Worker.
 *
 * ---------------------------------------------------------------------------
 * FIX vs the previous version
 * ---------------------------------------------------------------------------
 * `crypto.subtle.sign()` resolves to an **ArrayBuffer**, not a `Uint8Array`.
 * An ArrayBuffer has no `.length`, so feeding it into `concat()` made the sum
 * `NaN`, `new Uint8Array(NaN)` produced a zero-length buffer, and the first
 * `result.set(...)` threw `RangeError: offset is out of bounds`.
 *
 * Two changes, both in `toBytes()` / `concat()`:
 *   1. `toBytes()` normalises ArrayBuffer | TypedArray | number[] to a Uint8Array,
 *      so the length sum is always numeric.
 *   2. `concat()` sums normalised byte lengths and writes the normalised bytes,
 *      so it can no longer be handed a value without a numeric length.
 */

function toBytes(value) {
  if (value instanceof Uint8Array) return value;
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (Array.isArray(value)) return new Uint8Array(value);
  throw new TypeError('concat: unsupported chunk type: ' + Object.prototype.toString.call(value));
}

function concat(...chunks) {
  const parts = chunks.map(toBytes);
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

function packUint16(v) {
  return new Uint8Array([v & 0xff, (v >>> 8) & 0xff]);
}

function packUint32(v) {
  return new Uint8Array([v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff]);
}

function packString(s) {
  const bytes = new TextEncoder().encode(String(s));
  return concat(packUint16(bytes.length), bytes);
}

function base64UrlEncode(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function hmacSha256(key, message) {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return await crypto.subtle.sign('HMAC', cryptoKey, message);
}

function buildService(type, privileges, expireTs) {
  const parts = [packUint16(type), packUint16(Object.keys(privileges).length)];
  for (const [key, value] of Object.entries(privileges)) {
    parts.push(packUint16(parseInt(key, 10)));
    parts.push(packUint32(value));
  }
  parts.push(packUint32(expireTs));
  return concat(...parts);
}

async function buildToken(appId, appCertificate, channelName, uid, expireTs) {
  const version = '007';
  const salt = Math.floor(Math.random() * 99999999) + 1;
  const ts = Math.floor(Date.now() / 1000);

  const rtcPrivileges = { 1: expireTs, 2: expireTs, 3: expireTs, 4: expireTs };
  const rtcService = buildService(1, rtcPrivileges, expireTs);

  const signingData = concat(
    packString(version),
    packString(appId),
    packString(channelName),
    packString(uid),
    packUint32(salt),
    packUint32(ts),
    packUint16(1),
    rtcService,
  );

  const signingKey = new TextEncoder().encode(appCertificate);
  // NOTE: this resolves to an ArrayBuffer -- concat() now normalises it.
  const signature = await hmacSha256(signingKey, signingData);

  const body = concat(
    packString(version),
    packString(appId),
    packString(channelName),
    packString(uid),
    packUint32(salt),
    packUint32(ts),
    signature,
    packUint16(1),
    rtcService,
  );

  return version + base64UrlEncode(body);
}

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

    const { channelName, uid } = payload ?? {};
    // `uid === undefined` (not `!uid`) so uid 0 / "0" stay valid -- 0 is a legal
    // Agora uid and `!0` would wrongly reject it.
    if (!channelName || uid === undefined || uid === null) {
      return json({ error: 'channelName and uid are required' }, 400);
    }

    const appId = 'ade86a051ed4441b9b4aa00f93d67b7f';
    const appCertificate = env.AGORA_APP_CERTIFICATE;

    if (!appCertificate) {
      return json({ error: 'AGORA_APP_CERTIFICATE is not set' }, 500);
    }

    try {
      const expireTs = Math.floor(Date.now() / 1000) + 3600;
      const token = await buildToken(appId, appCertificate, String(channelName), uid, expireTs);
      return json({ token });
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
