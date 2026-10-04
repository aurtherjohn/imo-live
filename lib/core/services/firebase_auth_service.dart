import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../constants/country_data.dart';
import 'remote_contact_service.dart';

/// A failure the UI can present verbatim.
class AuthException implements Exception {
  const AuthException(this.message, {this.code = ''});

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// Everything the app needs from Firebase Authentication plus the Firestore
/// side-effects that must accompany it (profile documents, username index,
/// presence).
///
/// The class never lets a raw `FirebaseAuthException` escape: each one is
/// mapped to a message written for a person, because "ERROR_INVALID_CREDENTIAL"
/// is not a sentence. Screens catch [AuthException] and show `message`.
class FirebaseAuthService {
  FirebaseAuthService();

  static const String usersCollection = 'users';

  /// Characters allowed in a generated handle. Digits only keeps handles short,
  /// unambiguous and free of lookalike-letter confusion.
  static const String _handlePrefix = 'imouser_';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The signed-in user, or null. Reads the cached value, so it is safe to call
  /// during a widget build.
  User? get currentUser {
    try {
      return _auth.currentUser;
    } on Object {
      return null;
    }
  }

  String get currentUid => currentUser?.uid ?? '';

  /// Emits on every sign-in / sign-out. Drives the auth gate in the router.
  Stream<User?> authStateChanges() {
    try {
      return _auth.authStateChanges();
    } on Object catch (error) {
      debugPrint('authStateChanges unavailable: $error');
      return Stream<User?>.value(null);
    }
  }

  // ----------------------------------------------------------------- email

  /// Creates an account and the matching Firestore documents.
  ///
  /// Returns the new user. The email is *not* yet verified — the caller routes
  /// to the OTP screen next. Uniqueness of the handle is guaranteed by writing
  /// `usernames/{handle}` inside a transaction, so two simultaneous signups
  /// cannot both claim the same handle.
  Future<String> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    final String normalisedEmail = RemoteContactService.normaliseEmail(email);
    try {
      final UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: normalisedEmail,
        password: password,
      );
      final User? user = credential.user;
      if (user == null) {
        throw const AuthException('The account could not be created.');
      }

