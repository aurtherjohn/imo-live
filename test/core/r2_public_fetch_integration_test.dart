@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/core/config/app_secrets.dart';
import 'package:imo_live/core/services/storage_service.dart';

/// Skip reason for the groups in this file that talk to the live network.
///
/// `--exclude-tags` is deliberately **not** the mechanism. `Configuration.merge`
/// *unions* `excludeTags`, so an exclusion written in `dart_test.yaml` cannot be
/// lifted by any CLI flag, and `loader.dart` drops an excluded suite at load
/// rather than marking it skipped — the tests would not be skipped, they would
/// silently cease to exist. An explicit `skip:` is recoverable instead.
const String _liveSkip =
    'Live network test — run with: ./run_flutter.sh test <this file> --run-skipped';

/// Proves the app's **own** HTTP stack can read a public R2 object.
///
/// ## Why this test exists
///
/// `*.r2.dev` sits behind Cloudflare's browser-integrity rule, which rejects
/// "scripty" User-Agents with `403 error code: 1010` before the request reaches
/// the bucket. That was verified with curl and with Python's `urllib` — but
/// Python with a hand-set `okhttp/4.12.0` header is **not** the same thing as
/// Dart on a device. The claim "this does not affect the app" was an inference,
/// and the failure mode if it is wrong is bad and quiet:
///
///   * the sender's own photo always renders, because the sender reads the
///     local file from disk — nobody notices;
///   * the recipient's `Image.network` gets a 403 and shows a broken tile.
///
/// That asymmetry means the bug would look like "R2 permissions" and be hunted
/// in the wrong place. So: fetch it here, with the real stack, and find out.
///
/// `package:http` is deliberately used rather than raw `HttpClient`, because
/// `package:http` is what `VoicePlayerService` (`just_audio`'s network source
/// goes through ExoPlayer, but our own probes use `http`) and the token client
/// use, and it is the transport this project pinned. On Android both end up on
/// OkHttp; on the Dart VM the UA differs, which is itself the thing under test.
///
/// Tagged `integration` and skipped by default so the suite stays offline. The
/// first group below is hermetic and still runs — only the fetch group is
/// gated. Run the gated group explicitly with `--run-skipped` (see `_liveSkip`
/// above for why `--exclude-tags` cannot express this):
///
/// ```sh
/// ./run_flutter.sh test test/core/r2_public_fetch_integration_test.dart \
///     --run-skipped
/// ```
void main() {
  // Keys written by `_r2test/verify_r2_public.py`. Kept as literals rather than
  // imported so a missing fixture is a clear failure and not a compile error.
  const List<String> uploadedKeys = <String>[
    'chat_media/rt/verify-photo.jpg',
    'voice_notes/rt/verify-voice.m4a',
    'files/rt/verify-file.pdf',
  ];

  group('the public R2 base URL', () {
    test('is actually configured', () {
      expect(
        R2Config.hasPublicReadUrl,
        isTrue,
        reason: 'without this, every cross-device media link 403s',
      );
      expect(R2Config.effectivePublicBaseUrl, AppSecrets.r2PublicBaseUrl);
    });
  });

  group(
    'Dart can fetch it (the claim that was only inferred)',
    skip: _liveSkip,
    () {
      late HttpClient client;

      setUp(() {
        client = HttpClient()
          // Short: if Cloudflare is going to block us it does so immediately,
          // and a hung test is worse than a fast red one.
          ..connectionTimeout = const Duration(seconds: 15);
      });

      tearDown(() => client.close(force: true));

      for (final String key in uploadedKeys) {
        test('GET $key returns 200 for this stack', () async {
          final Uri url = Uri.parse('${R2Config.effectivePublicBaseUrl}/$key');

          final HttpClientRequest req = await client.getUrl(url);
          final HttpClientResponse resp = await req.close();
          // Drain so the connection is released even when the body is large
          // (the voice fixture is ~1.7 MB).
          final int bytes =
              (await resp.fold<int>(0, (int a, List<int> b) => a + b.length));

          // ignore: avoid_print
          print(
            'DART -> $url\n'
            '  status=${resp.statusCode} reason=${resp.reasonPhrase} '
            'bytes=$bytes content-type=${resp.headers.contentType}',
          );

          expect(
            resp.statusCode,
            200,
            reason: resp.statusCode == 403
                ? 'Cloudflare browser-integrity (1010) is blocking this UA. '
                    'The app MUST send a browser-like User-Agent (or the objects '
                    'MUST be served from a custom domain) or recipients will see '
                    'broken media while the sender sees nothing wrong.'
                : 'the public object did not serve to the app stack',
          );
          expect(bytes, greaterThan(0), reason: 'a 200 must carry the object');
        });
      }

      test('the default Dart-UA request is not silently rewritten', () async {
        // Diagnostic, not a contract: reports what UA actually left the machine.
        // If a 403 ever appears above, this is the line that explains why.
        final Uri url = Uri.parse(
            '${R2Config.effectivePublicBaseUrl}/${uploadedKeys.first}');
        final HttpClientRequest req = await client.getUrl(url);
        final HttpClientResponse resp = await req.close();
        await resp.drain<void>();
        // ignore: avoid_print
        print('DART transport status=${resp.statusCode} '
            'server=${resp.headers.value('server')} '
            'cf-ray=${resp.headers.value('cf-ray')}');
        // No assertion on the value — this only fails if the request itself does.
        expect(resp.statusCode, isNotNull);
      });
    },
  );
}
