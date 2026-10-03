@Tags(<String>['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/config/app_secrets.dart';
import 'package:imo_live/core/services/agora_token_client.dart';

/// Skip reason for every group in this file — it talks to the live Worker.
///
/// `--exclude-tags` is deliberately **not** the mechanism. `Configuration.merge`
/// *unions* `excludeTags`, so an exclusion written in `dart_test.yaml` cannot be
/// lifted by any CLI flag, and `loader.dart` drops an excluded suite at load
/// rather than marking it skipped — the tests would not be skipped, they would
/// silently cease to exist. An explicit `skip:` is recoverable instead.
const String _liveSkip =
    'Live network test — run with: ./run_flutter.sh test <this file> --run-skipped';

/// Exercises the token client against the **live** Worker.
///
/// The unit tests use a `MockClient`, which proves the request the client
/// *builds* and the responses it *parses*, but not that the real Worker accepts
/// what it sends. This test closes that gap: it is the only thing that would
/// catch a content-type mismatch, a body-encoding difference, a path the Worker
/// does not actually serve, or a server-side crash inside token generation.
///
/// Tagged `integration` and skipped by default, so the normal suite stays
/// offline and deterministic. Run it explicitly with `--run-skipped` (see
/// `_liveSkip` above for why `--exclude-tags` cannot express this):
///
/// ```sh
/// ./run_flutter.sh test test/core/agora_token_integration_test.dart \
///     --run-skipped
/// ```
///
/// ### Why this now demands success
///
/// This test previously accepted *any* transport-level outcome, because the
/// deployed Worker could not mint a token at all — it returned
/// `500 {"error":"offset is out of bounds"}` for every valid request, caused by
/// `crypto.subtle.sign()` resolving to an `ArrayBuffer` (no `.length`) that was
/// fed straight into `concat()`. The fix normalises every chunk to a
/// `Uint8Array` (`worker/agora-token-worker.js`, `toBytes()`).
///
/// That tolerant form was a mistake worth recording: a test that passes whether
/// or not the service works cannot detect a broken service. It stayed green
/// through the entire outage. So it now asserts the contract the Worker
/// actually promises — a `007` AccessToken2 token — and fails loudly if the
/// endpoint regresses.
void main() {
  group('AgoraTokenClient against the live Worker', skip: _liveSkip, () {
    late AgoraTokenClient client;

    setUp(() {
      client = AgoraTokenClient(
        baseUrl: AppSecrets.agoraTokenServerUrl,
        timeout: const Duration(seconds: 20),
      );
    });

    test('mints a well-formed AccessToken2 token', () async {
      final TokenResult result = await client.fetch(
        channelName: 'imo_live_probe_channel',
        uid: 123456789,
      );

      // A regression here means the deployed Worker is broken again. Report the
      // classification rather than a bare `expected true`, so the failure names
      // the cause.
      expect(
        result.isSuccess,
        isTrue,
        reason: 'live Worker did not mint a token: '
            '${result.failure} — ${result.message}',
      );
      expect(result.failure, isNull);

      final String token = result.token!;
      expect(token, isNotEmpty);
      // AccessToken2 tokens are version-prefixed. A `006` or a non-prefixed
      // string would mean the Worker changed encoding.
      expect(token, startsWith('007'));
      // 3-char version + base64url body; anything tiny is a truncated response.
      expect(token.length, greaterThan(100));

      // ignore: avoid_print
      print('LIVE WORKER OK: minted a ${token.length}-char token');
    });

    test('a channel with awkward characters is still handled cleanly',
        () async {
      final TokenResult result = await client.fetch(
        channelName: 'imo_a-b_c.d/../x',
        uid: 1,
      );
      expect(result.isSuccess, isTrue,
          reason: 'awkward channel rejected: ${result.failure}');
      expect(result.token, startsWith('007'));
    });

    test('an empty channel is rejected locally without hitting the network',
        () async {
      final TokenResult result = await client.fetch(channelName: '', uid: 1);
      expect(result.failure, TokenFailure.badRequest);
    });
  });
}