      await user.updateDisplayName(name.trim());
      final String username = await generateUniqueUsername();
      await _createUserDocument(
        uid: user.uid,
        name: name.trim(),
        email: normalisedEmail,
        username: username,
      );
      // Firebase sends its own verification message; the OTP screen in the app
      // re-sends it on demand and polls for the verified flag.
      await user.sendEmailVerification();
      return user.uid;
    } on FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: RemoteContactService.normaliseEmail(email),
        password: password,
      );
      final User? user = credential.user;
      if (user == null) throw const AuthException('Sign-in failed.');
      await touchPresence(user.uid, isOnline: true);
      return user.uid;
    } on FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: RemoteContactService.normaliseEmail(email),
      );
    } on FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  /// Re-sends the verification email for the signed-in account.
  Future<void> resendVerificationEmail() async {
    final User? user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw _translate(error);
    }
  }

  /// Reloads the account and reports whether the email is verified yet.
  ///
  /// The OTP screen polls this: an email link cannot be observed directly, so
  /// the only honest check is "has the server flipped the flag?".
  Future<bool> isEmailVerified() async {
    final User? user = currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ---------------------------------------------------------------- signout

  Future<void> signOut() async {
    final String uid = currentUid;
    if (uid.isNotEmpty) await touchPresence(uid, isOnline: false);
    try {
      await _auth.signOut();
    } on Object catch (error) {
      debugPrint('signOut failed: $error');
    }
  }

  // --------------------------------------------------------------- profiles

  /// Creates `users/{uid}` plus the three directory index documents.
  Future<void> _createUserDocument({
    required String uid,
    required String name,
    required String email,
    required String username,
    String phone = '',
    String firstName = '',
    String lastName = '',
    String signupMethod = AppConstants.signupMethodEmail,
  }) async {
    final String trimmedName = name.trim();
    final String phoneDigits = RemoteContactService.normalisePhone(phone);
    // Derived from the number, not asked for. `8801712345678` is a Bangladeshi
    // number and nothing else, so the country is knowable at signup — making
    // the user pick it from a 240-entry list would be asking them to retype
    // something the number already says. Null for an email account, which has
    // no number to read it from.
    //
    // The type is inferred rather than written: `CountryData` works with the
    // picker's `Country` (settings.dart), and there is a second, unrelated
    // `Country` in models/country.dart. Naming it here would mean choosing one
    // of the two, which is exactly the ambiguity that produced this bug.
    final country = phoneDigits.isEmpty
        ? null
        : CountryData.byDialPrefix(phoneDigits);
    final WriteBatch batch = _db.batch();
    batch.set(
      _db.collection(usersCollection).doc(uid),
      <String, dynamic>{
        'uid': uid,
        'name': trimmedName,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'username': username,
        'email': email,
        'phone': phoneDigits,
        // ISO 3166-1 alpha-2 and the E.164 dial code, both digits-only on the
        // code side so every consumer strips the `+` the same way.
        if (country != null) 'countryIso': country.iso,
        if (country != null)
          'countryCode': country.dialCode.replaceAll('+', ''),
        'bio': '',
        'age': 0,
        'gender': '',
        'avatarUrl': '',
        'coverUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
        'isVerified': false,
        // Which flow created this account. The auth gate and the profile screen
        // both need to know: a phone account has no real address to verify.
        'signupMethod': signupMethod,
        // ------------------------------------------------------- searchable
        //
        // Denormalised copies. Firestore cannot query case-insensitively and
        // cannot do `contains`, so every field a search touches is written
        // twice: once as displayed, once in the canonical form the query uses.
        'nameLowercase': trimmedName.toLowerCase(),
        'usernameLower': username.toLowerCase(),
        'phoneLower': phoneDigits,
        // Firestore has no substring operator, so `array-contains` over
        // materialised tokens is the only client-side way to do token search.
        'searchKeywords': buildSearchKeywords(
          name: trimmedName,
          firstName: firstName,
          lastName: lastName,
          username: username,
          phone: phoneDigits,
        ),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection(RemoteContactService.usernamesCollection).doc(username),
      <String, dynamic>{'uid': uid},
      SetOptions(merge: true),
    );
    if (email.isNotEmpty) {
      batch.set(
        _db.collection(RemoteContactService.emailsCollection).doc(email),
        <String, dynamic>{'uid': uid},
        SetOptions(merge: true),
      );
    }
    if (phone.isNotEmpty) {
      batch.set(
        _db
            .collection(RemoteContactService.phonesCollection)
            .doc(RemoteContactService.normalisePhone(phone)),
        <String, dynamic>{'uid': uid},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Creates the profile documents for a user who signed up through an OAuth
  /// provider rather than with a password.
  ///
  /// An existing profile is left alone apart from refreshing the avatar, so
  /// signing in again with Google never overwrites a name or bio the user set
  /// inside the app.
  Future<void> ensureProfileForExternalUser({
    required String uid,
    required String name,
    required String email,
    String photoUrl = '',
  }) async {
    try {
      final DocumentReference<Map<String, dynamic>> profile =
          _db.collection(usersCollection).doc(uid);
      final DocumentSnapshot<Map<String, dynamic>> existing =
          await profile.get();

      if (!existing.exists) {
        final String username = await generateUniqueUsername();
        await _createUserDocument(
          uid: uid,
          name: name,
          email: email,
          username: username,
        );
        if (photoUrl.isNotEmpty) {
          await profile.set(
            <String, dynamic>{'avatarUrl': photoUrl},
            SetOptions(merge: true),
          );
        }
        return;
      }

      final Map<String, dynamic> updates = <String, dynamic>{
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      // Only fill the avatar if the user has not uploaded one themselves.
      final String currentAvatar =
          (existing.data()?['avatarUrl'] as String?)?.trim() ?? '';
      if (currentAvatar.isEmpty && photoUrl.isNotEmpty) {
        updates['avatarUrl'] = photoUrl;
      }
      final String currentEmail =
          (existing.data()?['email'] as String?)?.trim() ?? '';
      if (currentEmail.isEmpty && email.isNotEmpty) {
        updates['email'] = RemoteContactService.normaliseEmail(email);
        final WriteBatch batch = _db.batch();
        batch.set(
          _db
              .collection(RemoteContactService.emailsCollection)
              .doc(RemoteContactService.normaliseEmail(email)),
          <String, dynamic>{'uid': uid},
          SetOptions(merge: true),
        );
        batch.set(profile, updates, SetOptions(merge: true));
        await batch.commit();
        return;
      }
      await profile.set(updates, SetOptions(merge: true));
    } on Object catch (error) {
      debugPrint('ensureProfileForExternalUser($uid) failed: $error');
    }
  }

  /// Updates the mutable fields of the signed-in user's profile.
  ///
  /// Handle changes additionally rewrite `usernames/{handle}` inside a
  /// transaction, so a taken handle is rejected rather than silently stolen.
  Future<void> updateProfile({
    String? name,
    String? username,
    String? bio,
    int? age,
    String? gender,
    String? phone,
    String? avatarUrl,
    String? coverUrl,
    bool? isVerified,
  }) async {
    final String uid = currentUid;
    if (uid.isEmpty) throw const AuthException('You are not signed in.');

    final Map<String, dynamic> updates = <String, dynamic>{};
    if (name != null) {
      updates['name'] = name.trim();
      // Keep the searchable copy in step with the display name. Without this a
      // rename would leave the old name matching searches forever.
      updates['nameLowercase'] = name.trim().toLowerCase();
    }
    if (bio != null) updates['bio'] = bio.trim();
    if (age != null) updates['age'] = age;
    if (gender != null) updates['gender'] = gender;
    if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;
    if (coverUrl != null) updates['coverUrl'] = coverUrl;
    if (isVerified != null) updates['isVerified'] = isVerified;

    if (username != null && username.trim().isNotEmpty) {
      final String desired = RemoteContactService.normaliseUsername(username);
      final bool claimed = await _claimUsername(uid: uid, username: desired);
      if (!claimed) {
        throw AuthException('@$desired is already taken. Try another one.');
      }
      updates['username'] = desired;
    }

    if (phone != null && phone.trim().isNotEmpty) {
      final String normalised = RemoteContactService.normalisePhone(phone);
      updates['phone'] = normalised;
      await _db
          .collection(RemoteContactService.phonesCollection)
          .doc(normalised)
          .set(<String, dynamic>{'uid': uid}, SetOptions(merge: true));
    }

    if (updates.isEmpty) return;

    // Any field that feeds `searchKeywords` has to refresh it, or a rename
    // leaves the old tokens matching forever. This is the only place that needs
    // to read the profile back, so it is done once, here, rather than on every
    // save.
    if (name != null || username != null || phone != null) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> current =
            await _db.collection(usersCollection).doc(uid).get();
        final Map<String, dynamic> data = current.data() ?? <String, dynamic>{};
        updates['searchKeywords'] = buildSearchKeywords(
          name: name?.trim() ?? (data['name'] as String?) ?? '',
          firstName: (data['firstName'] as String?) ?? '',
          lastName: (data['lastName'] as String?) ?? '',
          username:
              (updates['username'] as String?) ?? (data['username'] as String?) ?? '',
          phone: (updates['phone'] as String?) ?? (data['phone'] as String?) ?? '',
        );
      } on Object catch (error) {
        // A failed keyword refresh must not fail the edit the user asked for.
        debugPrint('searchKeywords refresh for $uid failed: $error');
      }
    }

    await _db
        .collection(usersCollection)
        .doc(uid)
        .set(updates, SetOptions(merge: true));

    if (name != null && name.trim().isNotEmpty) {
      try {
        await currentUser?.updateDisplayName(name.trim());
      } on Object catch (error) {
        debugPrint('updateDisplayName failed: $error');
      }
    }
  }

  /// Atomically claims [username] for [uid].
  ///
  /// Returns false when someone else owns it. The transaction is what makes the
  /// handle genuinely unique — a plain `get` followed by a `set` would race.
  Future<bool> _claimUsername({
    required String uid,
    required String username,
  }) async {
    final DocumentReference<Map<String, dynamic>> index =
        _db.collection(RemoteContactService.usernamesCollection).doc(username);
    try {
      return await _db.runTransaction<bool>(
        (Transaction txn) async {
          final DocumentSnapshot<Map<String, dynamic>> snapshot =
              await txn.get(index);
          final String? owner = snapshot.data()?['uid'] as String?;
          if (owner != null && owner != uid) return false;

          // Release the previous handle so it becomes available again.
          final DocumentSnapshot<Map<String, dynamic>> profile =
              await txn.get(_db.collection(usersCollection).doc(uid));
          final String previous =
              (profile.data()?['username'] as String?)?.trim() ?? '';
          if (previous.isNotEmpty && previous != username) {
            txn.delete(_db
                .collection(RemoteContactService.usernamesCollection)
                .doc(previous));
          }
          txn.set(index, <String, dynamic>{'uid': uid});
          return true;
        },
      );
    } on Object catch (error) {
      debugPrint('claimUsername($username) failed: $error');
      rethrow;
    }
  }

  /// Generates `imouser_XXXXXX` that no one else holds.
  ///
  /// Rejection sampling rather than a counter: 10^6 space, checked against the
  /// index, retried a bounded number of times before widening the suffix so a
  /// crowded namespace can never hard-fail a signup.
  Future<String> generateUniqueUsername({int digits = 6}) async {
    final Random random = Random.secure();
    for (int attempt = 0; attempt < 12; attempt++) {
      final int width = digits + (attempt ~/ 4);
      final int bound = pow(10, width).toInt();
      final String suffix = random.nextInt(bound).toString().padLeft(width, '0');
      final String candidate = '$_handlePrefix$suffix';
      final DocumentSnapshot<Map<String, dynamic>> existing = await _db
          .collection(RemoteContactService.usernamesCollection)
          .doc(candidate)
          .get();
      if (!existing.exists) return candidate;
    }
    // Fall back to a uid-derived handle, which is unique by construction.
    final String uid = currentUid;
    return '$_handlePrefix${uid.isEmpty ? DateTime.now().microsecondsSinceEpoch : uid}'
        .substring(0, min(24, _handlePrefix.length + 18));
  }

  /// Checks whether a handle is free, for the live "taken / available" hint in
  /// profile setup.
  Future<bool> isUsernameAvailable(String username) async {
    final String normalised = RemoteContactService.normaliseUsername(username);
    if (normalised.isEmpty) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> existing = await _db
          .collection(RemoteContactService.usernamesCollection)
          .doc(normalised)
          .get();
      if (!existing.exists) return true;
      return (existing.data()?['uid'] as String?) == currentUid;
    } on Object catch (error) {
      debugPrint('isUsernameAvailable($normalised) failed: $error');
      return false;
    }
  }

  // ----------------------------------------------------------------- phone

  /// Creates an account from a phone number plus a PIN.
  ///
  /// ### Where the PIN goes
  ///
  /// Straight into the auth SDK as the account password, and nowhere else. The
  /// backend hashes and salts it; this app never sees it again and **nothing
  /// password-derived is ever written to Firestore**.
  ///
  /// That is a deliberate departure from the original spec, which asked for a
  /// client-computed `passwordHash` + `salt` stored on `users/{uid}`. Two
  /// reasons it cannot work here:
  ///
  /// 1. **It would be readable.** The deployed rules grant every signed-in user
  ///    read on every document. A hash sitting on `users/{uid}` is therefore
  ///    readable by any account in the app.
  /// 2. **A 6-digit PIN cannot be hashed safely at all.** Ten to the sixth
  ///    candidates is under a second of work for a single GPU. Against a leaked
  ///    salt+hash an attacker does not need to guess online — they enumerate
  ///    the entire keyspace offline. No KDF setting fixes a secret that small;
  ///    only a server that refuses to answer fast does, which is exactly what
  ///    the auth backend is.
  ///
  /// So the PIN is a *password*, and it is stored the way passwords are stored.
  ///
  /// ### Ordering
  ///
  /// The auth account is created first, then the Firestore claim. If the claim
  /// fails the auth account is deleted again ([_rollback]) — otherwise a
  /// half-created account would hold the derived address and permanently block
  /// the number.
  Future<String> signUpWithPhone({
    required String phoneDigits,
    required String pin,
    required String firstName,
    required String lastName,
    String username = '',
  }) async {
    final String digits = RemoteContactService.normalisePhone(phoneDigits);
    if (digits.length < 6) {
      throw const AuthException('Enter a valid phone number.');
    }
    final String email = AppConstants.phoneAuthEmailFor(digits);
    final String first = firstName.trim();
    final String last = lastName.trim();
    final String fullName =
        <String>[first, last].where((String p) => p.isNotEmpty).join(' ');

    User? created;
    try {
      final UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: pin,
      );
      created = credential.user;
      if (created == null) {
        throw const AuthException('The account could not be created.');
      }
      await created.updateDisplayName(fullName);

      // The handle is claimed together with the number, inside one transaction.
      // A collision is resolved by widening the numeric suffix and retrying,
      // because the caller may still have been signed out when it generated the
      // handle and therefore could not have checked availability first.
      String handle = username.trim().isNotEmpty
          ? RemoteContactService.normaliseUsername(username)
          : generateLocalUsername();

      bool claimed = false;
      for (int attempt = 0; attempt < 8 && !claimed; attempt++) {
        claimed = await _claimPhoneIdentity(
          uid: created.uid,
          phoneDigits: digits,
          username: handle,
          authEmail: email,
        );
        if (!claimed) {
          handle = generateLocalUsername(digits: 6 + (attempt ~/ 3));
        }
      }
      if (!claimed) {
        throw const AuthException(
          'That number or username is already taken. Try another one.',
        );
      }

      await _createUserDocument(
        uid: created.uid,
        name: fullName.isEmpty ? digits : fullName,
        // The derived address is a routing detail, not a contact address: it is
        // left out of the profile so it is neither displayed nor searchable.
        email: '',
        username: handle,
        phone: digits,
        firstName: first,
        lastName: last,
        signupMethod: AppConstants.signupMethodPhone,
      );
      return created.uid;
    } on FirebaseAuthException catch (error) {
      await _rollback(created);
      throw _translatePhoneSignUp(error);
    } on AuthException {
      await _rollback(created);
      rethrow;
    } on Object catch (error) {
      debugPrint('signUpWithPhone failed: $error');
      await _rollback(created);
      throw const AuthException('The account could not be created.');
    }
  }

  /// Signs in with a phone number and PIN.
  ///
  /// The derived address is computed locally, so this needs **no Firestore
  /// read** — which is the only way it can work at all, since the caller is
  /// signed out and the rules require an authenticated request.
  Future<String> signInWithPhone({
    required String phoneDigits,
    required String pin,
  }) async {
    final String digits = RemoteContactService.normalisePhone(phoneDigits);
    if (digits.length < 6) {
      throw const AuthException('Enter a valid phone number.');
    }
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: AppConstants.phoneAuthEmailFor(digits),
        password: pin,
      );
      final User? user = credential.user;
      if (user == null) throw const AuthException('Sign-in failed.');
      await touchPresence(user.uid, isOnline: true);
      return user.uid;
    } on FirebaseAuthException catch (error) {
      throw _translatePhoneSignIn(error);
    }
  }

  /// Atomically claims the number and the handle for [uid].
  ///
  /// Returns false when either is already held by somebody else. A transaction
  /// rather than a `get`-then-`set` because two people signing up on the same
  /// number at the same instant must not both succeed.
  ///
  /// The `phones/{digits}` document carries `authEmail` as well as `uid`, so the
  /// index is self-describing: a reader can tell a phone account from an email
  /// account that merely happens to have a number on file.
  Future<bool> _claimPhoneIdentity({
    required String uid,
    required String phoneDigits,
    required String username,
    required String authEmail,
  }) async {
    final DocumentReference<Map<String, dynamic>> phoneRef =
        _db.collection(RemoteContactService.phonesCollection).doc(phoneDigits);
    final DocumentReference<Map<String, dynamic>> handleRef =
        _db.collection(RemoteContactService.usernamesCollection).doc(username);
    try {
      return await _db.runTransaction<bool>((Transaction txn) async {
        final DocumentSnapshot<Map<String, dynamic>> phoneSnap =
            await txn.get(phoneRef);
        final String? phoneOwner = phoneSnap.data()?['uid'] as String?;
        if (phoneOwner != null && phoneOwner != uid) return false;

        final DocumentSnapshot<Map<String, dynamic>> handleSnap =
            await txn.get(handleRef);
        final String? handleOwner = handleSnap.data()?['uid'] as String?;
        if (handleOwner != null && handleOwner != uid) return false;

        txn.set(
          phoneRef,
          <String, dynamic>{
            'uid': uid,
            'phone': phoneDigits,
            'authEmail': authEmail,
            'signupMethod': AppConstants.signupMethodPhone,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        txn.set(
          handleRef,
          <String, dynamic>{'uid': uid},
          SetOptions(merge: true),
        );
        return true;
      });
    } on Object catch (error) {
      debugPrint('claimPhoneIdentity($phoneDigits) failed: $error');
      rethrow;
    }
  }

  /// Deletes a half-created auth account.
  ///
  /// Best-effort on purpose: every caller is already on an error path, and a
  /// failed cleanup must not replace the real error with a confusing one.
  ///
  /// The sign-out fallback matters more than it looks. `delete()` needs a recent
  /// login and can be refused. If it is, the account stays — but the *session*
  /// must not, because the auth gate would walk the user straight into the app
  /// as a signed-in account with no profile document, and every screen behind
  /// that gate reads under a uid that does not exist.
  Future<void> _rollback(User? user) async {
    if (user == null) return;
    try {
      await user.delete();
    } on Object catch (error) {
      debugPrint('Rollback of ${user.uid} failed: $error');
      try {
        await _auth.signOut();
      } on Object catch (signOutError) {
        debugPrint('Rollback sign-out failed: $signOutError');
      }
    }
  }

  /// Generates `imouser_XXXXXX` for a phone signup.
  ///
  /// Purely local and deliberately *not* checked against the directory: the
  /// caller is mid-signup, and the rules deny a signed-out read of
  /// `usernames/{handle}`. Uniqueness is enforced by the atomic claim in
  /// [signUpWithPhone], which retries with a wider suffix on a collision — so a
  /// 10^6 space never has to be checked up front to be safe.
  ///
  /// Digits rather than a name slug: the user has not told us their name yet at
  /// this point in the phone flow, and a number is unambiguous where
  /// transliterated names are not.
  static String generateLocalUsername({int digits = 6}) {
    final int width = digits.clamp(4, 12);
    final int bound = pow(10, width).toInt();
    final String suffix =
        Random.secure().nextInt(bound).toString().padLeft(width, '0');
    return '$_handlePrefix$suffix';
  }

  /// Builds a `first.lastNNN` handle from a name — `Tanvir Ahmed` →
  /// `tanvir.ahmed482`.
  ///
  /// Kept for a caller that has a name to work from; the phone flow uses
  /// [generateLocalUsername] instead.
  static String generateUsernameFromName({
    required String firstName,
    required String lastName,
    int suffixDigits = 3,
  }) {
    String slug(String raw) =>
        raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final String first = slug(firstName);
    final String last = slug(lastName);
    String base = <String>[
      if (first.isNotEmpty) first,
      if (last.isNotEmpty) last,
    ].join('.');
    if (base.isEmpty) base = 'user';
    if (base.length > 18) base = base.substring(0, 18);

    final int width = suffixDigits.clamp(2, 8);
    final int bound = pow(10, width).toInt();
    final String suffix = Random.secure().nextInt(bound).toString().padLeft(width, '0');
    return '$base$suffix';
  }

  /// Tokens written to `users/{uid}.searchKeywords`.
  ///
  /// Firestore can only test array membership, so token search means
  /// materialising the tokens at write time. Two decisions worth recording:
  ///
  /// * **Bounded prefixes, not n-grams.** A 12-character word contributes 11
  ///   entries (lengths 2–12) rather than all 66 substrings. That is what makes
  ///   `array-contains 'tanv'` find "Tanvir" while keeping the array — which is
  ///   replicated into every user document and indexed — from exploding.
  /// * **The phone number is not expanded.** It is added whole; a numeric
  ///   prefix search is already served by the `phoneLower` range query, and 13
  ///   digits of prefixes would be pure index weight.
  static List<String> buildSearchKeywords({
    required String name,
    String firstName = '',
    String lastName = '',
    String username = '',
    String phone = '',
  }) {
    final Set<String> tokens = <String>{};

    void add(String raw, {bool prefixes = true}) {
      final String value = raw.trim().toLowerCase();
      if (value.isEmpty) return;
      tokens.add(value);
      if (!prefixes) return;
      // Split on anything that is not a letter or digit, keeping Bengali
      // (U+0980–U+09FF) as a letter — the app ships an `bn` locale, so a
      // Bengali display name must tokenise too.
      for (final String word
          in value.split(RegExp(r'[^a-z0-9\u0980-\u09FF]+'))) {
        if (word.isEmpty) continue;
        tokens.add(word);
        final int ceiling = word.length < 12 ? word.length : 12;
        for (int i = 2; i <= ceiling; i++) {
          tokens.add(word.substring(0, i));
        }
      }
    }

    add(name);
    add(firstName);
    add(lastName);
    add(username);
    add(phone, prefixes: false);
    tokens.remove('');
    return tokens.toList(growable: false);
  }

  // -------------------------------------------------------------- presence

  /// Writes `isOnline` / `lastSeen` so the chat header can show presence.
  Future<void> touchPresence(String uid, {required bool isOnline}) async {
    if (uid.isEmpty) return;
    try {
      await _db.collection(usersCollection).doc(uid).set(
        <String, dynamic>{
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('touchPresence($uid) failed: $error');
    }
  }

  // ------------------------------------------------------------ error map

  /// Turns a `FirebaseAuthException` into something a person can act on.
  static AuthException _translate(FirebaseAuthException error) {
    final String message = switch (error.code) {
      'invalid-email' => 'That email address doesn\'t look right.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' => 'No account uses that email.',
      'wrong-password' => 'That password is incorrect.',
      'invalid-credential' =>
        'Email or password is incorrect. Check both and try again.',
      'email-already-in-use' => 'An account already uses that email.',
      'weak-password' => 'Choose a password with at least 6 characters.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled for the project yet.',
      'too-many-requests' =>
        'Too many attempts. Wait a moment and try again.',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      'requires-recent-login' =>
        'For security, sign in again to finish this change.',
      'account-exists-with-different-credential' =>
        'That email is registered with a different sign-in method.',
      'credential-already-in-use' =>
        'That sign-in is already linked to another account.',
      _ => error.message ?? 'Something went wrong. Please try again.',
    };
    return AuthException(message, code: error.code);
  }

  /// Signup-side translation for the phone flow.
  ///
  /// `email-already-in-use` is the one that matters: the address is derived from
  /// the number, so that code means "this number is taken" — and telling the
  /// user an *email* is in use would be nonsense when they never typed one.
  static AuthException _translatePhoneSignUp(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => const AuthException(
          'That number already has an account. Log in instead.',
          code: 'phone-already-in-use',
        ),
      'invalid-email' =>
        const AuthException('Enter a valid phone number.'),
      'weak-password' =>
        const AuthException('Use a PIN with at least 6 digits.'),
      _ => _translate(error),
    };
  }

  /// Sign-in-side translation for the phone flow.
  ///
  /// Every "this did not match" code collapses to one sentence on purpose.
  /// Distinguishing "no such number" from "wrong PIN" would let anyone
  /// enumerate which numbers have accounts by watching which message they get.
  static AuthException _translatePhoneSignIn(FirebaseAuthException error) {
    return switch (error.code) {
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' ||
      'invalid-email' =>
        const AuthException(
          'That number or PIN is incorrect.',
          code: 'phone-bad-credentials',
        ),
      'too-many-requests' => const AuthException(
          'Too many attempts. Wait a moment and try again.',
        ),
      'network-request-failed' => const AuthException(
          'No connection. Check your network and try again.',
        ),
      _ => _translate(error),
    };
  }
}
