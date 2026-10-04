import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The sealed form of a message body.
///
/// Stored as JSON in the message's `text` field when `e2ee` is true. Every
/// field is base64url so the document stays a plain string — Firestore has no
/// binary type, and a readable envelope makes a malformed payload obvious in
/// the console instead of a silent decrypt failure.
@immutable
class E2eeEnvelope {
  const E2eeEnvelope({
    required this.version,
    required this.senderPublicKey,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  /// Bumped only if the wire format changes incompatibly.
  static const int currentVersion = 1;

  /// Recorded in the envelope so a future algorithm change is detectable from
  /// the data alone rather than by trying to decrypt and hoping.
  static const String algorithmId = 'X25519+AesGcm256';

  static const String _keyVersion = 'v';
  static const String _keyAlgorithm = 'alg';
  static const String _keySenderKey = 'sk';
  static const String _keyNonce = 'n';
  static const String _keyCipher = 'c';
  static const String _keyMac = 'm';

  final int version;

  /// The sender's X25519 public key at send time.
  ///
  /// Carried inline rather than looked up from `users/{uid}` so a message can
  /// still be read after the sender rotates their key — a lookup would return
  /// the *new* key and derive the wrong shared secret.
  final Uint8List senderPublicKey;

  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  Map<String, Object?> toJson() => <String, Object?>{
        _keyVersion: version,
        _keyAlgorithm: algorithmId,
        _keySenderKey: base64Url.encode(senderPublicKey),
        _keyNonce: base64Url.encode(nonce),
        _keyCipher: base64Url.encode(cipherText),
        _keyMac: base64Url.encode(mac),
      };

  String encode() => jsonEncode(toJson());

  /// Parses a stored envelope, or null when the payload is not one.
  ///
  /// Returns null rather than throwing: an old plaintext message, a message
  /// from a build without E2EE, and a genuinely corrupt payload all have to
  /// degrade to "show what arrived", not crash the chat screen.
  static E2eeEnvelope? tryDecode(String source) {
    if (source.isEmpty || source.codeUnitAt(0) != 0x7B /* '{' */) return null;
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded[_keyAlgorithm] != algorithmId) return null;
      if (decoded[_keyVersion] != currentVersion) return null;

      final Uint8List? senderKey = _decode(decoded[_keySenderKey]);
      final Uint8List? nonce = _decode(decoded[_keyNonce]);
      final Uint8List? cipher = _decode(decoded[_keyCipher]);
      final Uint8List? mac = _decode(decoded[_keyMac]);

      if (senderKey == null ||
          senderKey.length != 32 ||
          nonce == null ||
          nonce.length != 12 ||
          cipher == null ||
          mac == null) {
        return null;
      }
      return E2eeEnvelope(
        version: currentVersion,
        senderPublicKey: senderKey,
        nonce: nonce,
        cipherText: cipher,
        mac: mac,
      );
    } on Object {
      return null;
    }
  }

  static Uint8List? _decode(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64Url.decode(value);
    } on Object {
      return null;
    }
  }
}

/// End-to-end encryption for one-to-one conversations.
///
/// ### What is actually guaranteed
///
/// A message body is sealed on the sender's device and opened on the
/// recipient's device. Firestore only ever stores the ciphertext, so the
/// database operator — and anyone who reads the documents — sees nothing.
///
/// ### What is NOT guaranteed, and must not be assumed
///
/// This is a **first iteration**, and it is deliberately narrower than Signal:
///
/// * **No forward secrecy.** One X25519 shared secret per conversation
///   encrypts every message forever. If that secret ever leaks, *all* past
///   messages in the conversation fall with it. Fixing this needs a ratchet.
///   // TODO: Complete protocol handshake — replace the static shared secret
///   // with X3DH + a Double Ratchet (per-message ephemeral keys) so a
///   // compromised key cannot retroactively open old messages.
/// * **No MITM protection.** Public keys are read from `users/{uid}`. A server
///   that lies about a public key can silently sit in the middle. Real
///   deployments need out-of-band verification.
///   // TODO: Derive a safety number from both public keys, show it as a QR
///   // code on the contact-info screen, and let the user mark a peer verified.
/// * **Group chats are not covered.** Group encryption needs sender keys and
///   per-member fan-out, not a two-party exchange.
///   // TODO: Extend to groups with a per-group key wrapped once per member.
///
/// ### Failure policy
///
/// Everything fails **open** and loudly. If a peer has not published a key, or
/// the private key is unavailable, [seal] returns null and the caller sends
/// plaintext rather than dropping the message — silently failing to send is
/// worse than sending less privately, and the app must never appear broken
/// because a key exchange had not happened yet.
class E2eeService {
  E2eeService({
    FirebaseFirestore? firestore,
    this.secureStorage,
    this.random,
  }) : _db = firestore;

