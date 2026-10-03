import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imo_live/core/config/app_secrets.dart';
import 'package:imo_live/core/services/agora_call_service.dart';
import 'package:imo_live/core/services/agora_token_client.dart';

/// The Agora token server is now the only way this app obtains an RTC token, so
/// these tests pin the wire contract and every way the request can fail. A
/// regression here is silent in production — the join either never happens or,
/// worse, happens with an empty token and gets dropped by Agora a second later.
void main() {
  group('AgoraCallConfig', () {
    test('reads the token server from AppSecrets by default', () {
      const AgoraCallConfig config = AgoraCallConfig();
      expect(config.tokenEndpoint, AppSecrets.agoraTokenServerUrl);
      expect(config.tokenEndpoint, isNotEmpty);
    });

    test('a build with no build-time token still has a token source', () {
      const AgoraCallConfig config = AgoraCallConfig();
      // The whole point of the change: an empty AGORA_TOKEN is no longer a
      // broken configuration, because the server mints one per call.
      expect(config.token, isEmpty);
      expect(config.hasTokenSource, isTrue);
    });

    test('an empty endpoint means no client is built', () {
      const AgoraCallConfig config = AgoraCallConfig(tokenEndpoint: '');
      expect(config.tokenClient, isNull);
      expect(config.hasTokenSource, isFalse);
    });

    test('isConfigured tracks the App ID, not the token source', () {
      const AgoraCallConfig config = AgoraCallConfig();
      expect(config.isConfigured, isTrue);
      expect(
        const AgoraCallConfig(appId: '  ').isConfigured,
        isFalse,
        reason: 'a blank App ID cannot join a channel at all',
      );
    });
  });

  group('AgoraTokenClient — success', () {
    test('POSTs channelName and uid, and returns the token', () async {
      Uri? seenUri;
      Map<String, dynamic>? seenBody;

      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        client: MockClient((http.Request request) async {
          seenUri = request.url;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], contains('application/json'));
          return http.Response('{"token":"007eJxTAAAA"}', 200);
        }),
      );

      final TokenResult result =
          await client.fetch(channelName: 'imo_a_b', uid: 12345);

      expect(result.isSuccess, isTrue);
      expect(result.token, '007eJxTAAAA');
      expect(result.failure, isNull);
      expect(seenUri.toString(), 'https://token.example.workers.dev');
      expect(seenBody!['channelName'], 'imo_a_b');
      // The contract sends uid as a STRING even though it is numeric.
      expect(seenBody!['uid'], '12345');
      expect(seenBody!['uid'], isA<String>());
    });

    test('trims surrounding whitespace off the returned token', () async {
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        client: MockClient(
          (http.Request request) async =>
              http.Response('{"token":"  abc123  "}', 200),
        ),
      );
      final TokenResult result =
          await client.fetch(channelName: 'c', uid: 1);
      expect(result.token, 'abc123');
    });
  });

  group('AgoraTokenClient — failures', () {
    Future<TokenFailure?> failureOf(http.Response response) async {
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        client: MockClient((_) async => response),
      );
      final TokenResult result = await client.fetch(channelName: 'c', uid: 1);
      expect(result.isSuccess, isFalse);
      expect(result.token, isNull);
      return result.failure;
    }

    test('an unconfigured base URL never sends a request', () async {
      var called = false;
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: '   ',
        client: MockClient((_) async {
          called = true;
          return http.Response('{"token":"x"}', 200);
        }),
      );
      final TokenResult result = await client.fetch(channelName: 'c', uid: 1);
      expect(result.failure, TokenFailure.notConfigured);
      expect(called, isFalse);
    });

    test('an empty channel name is a bad request, not a network call', () async {
      var called = false;
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        client: MockClient((_) async {
          called = true;
          return http.Response('{"token":"x"}', 200);
        }),
      );
      final TokenResult result = await client.fetch(channelName: '', uid: 1);
      expect(result.failure, TokenFailure.badRequest);
      expect(called, isFalse);
    });

    test('a 500 is reported as an http status failure', () async {
      // The live worker returns exactly this shape when it is misconfigured.
      expect(
        await failureOf(http.Response('{"error":"offset is out of bounds"}', 500)),
        TokenFailure.httpStatus,
      );
    });

    test('a 403 is reported as an http status failure', () async {
      expect(
        await failureOf(http.Response('forbidden', 403)),
        TokenFailure.httpStatus,
      );
    });

    test('a 200 with an empty body is a malformed response', () async {
      expect(
        await failureOf(http.Response('', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a 200 with non-JSON is a malformed response', () async {
      expect(
        await failureOf(http.Response('<html>nope</html>', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a 200 with a JSON array is a malformed response', () async {
      expect(
        await failureOf(http.Response('[1,2,3]', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a 200 with no token field is a malformed response', () async {
      expect(
        await failureOf(http.Response('{"ok":true}', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a 200 with a blank token is a malformed response', () async {
      expect(
        await failureOf(http.Response('{"token":"   "}', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a non-string token is a malformed response', () async {
      expect(
        await failureOf(http.Response('{"token":12345}', 200)),
        TokenFailure.malformedResponse,
      );
    });

    test('a thrown transport error is a network failure, not a crash', () async {
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        client: MockClient((_) async => throw const _Boom()),
      );
      final TokenResult result = await client.fetch(channelName: 'c', uid: 1);
      expect(result.failure, TokenFailure.network);
    });

    test('a hung server times out rather than hanging the call', () async {
      final AgoraTokenClient client = AgoraTokenClient(
        baseUrl: 'https://token.example.workers.dev',
        timeout: const Duration(milliseconds: 40),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('{"token":"x"}', 200);
        }),
      );
      final TokenResult result = await client.fetch(channelName: 'c', uid: 1);
      expect(result.failure, TokenFailure.timeout);
    });

    test('every failure carries something to show a user', () {
      for (final TokenFailure failure in TokenFailure.values) {
        final TokenResult result = TokenResult.failure(failure);
        expect(
          result.message,
          isNotNull,
          reason: '$failure must explain itself to the user',
        );
        expect(result.message, isNotEmpty);
      }
      expect(const TokenResult.success('t').message, isNull);
    });
  });

  group('AppSecrets — no hardcoded URLs outside the config file', () {
    test('both new endpoints are https and fully qualified', () {
      expect(AppSecrets.agoraTokenServerUrl, startsWith('https://'));
      expect(AppSecrets.r2PublicBaseUrl, startsWith('https://'));
      // A trailing slash would produce `//` when the object key is appended.
      expect(AppSecrets.agoraTokenServerUrl, isNot(endsWith('/')));
      expect(AppSecrets.r2PublicBaseUrl, isNot(endsWith('/')));
    });

    test('the r2.dev base URL carries no path prefix', () {
      final Uri uri = Uri.parse(AppSecrets.r2PublicBaseUrl);
      expect(uri.path, anyOf('', '/'));
      expect(uri.query, isEmpty);
    });
  });
}

/// A transport error that is neither an HTTP status nor a timeout.
class _Boom implements Exception {
  const _Boom();
}
