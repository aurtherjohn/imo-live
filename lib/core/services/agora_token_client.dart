import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Asks a token server for a short-lived Agora RTC token.
///
/// ### Why a server and not the App Certificate
///
/// An Agora channel join is authorised by an RTC token, and a token is *signed*
/// with the App Certificate. If the client signed its own tokens, the
/// certificate would have to ship inside the APK — and anyone who unpacked the
/// file could then mint tokens for any channel on the account. So the
/// certificate stays on the server and this class only ever carries the
/// resulting token.
///
/// ### Wire contract
///
/// ```jsonc
/// // request
/// POST <baseUrl>
/// Content-Type: application/json
/// { "channelName": "imo_<uidA>_<uidB>", "uid": "123456789" }
///
/// // response
/// 200 { "token": "007eJxT..." }
/// ```
///
/// The request body is sent exactly as the directive specifies: both fields are
/// JSON **strings**. `uid` is the numeric Agora uid as a string, because the
/// worker is written to parse it and a JSON number would change the contract.
///
/// ### Failure policy
///
/// [fetch] never throws — it returns a [TokenResult] describing what happened.
/// A call screen must be able to distinguish "the server is briefly
/// unreachable" from "this project is misconfigured", and neither is an
/// exception the UI should have to catch.
class AgoraTokenClient {
  /// [client] is optional and is only used by tests, which inject a mock so a
  /// token request can be exercised without a network. When it is omitted, a
  /// fresh client is created per request and closed afterwards — a shared
  /// client would keep sockets alive for the life of the app for no benefit,
  /// since a token request happens once per call.
  AgoraTokenClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _injectedClient = client;

  /// Token server root, e.g. `https://agora-token.example.workers.dev`.
  final String baseUrl;

  /// How long to wait before treating the server as unavailable.
  ///
  /// Deliberately shorter than [AgoraCallService.ringTimeout]: a join that is
  /// still waiting on a token when the ring gives up is worse than a fast,
  /// honest failure the user can retry.
  final Duration timeout;

  /// A caller-supplied client (tests only), or null to create one per request.
  ///
  /// Named `_injectedClient` rather than `_client` on purpose: `_client =
  /// client` in the initializer list is exactly what `prefer_initializing_formals`
  /// flags, and renaming the field is a real fix rather than a suppression.
  final http.Client? _injectedClient;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Requests a token for [channelName], identifying this peer as [uid].
  Future<TokenResult> fetch({
    required String channelName,
    required int uid,
  }) async {
    final String url = baseUrl.trim();
    if (url.isEmpty) {
      return const TokenResult.failure(TokenFailure.notConfigured);
    }
    if (channelName.trim().isEmpty) {
      return const TokenResult.failure(TokenFailure.badRequest);
    }

    final http.Client client = _injectedClient ?? http.Client();
    try {
      final http.Response response = await client
          .post(
            Uri.parse(url),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            // `uid` is stringified on purpose — see the class docs.
            body: jsonEncode(<String, String>{
              'channelName': channelName,
              'uid': '$uid',
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'Agora token server returned ${response.statusCode}: '
          '${_truncate(response.body)}',
        );
        return TokenResult.failure(TokenFailure.httpStatus);
      }

      return _parse(response.body);
    } on TimeoutException {
      debugPrint('Agora token request timed out after ${timeout.inSeconds}s');
      return const TokenResult.failure(TokenFailure.timeout);
    } on Object catch (error) {
      debugPrint('Agora token request failed: $error');
      return const TokenResult.failure(TokenFailure.network);
    } finally {
      // Only close a client this instance created. An injected client belongs to
      // the caller, which may be reusing it for other requests.
      if (_injectedClient == null) client.close();
    }
  }

  /// Pulls `token` out of the response body.
  ///
  /// A 200 with an unparseable or empty body is a server-side bug, not a
  /// network problem, and is reported as [TokenFailure.malformedResponse] so
  /// the two are not conflated in a bug report.
  static TokenResult _parse(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        debugPrint('Agora token server sent a non-object body');
        return const TokenResult.failure(TokenFailure.malformedResponse);
      }
      final Object? token = decoded['token'];
      if (token is! String || token.trim().isEmpty) {
        debugPrint(
          'Agora token server response carried no token: ${_truncate(body)}',
        );
        return const TokenResult.failure(TokenFailure.malformedResponse);
      }
      return TokenResult.success(token.trim());
    } on FormatException catch (error) {
      debugPrint('Agora token server sent invalid JSON: $error');
      return const TokenResult.failure(TokenFailure.malformedResponse);
    }
  }

  static String _truncate(String value) =>
      value.length <= 200 ? value : '${value.substring(0, 200)}…';
}

/// Why a token request did not produce a token.
///
/// Distinct cases rather than a nullable string, because the message the user
/// should see depends on which one it is: a timeout is worth retrying, a
/// misconfigured server is not.
enum TokenFailure {
  /// No token server URL is configured at all.
  notConfigured,

  /// The channel name was empty — a programming error.
  badRequest,

  /// The device could not reach the server.
  network,

  /// The server accepted the request but did not answer in time.
  timeout,

  /// The server answered with a non-200 status.
  httpStatus,

  /// The server answered 200 with a body that carried no usable token.
  malformedResponse,
}

/// The outcome of [AgoraTokenClient.fetch].
@immutable
class TokenResult {
  const TokenResult.success(this.token)
      : failure = null;

  const TokenResult.failure(TokenFailure this.failure) : token = null;

  /// The minted token, or null on failure.
  final String? token;

  /// Why the request failed, or null on success.
  final TokenFailure? failure;

  bool get isSuccess => token != null;

  /// A sentence to show the user, or null when there is nothing to say.
  String? get message => switch (failure) {
        null => null,
        TokenFailure.notConfigured =>
          'Calls are not configured on this build.',
        TokenFailure.badRequest => 'This call could not be placed.',
        TokenFailure.network =>
          'Could not reach the call server. Check your connection.',
        TokenFailure.timeout => 'The call server did not respond in time.',
        TokenFailure.httpStatus => 'The call server rejected this request.',
        TokenFailure.malformedResponse =>
          'The call server sent an unusable response.',
      };
}