  /// The platform keystore. Injected by tests; otherwise the Android Keystore
  /// / iOS Keychain implementation, created on first use.
  FlutterSecureStorage? secureStorage;

  /// Injected by tests for reproducible nonces. [Random.secure] otherwise.
  Random? random;

  /// Where public keys are published.
  static const String usersCollection = 'users';

  /// Field on `users/{uid}` holding the base64url X25519 public key.
  static const String publicKeyField = 'e2eePublicKey';

  /// Shown in the chat list for a conversation whose last message is sealed —
  /// the preview itself must not leak.
  static const String sealedPreview = 'Encrypted message';

  /// Shown in place of a body that could not be opened.
  static const String undecryptablePreview = 'Could not decrypt this message';

  /// ⚠️ The key material is stored **per uid**, not per device.
  ///
  /// It used to be two fixed keys, which meant every account on the device
  /// shared one identity: account B, signing in after account A, would read
  /// A's private key out of the keystore and publish A's public key as its own.
  /// That is an account-isolation defect — the two accounts' messages became
  /// mutually readable — and it is why the key names carry the uid.
  ///
  /// The unsuffixed names are kept only as a migration source: the first run
  /// after this change adopts an existing identity under the uid that is
  /// signed in, then deletes the legacy entry so a later account cannot adopt
  /// it. See [ensureIdentity].
  static const String _legacyPrivateKeyStorageKey = 'imo_e2ee_private_key';
  static const String _legacyPublicKeyStorageKey = 'imo_e2ee_public_key';

  static String _privateKeyStorageKey(String uid) => 'imo_e2ee_private_key_$uid';
  static String _publicKeyStorageKey(String uid) => 'imo_e2ee_public_key_$uid';

  /// AES-GCM; 12-byte nonce, 128-bit tag, as required by the cipher.
  static final AesGcm _aes = AesGcm.with256bits();
  static final X25519 _x25519 = X25519();

  FirebaseFirestore? _db;

  SimpleKeyPair? _keyPair;
  Uint8List? _publicKey;
  String _uid = '';

  /// Cached peer public keys. Null entries are cached too, so an account with
  /// no published key is not re-fetched on every message.
  final Map<String, Uint8List?> _peerKeys = <String, Uint8List?>{};

  /// True once this device holds a usable key pair.
  bool get isReady => _keyPair != null && _publicKey != null;

  /// The uid the current key pair belongs to.
  String get uid => _uid;

  /// This device's public key, base64url — what gets published.
  String? get publicKeyBase64 =>
      _publicKey == null ? null : base64Url.encode(_publicKey!);

  /// Visible for testing: the raw public key bytes.
  @visibleForTesting
  Uint8List? get publicKeyBytes => _publicKey;

  /// Visible for testing: registers a peer's public key so [seal] and [open]
  /// can be exercised without a Firestore round trip.
  @visibleForTesting
  void seedPeerKey(String uid, Uint8List key) => _peerKeys[uid] = key;

  FirebaseFirestore get _firestore => _db ??= FirebaseFirestore.instance;

  FlutterSecureStorage get _storage =>
      secureStorage ??= const FlutterSecureStorage();

  // ------------------------------------------------------------- identity

