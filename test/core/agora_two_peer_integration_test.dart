@Tags(<String>['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/config/app_secrets.dart';
import 'package:imo_live/core/services/agora_call_service.dart';
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

/// Drives **two peers independently** against the live token server.
///
/// The unit tests prove the derivation is symmetric and the uids differ, and
/// `agora_token_client_test.dart` proves the client parses a token. Neither
/// proves the thing that actually breaks calls: that two devices, each running
/// only its own half of the logic, end up in the *same* channel with *different*
/// uids and tokens the server accepts for exactly that pair.
///
/// That is the failure the caller cannot see. A channel mismatch or a uid
/// collision produces two clients that join successfully and simply never hear
/// each other — no error, no log, just silence. So this test asserts the
/// agreement explicitly, against the real Worker.
///
/// Tagged `integration` and skipped by default. Run it explicitly with
/// `--run-skipped` (see `_liveSkip` above for why `--exclude-tags` cannot
/// express this):
///
/// ```sh
/// ./run_flutter.sh test test/core/agora_two_peer_integration_test.dart \
///     --run-skipped
/// ```
void main() {
  group('two peers against the live Worker', skip: _liveSkip, () {
    late AgoraTokenClient client;

    setUp(() {
      client = AgoraTokenClient(
        baseUrl: AppSecrets.agoraTokenServerUrl,
        timeout: const Duration(seconds: 20),
      );
    });

    test('both sides derive the same channel and different uids', () async {
      // Two realistic account ids. The order matters: the caller thinks of the
      // pair as (self, peer) and the callee as (self, peer) with the arguments
      // the other way round, which is exactly where a naive derivation breaks.
      const String alice = 'alice_2f9c41ab';
      const String bob = 'bob_7d3e08fa';

      final int aliceUid = AgoraCallService.uidFor(alice);
      final int bobUid = AgoraCallService.uidFor(bob);

      expect(
        aliceUid,
        isNot(bobUid),
        reason: 'a shared uid makes Agora kick the first peer out of the channel',
      );
      expect(aliceUid, isNot(0));
      expect(bobUid, isNot(0));

      final String aliceChannel = AgoraCallService.channelIdFor(alice, bob);
      final String bobChannel = AgoraCallService.channelIdFor(bob, alice);

      expect(
        aliceChannel,
        bobChannel,
        reason: 'the two peers must land in one channel without exchanging it',
      );
      expect(aliceChannel.length, lessThanOrEqualTo(64));

      // Now the part only a real server can answer.
      final TokenResult aliceToken = await client.fetch(
        channelName: aliceChannel,
        uid: aliceUid,
      );
      final TokenResult bobToken = await client.fetch(
        channelName: bobChannel,
        uid: bobUid,
      );

      expect(
        aliceToken.isSuccess,
        isTrue,
        reason: 'caller got no token: ${aliceToken.failure}',
      );
      expect(
        bobToken.isSuccess,
        isTrue,
        reason: 'callee got no token: ${bobToken.failure}',
      );

      expect(
        aliceToken.token,
        isNot(bobToken.token),
        reason: 'two uids must not mint the same token',
      );

      // A token is bound to one (channel, uid) pair. Decode the body and check
      // the pair is actually in there — a token for the wrong channel or the
      // wrong uid is accepted at mint time and rejected at join time.
      for (final (String who, String? token, int uid) in <(String, String?, int)>[
        ('caller', aliceToken.token, aliceUid),
        ('callee', bobToken.token, bobUid),
      ]) {
        final List<int> body = _tokenBody(token!);
        expect(
          _contains(body, aliceChannel),
          isTrue,
          reason: '$who token does not embed the shared channel',
        );
        expect(
          _contains(body, '$uid'),
          isTrue,
          reason: '$who token does not embed its own uid ($uid)',
        );
      }

      // ignore: avoid_print
      print(
        'TWO PEERS OK: channel=$aliceChannel '
        'uids=$aliceUid/$bobUid '
        'tokens=${aliceToken.token!.length}/${bobToken.token!.length} chars',
      );
    });

    test('a token minted for one channel does not name another', () async {
      const String channelA = 'imo_two_peer_probe_alpha';
      const String channelB = 'imo_two_peer_probe_beta';
      final int uid = AgoraCallService.uidFor('probe_account');

      final TokenResult a = await client.fetch(channelName: channelA, uid: uid);
      expect(a.isSuccess, isTrue, reason: '${a.failure}');

      final List<int> body = _tokenBody(a.token!);
      expect(_contains(body, channelA), isTrue);
      expect(
        _contains(body, channelB),
        isFalse,
        reason: 'the token must be bound to the channel it was minted for',
      );
    });
  });
}

/// The AccessToken2 body, decoded.
///
/// Strips the 3-character version prefix (`007`) — the body re-states the
/// version as a packed string, so the prefix is not part of the base64.
List<int> _tokenBody(String token) {
  final String body = token.substring(3);
  final String padded =
      body.replaceAll('-', '+').replaceAll('_', '/') +
          '=' * ((4 - body.length % 4) % 4);
  return base64.decode(padded);
}

/// True when [needle] appears as UTF-8 inside [haystack].
///
/// The packed strings in the body are length-prefixed but not delimited, so a
/// substring search is the right test: it proves the value was written into the
/// signed bytes.
bool _contains(List<int> haystack, String needle) {
  final List<int> n = utf8.encode(needle);
  if (n.isEmpty || n.length > haystack.length) return false;
  for (int i = 0; i + n.length <= haystack.length; i++) {
    bool match = true;
    for (int j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
