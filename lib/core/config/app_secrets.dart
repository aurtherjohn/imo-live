/// Hardcoded credentials for the current **development** build.
///
/// ⚠️ DEVELOPMENT CREDENTIALS ONLY - REVOKE AND REPLACE BEFORE PRODUCTION
/// TODO: Replace with production keys after development is complete.
///
/// ---------------------------------------------------------------------------
/// READ THIS BEFORE SHIPPING
///
/// Everything in this file is a `static const String`, which means it is
/// compiled into `libapp.so` as a literal and can be recovered from a release
/// APK with nothing more than `strings`. There is no obfuscation that changes
/// that: a client-side secret is a public secret.
///
/// The blast radius of each group is not the same, so they are documented
/// separately below. In short:
///
///   * the R2 **secret access key** grants read/write/delete on the bucket —
///     anyone holding it can wipe every user's media;
///   * the STUN/TURN values are **not secrets at all**. Every client that
///     places a call is handed them, so they are here because this file is the
///     one place a URL is allowed to live — not because they need protecting.
///     What they do need is *replacing*: the TURN relay below is a public,
///     rate-limited test service.
///
/// These are safe **only** because they are temporary, unshipped, and scheduled
/// for revocation. Revoke them in the Cloudflare and Agora dashboards, do not
/// distribute this APK, and do not `git init` this directory while the file is
/// populated. The production path is the `--dart-define` override documented in
/// [R2Config] — no code change is needed to move to it.
/// ---------------------------------------------------------------------------
class AppSecrets {
  const AppSecrets._();

  // ==========================================================================
  // Cloudflare R2 Credentials
  // ==========================================================================
  // ⚠️ DEVELOPMENT CREDENTIALS ONLY - REVOKE AND REPLACE BEFORE PRODUCTION
  // TODO: Replace with production keys after development is complete.

  /// R2 account id — the `<ACCOUNT_ID>` in the S3 endpoint host.
  static const String r2AccountId = '71305171ebce194093dd5cf520f23190';

  /// S3 access key id, from R2 → Manage API Tokens.
  static const String r2AccessKeyId = '6f3055f9aeb2b82c3731792f319781d7';

  /// S3 secret access key.
  ///
  /// Grants Object Read & Write on the bucket. Treat as a full compromise of
  /// the bucket's contents the moment this APK leaves your hands.
  static const String r2SecretAccessKey =
      'd6aa10be1b1a37901da51d0f6efde46443d43315a5ae3e5431664a6d4a3499bb';

  /// Bucket that holds all app media.
  static const String r2BucketName = 'imo-live-storage';

  /// S3 API endpoint. R2 requires the `auto` region, handled in [R2Config].
  static const String r2EndpointUrl =
      'https://71305171ebce194093dd5cf520f23190.eu.r2.cloudflarestorage.com';

  // NOTE: a `cfat_…` Cloudflare **account** API token was previously recorded
  // here. It has been removed. It was never read by the S3 code path — the S3
  // client authenticates with [r2AccessKeyId] / [r2SecretAccessKey] alone — and
  // an account-scoped token can reach far beyond this one bucket, so it was the
  // widest-scoped value in the file for no benefit. It was also already
  // invalid. Do not re-add a value of this kind.

  /// Public read base URL for the bucket — the prefix used to build every media
  /// link that is stored on a message and rendered by the *other* device.
  ///
  /// This is the bucket's `r2.dev` development URL. It is a **public** value by
  /// construction: anything under it is world-readable, which is exactly what
  /// makes a photo or a voice note render on a recipient's phone without
  /// credentials. It is not a secret, and [R2Config.effectivePublicBaseUrl]
  /// appends `/{objectKey}` to it.
  ///
  /// No trailing slash; one is stripped before the key is appended.
  ///
  /// ⚠️ `r2.dev` URLs are rate-limited and not intended for production traffic —
  /// bind a custom domain to the bucket and pass
  /// `--dart-define=R2_PUBLIC_BASE_URL=…` before launch.
  static const String r2PublicBaseUrl =
      'https://pub-215c584aa24f47d792388de37c21b079.r2.dev';