  /// Loads this device's key pair, generating and publishing it on first run.
  ///
  /// Idempotent and cheap after the first call. Safe to call on every sign-in:
  /// the private key lives in secure storage, so a reinstall generates a new
  /// identity (and therefore cannot read old messages — which is correct, and
  /// why key backup is a separate problem).
  Future<void> ensureIdentity(String uid) async {
    if (uid.isEmpty) return;
    if (uid == _uid && _keyPair != null) return;

    _uid = uid;
    _peerKeys.clear();

    try {
      final FlutterSecureStorage store = _storage;
      final ({String? private, String? public}) stored =
          await _readIdentity(store, uid);

      if (stored.private != null && stored.public != null) {
        final Uint8List? private = E2eeEnvelope._decode(stored.private!);
        final Uint8List? public = E2eeEnvelope._decode(stored.public!);
        if (private != null &&
            public != null &&
            private.length == 32 &&
            public.length == 32) {
          _keyPair = _keyPairFrom(private, public);
          _publicKey = public;
          await _publishPublicKey(uid, public);
          return;
        }
        debugPrint('E2EE: stored key material is malformed, regenerating');
      }

      final SimpleKeyPair keyPair = await _x25519.newKeyPair();
      final SimplePublicKey public = await keyPair.extractPublicKey();
      final List<int> private = await keyPair.extractPrivateKeyBytes();

      final Uint8List publicBytes = Uint8List.fromList(public.bytes);
      final Uint8List privateBytes = Uint8List.fromList(private);

      await store.write(
        key: _privateKeyStorageKey(uid),
        value: base64Url.encode(privateBytes),
      );
      await store.write(
        key: _publicKeyStorageKey(uid),
        value: base64Url.encode(publicBytes),
      );

      _keyPair = keyPair;
      _publicKey = publicBytes;
      await _publishPublicKey(uid, publicBytes);
    } on Object catch (error) {
      // A missing keystore (some Android emulators, a rooted device) must not
      // take messaging down with it. Encryption simply stays unavailable.
      debugPrint('E2EE identity unavailable: $error');
    }
  }

  /// Reads this uid's stored identity, migrating a pre-per-uid one if needed.
  ///
  /// The migration exists so that the change to per-uid key names does not
  /// orphan every message already sealed on this device: the very first
  /// `ensureIdentity` after the upgrade finds the old fixed-name entry, adopts
  /// it under the signed-in uid, and **deletes the old entry**. Deleting it is
  /// the part that matters — leaving it in place would let the next account to
  /// sign in adopt the same key, which is the defect this whole change fixes.
  Future<({String? private, String? public})> _readIdentity(
    FlutterSecureStorage store,
    String uid,
  ) async {
    final String? ownPrivate =
        await store.read(key: _privateKeyStorageKey(uid));
    final String? ownPublic = await store.read(key: _publicKeyStorageKey(uid));
    if (ownPrivate != null && ownPublic != null) {
      return (private: ownPrivate, public: ownPublic);
    }

    final String? legacyPrivate =
        await store.read(key: _legacyPrivateKeyStorageKey);
    final String? legacyPublic =
        await store.read(key: _legacyPublicKeyStorageKey);
    if (legacyPrivate == null || legacyPublic == null) {
      return (private: null, public: null);
    }

    await store.write(key: _privateKeyStorageKey(uid), value: legacyPrivate);
    await store.write(key: _publicKeyStorageKey(uid), value: legacyPublic);
    await purgeLegacyKeys();
    debugPrint('E2EE: adopted the pre-per-uid identity for $uid');
    return (private: legacyPrivate, public: legacyPublic);
  }

  /// Deletes the pre-per-uid key material, if any is still on the device.
  ///
  /// Called on sign-out as well as after a migration, so a device that upgrades
  /// and then switches accounts cannot hand the first account's private key to
  /// the second.
  Future<void> purgeLegacyKeys() async {
    try {
      final FlutterSecureStorage store = _storage;
      await store.delete(key: _legacyPrivateKeyStorageKey);
      await store.delete(key: _legacyPublicKeyStorageKey);
    } on Object catch (error) {
      debugPrint('E2EE: purging legacy keys failed: $error');
    }
  }

  /// Deletes [uid]'s stored key pair. Used by account deletion, never by a plain
  /// sign-out — the key has to survive that, or signing back in could not read
  /// the account's own history.
  Future<void> forgetStoredIdentity(String uid) async {
    if (uid.isEmpty) return;
    try {
      final FlutterSecureStorage store = _storage;
      await store.delete(key: _privateKeyStorageKey(uid));
      await store.delete(key: _publicKeyStorageKey(uid));
      if (uid == _uid) reset();
    } on Object catch (error) {
      debugPrint('E2EE: forgetting $uid failed: $error');
    }
  }

  /// Drops the in-memory identity on sign-out. The stored key is kept, so
  /// signing back in on the same device restores it.
  void reset() {
    _keyPair = null;
    _publicKey = null;
    _uid = '';
    _peerKeys.clear();
  }

