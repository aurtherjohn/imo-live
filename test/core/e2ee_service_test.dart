import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:imo_live/core/services/e2ee_service.dart';

/// In-memory stand-in for the platform keystore.
///
/// Each instance is its own device: `E2eeService` uses fixed storage keys, so
/// two participants must not share one store or the second would overwrite the
/// first's identity.
class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// Builds a participant with a published identity.
///
/// `ensureIdentity` also tries to publish to Firestore, which has no plugin in
/// a unit test — that failure is caught and logged, so it does not need stubbing.
Future<E2eeService> _participant(String uid, int seed) async {
  final E2eeService service = E2eeService(
    secureStorage: _MemorySecureStorage(),
    random: Random(seed),
  );
  await service.ensureIdentity(uid);
  return service;
}

/// Deterministic byte string of [length] bytes.
Uint8List _bytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (int i) => i));

/// A structurally valid envelope, for the "what if one field is wrong" tests.
E2eeEnvelope _envelopeFixture() => E2eeEnvelope(
      version: E2eeEnvelope.currentVersion,
      senderPublicKey: _bytes(32),
      nonce: _bytes(12),
      cipherText: Uint8List.fromList(<int>[1]),
      mac: _bytes(16),
    );

void main() {
  group('E2eeEnvelope', () {
    test('round-trips through JSON', () {
      final E2eeEnvelope envelope = E2eeEnvelope(
        version: E2eeEnvelope.currentVersion,
        senderPublicKey: _bytes(32),
        nonce: _bytes(12),
        cipherText: Uint8List.fromList(<int>[1, 2, 3]),
        mac: _bytes(16),
      );

      final E2eeEnvelope? decoded = E2eeEnvelope.tryDecode(envelope.encode());

      expect(decoded, isNotNull);
      expect(decoded!.cipherText, envelope.cipherText);
      expect(decoded.nonce, envelope.nonce);
      expect(decoded.mac, envelope.mac);
      expect(decoded.senderPublicKey, envelope.senderPublicKey);
    });

    test('rejects a plaintext body instead of throwing', () {
      expect(E2eeEnvelope.tryDecode('hello there'), isNull);
      expect(E2eeEnvelope.tryDecode(''), isNull);
      expect(E2eeEnvelope.tryDecode('{not json'), isNull);
      expect(E2eeEnvelope.tryDecode('[]'), isNull);
    });

    test('rejects an unknown algorithm or version', () {
      final Map<String, Object?> good = _envelopeFixture().toJson();

      expect(
        E2eeEnvelope.tryDecode(
          jsonEncode(<String, Object?>{...good, 'alg': 'rot13'}),
        ),
        isNull,
      );
      expect(
        E2eeEnvelope.tryDecode(
          jsonEncode(<String, Object?>{...good, 'v': 99}),
        ),
        isNull,
      );
    });

    test('rejects a wrong-length key or nonce', () {
      final Map<String, Object?> good = _envelopeFixture().toJson();

      expect(
        E2eeEnvelope.tryDecode(
          jsonEncode(<String, Object?>{...good, 'sk': base64Url.encode(<int>[1, 2])}),
        ),
        isNull,
      );
      expect(
        E2eeEnvelope.tryDecode(
          jsonEncode(<String, Object?>{...good, 'n': base64Url.encode(<int>[1, 2])}),
        ),
        isNull,
      );
    });
  });

  group('E2eeService', () {
    test('generates and republishes an identity', () async {
      final E2eeService alice = await _participant('alice', 1);

      expect(alice.isReady, isTrue);
      expect(alice.publicKeyBytes, hasLength(32));
    });

    test('a second call reuses the stored key pair', () async {
      final _MemorySecureStorage store = _MemorySecureStorage();
      final E2eeService service =
          E2eeService(secureStorage: store, random: Random(7));

      await service.ensureIdentity('alice');
      final String? first = service.publicKeyBase64;

      await service.ensureIdentity('alice');

      expect(service.publicKeyBase64, first,
          reason: 'a new identity would make old messages unreadable');
    });

    test('seals and opens a message between two devices', () async {
      final E2eeService alice = await _participant('alice', 1);
      final E2eeService bob = await _participant('bob', 2);
      alice.seedPeerKey('bob', bob.publicKeyBytes!);
      bob.seedPeerKey('alice', alice.publicKeyBytes!);

      const String body = 'Meet me at the usual place at 8.';
      final String? sealed = await alice.seal('bob', body);

      expect(sealed, isNotNull);
      expect(sealed, isNot(contains(body)),
          reason: 'the ciphertext must not contain the plaintext');

      expect(await bob.open(sealed!), body);
    });

    test('the ciphertext never repeats for the same message', () async {
      final E2eeService alice = await _participant('alice', 1);
      final E2eeService bob = await _participant('bob', 2);
      alice.seedPeerKey('bob', bob.publicKeyBytes!);

      final String? first = await alice.seal('bob', 'same message');
      final String? second = await alice.seal('bob', 'same message');

      expect(first, isNot(second),
          reason: 'a reused nonce under the same key breaks AES-GCM');
    });

    test('a tampered payload is rejected, not decrypted', () async {
      final E2eeService alice = await _participant('alice', 1);
      final E2eeService bob = await _participant('bob', 2);
      alice.seedPeerKey('bob', bob.publicKeyBytes!);
      bob.seedPeerKey('alice', alice.publicKeyBytes!);

      final String sealed = (await alice.seal('bob', 'transfer 500'))!;
      final Map<String, dynamic> tampered =
          jsonDecode(sealed) as Map<String, dynamic>;
      final List<int> cipher = base64Url.decode(tampered['c'] as String);
      cipher[0] ^= 0xFF;
      tampered['c'] = base64Url.encode(cipher);

      expect(await bob.open(jsonEncode(tampered)), isNull,
          reason: 'AES-GCM must detect the modification via its MAC');
    });

    test('a third party cannot open the message', () async {
      final E2eeService alice = await _participant('alice', 1);
      final E2eeService bob = await _participant('bob', 2);
      final E2eeService eve = await _participant('eve', 3);
      alice.seedPeerKey('bob', bob.publicKeyBytes!);

      final String sealed = (await alice.seal('bob', 'for bob only'))!;

      expect(await eve.open(sealed), isNull);
    });

    test('does not seal without a published peer key', () async {
      final E2eeService alice = await _participant('alice', 1);

      expect(await alice.seal('bob', 'hello'), isNull,
          reason: 'failing open to plaintext beats dropping the message');
    });

    test('does not seal an empty body or a message to itself', () async {
      final E2eeService alice = await _participant('alice', 1);
      alice.seedPeerKey('bob', alice.publicKeyBytes!);

      expect(await alice.seal('bob', ''), isNull);
      expect(await alice.seal('alice', 'note to self'), isNull);
    });

    test('reset drops the in-memory identity', () async {
      final E2eeService alice = await _participant('alice', 1);
      alice.reset();

      expect(alice.isReady, isFalse);
      expect(await alice.seal('bob', 'hello'), isNull);
    });
  });
}