  // ==========================================================================
  // STUN / TURN (WebRTC call transport)
  // ==========================================================================
  //
  // A call needs two things from the network: a way for each phone to learn its
  // own public address (STUN) and, when the two phones cannot reach each other
  // directly, a relay that carries the media for them (TURN).
  //
  //   * STUN is enough for two peers on the same network or behind friendly
  //     NAT. It is a best-effort lookup with no SLA, and it sees the IP address
  //     of every user who calls.
  //   * TURN is what makes a call work on *mobile data*. Symmetric NAT and
  //     carrier-grade NAT are the normal case on a phone, and they cannot be
  //     punched through — without a relay the two sides negotiate and then
  //     never connect. This is the exact failure the Agora swap was originally
  //     made to work around, so the relay is not optional.
  //
  // Both are read by `WebRtcIce` in `webrtc_call_service.dart`, which prefers a
  // `--dart-define` and falls back to these values — so pointing the app at a
  // Cloudflare TURN deployment is a build-flag change, not a code change:
  //
  //   flutter build apk --release --split-per-abi \
  //     --dart-define=CALLS_TURN_URL=turn:turn.cloudflare.example:3478 \
  //     --dart-define=CALLS_TURN_USERNAME=... \
  //     --dart-define=CALLS_TURN_PASSWORD=...

  /// STUN. Google's public server, free and widely used.
  static const String callStunUrl = 'stun:stun.l.google.com:19302';

  /// TURN relay used while Cloudflare credentials are pending.
  ///
  /// ⚠️ **Open Relay (Metered) is a shared public test service.** The
  /// credentials below are published for anyone to use, which is precisely why
  /// they are acceptable in a development build and unacceptable in a shipped
  /// one — and why the service is rate-limited and may refuse a call outright.
  /// Replace all three values before release.
  static const String callTurnUrl = 'turn:openrelay.metered.ca:80';

  /// TURN username for [callTurnUrl]. Public by design — see the warning above.
  static const String callTurnUsername = 'openrelayproject';

  /// TURN password for [callTurnUrl]. Public by design — see the warning above.
  static const String callTurnPassword = 'openrelayproject';

  // ==========================================================================
  // Agora Credentials (Voice & Video Call) — RETAINED, NOT IN USE
  // ==========================================================================
  //
  // ⚠️ The project moved off Agora on 2026-09-29: `callServiceProvider` selects
  // `WebRtcCallService` and nothing in the app reaches an Agora code path any
  // more. `agora_call_service.dart` is kept on disk but is not wired in.
  //
  // These values therefore exist only so that file still compiles. If the file
  // is deleted, delete this section and the `agora_rtc_engine` dependency with
  // it — that dependency is a large native library that ships in every APK.

  /// Agora App ID. This one is genuinely public — it ships in every Agora
  /// client by design and identifies the project.
  static const String agoraAppId = 'ade86a051ed4441b9b4aa00f93d67b7f';

  /// The Agora App Certificate is deliberately **not** here.
  ///
  /// It is a server-side secret: RTC tokens are minted by [agoraTokenServerUrl],
  /// which holds the certificate in a Cloudflare Worker environment variable.
  /// Nothing in the app ever read this constant — and a client-side copy is one
  /// `import` away from being compiled into every APK, after which anyone who
  /// unpacks the file could sign tokens for any channel on the account. That is
  /// the whole reason the token endpoint exists.
  ///
  /// Removed 2026-09-29. Do not re-add it; the value belongs in the Worker's
  /// secret store and in the Agora console, not in the source tree.

  /// Agora token server — a Cloudflare Worker that mints RTC tokens.
  ///
  /// The client sends `POST {channelName, uid}` and receives
  /// `{"token": "<agora_token>"}`. The App Certificate never leaves the Worker,
  /// so a token is only obtainable by a caller who knows a channel name and a
  /// uid — never by someone who merely unpacked the APK.
  ///
  /// See [AgoraCallConfig.tokenEndpoint] for how it is consumed.
  static const String agoraTokenServerUrl =
      'https://agora-token.akazadfb89.workers.dev';

  // ==========================================================================
  // OneSignal (push delivery)
  // ==========================================================================
  //
  // Both values are public by construction and both are expected in the APK:
  //
  //   * the App ID identifies the OneSignal app to the SDK. It ships in every
  //     OneSignal client by design, exactly like an Agora App ID;
  //   * the Worker URL is a public HTTPS endpoint.
  //
  // The **REST API key** is the secret, and it is deliberately *not* here. It
  // lives in the Worker's environment (`wrangler secret put ONESIGNAL_REST_KEY`)
  // so that sending is only possible through the Worker. If it were a constant
  // in this file, anyone who unpacked the APK could push to every user.

  /// OneSignal App ID for the `imo-live` app.
  static const String oneSignalAppId = '30f1b1ec-ec2a-4787-8e88-d483e05c6e82';

  /// Cloudflare Worker that fans a send request out to OneSignal.
  ///
  /// The client `POST`s `{receiverUid, title, body, data}`; the Worker resolves
  /// the uid to a player id, attaches the REST key and calls OneSignal. See
  /// [OneSignalService.sendNotificationToUser].
  static const String oneSignalWorkerUrl =
      'https://send-notification.akazadfb89.workers.dev';
}