  /// Rebuilds a [SimpleKeyPair] from stored bytes.
  ///
  /// The public half is required: X25519 derives the shared secret from the
  /// private scalar, but the API needs both to build a usable key pair object.
  static SimpleKeyPair _keyPairFrom(Uint8List private, Uint8List public) =>
      SimpleKeyPairData(
        private,
        publicKey: SimplePublicKey(public, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );

  Future<void> _publishPublicKey(String uid, Uint8List public) async {
    try {
      await _firestore.collection(usersCollection).doc(uid).set(
        <String, dynamic>{
          publicKeyField: base64Url.encode(public),
          'e2eeUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('E2EE public key not published for $uid: $error');
    }
  }

  // -------------------------------------------------------------- sealing

  /// Seals [plaintext] for [peerUid].
  ///
  /// Returns the encoded envelope, or null when it cannot — no identity, no
  /// published peer key, or an empty body. The caller sends plaintext on null.
  Future<String?> seal(String peerUid, String plaintext) async {
    if (plaintext.isEmpty || peerUid.isEmpty || peerUid == _uid) return null;
    final SimpleKeyPair? keyPair = _keyPair;
    final Uint8List? ownPublic = _publicKey;
    if (keyPair == null || ownPublic == null) return null;

    final Uint8List? peerKey = await _publicKeyFor(peerUid);
    if (peerKey == null) return null;

    try {
      final SecretKey shared = await _sharedSecret(keyPair, peerKey);
      final Uint8List nonce = _nonce();
      final SecretBox box = await _aes.encrypt(
        utf8.encode(plaintext),
        secretKey: shared,
        nonce: nonce,
      );
      return E2eeEnvelope(
        version: E2eeEnvelope.currentVersion,
        senderPublicKey: ownPublic,
        nonce: Uint8List.fromList(box.nonce),
        cipherText: Uint8List.fromList(box.cipherText),
        mac: Uint8List.fromList(box.mac.bytes),
      ).encode();
    } on Object catch (error) {
      // Never return a partially-built envelope: it would be undecryptable.
      debugPrint('E2EE seal failed: $error');
      return null;
    }
  }

  /// Opens a sealed body.
  ///
  /// Returns null when [source] is not a valid envelope, or decryption fails —
  /// including a tampered payload, which AES-GCM detects via its MAC. Callers
  /// show [undecryptablePreview] rather than the raw ciphertext.
  Future<String?> open(String source, {String? senderId}) async {
    final E2eeEnvelope? envelope = E2eeEnvelope.tryDecode(source);
    if (envelope == null) return null;

    final SimpleKeyPair? keyPair = _keyPair;
    if (keyPair == null) return null;

    Uint8List peerKey = envelope.senderPublicKey;
    if (peerKey.length != 32) {
      final String? sender = senderId;
      if (sender == null || sender.isEmpty) return null;
      final Uint8List? published = await _publicKeyFor(sender);
      if (published == null) return null;
      peerKey = published;
    }

    try {
      final SecretKey shared = await _sharedSecret(keyPair, peerKey);
      final List<int> clear = await _aes.decrypt(
        SecretBox(
          envelope.cipherText,
          nonce: envelope.nonce,
          mac: Mac(envelope.mac),
        ),
        secretKey: shared,
      );
      return utf8.decode(clear);
    } on Object catch (error) {
      debugPrint('E2EE open failed: $error');
      return null;
    }
  }

  /// True when [peerUid] has published a key, i.e. [seal] can succeed.
  Future<bool> canSealFor(String peerUid) async =>
      _keyPair != null && await _publicKeyFor(peerUid) != null;

  // ------------------------------------------------------------- internals

  Future<SecretKey> _sharedSecret(
    SimpleKeyPair keyPair,
    Uint8List peerPublic,
  ) =>
      _x25519.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
      );

  /// Fetches and caches a peer's published public key.
  Future<Uint8List?> _publicKeyFor(String uid) async {
    if (_peerKeys.containsKey(uid)) return _peerKeys[uid];
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _firestore.collection(usersCollection).doc(uid).get();
      final Object? raw = doc.data()?[publicKeyField];
      final Uint8List? key = E2eeEnvelope._decode(raw);
      final Uint8List? valid = key != null && key.length == 32 ? key : null;
      _peerKeys[uid] = valid;
      if (valid == null) {
        debugPrint('E2EE: $uid has no published key — sending in the clear');
      }
      return valid;
    } on Object catch (error) {
      debugPrint('E2EE public key fetch for $uid failed: $error');
      return null;
    }
  }

  Uint8List _nonce() {
    final Random random = this.random ?? Random.secure();
    return Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256), growable: false),
    );
  }
}
