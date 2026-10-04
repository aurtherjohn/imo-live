import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../config/app_secrets.dart';

/// The client half of OneSignal.
///
/// Two responsibilities, deliberately kept in one place:
///
///  * **Identity** — [linkUser] / [unlinkUser] bind the signed-in Firebase uid
///    to this device's OneSignal subscription and mirror the resulting player
///    id onto `users/{uid}.oneSignalPlayerId`, which is the field the Cloudflare
///    Worker reads when it sends.
///  * **Sending** — [sendNotificationToUser] posts to that Worker. The OneSignal
///    **REST API key is never in this app**: it lives in the Worker's secret
///    store, so a decompiled APK cannot push to anyone. See [AppSecrets].
///
/// Every method is best-effort. Push is an enhancement, never a dependency: a
/// missing player id, a denied permission or an unreachable Worker must never
/// break sign-in, messaging or a call.
abstract final class OneSignalService {
  /// `users/{uid}` field holding this account's OneSignal player id.
  static const String playerIdField = 'oneSignalPlayerId';

  static const String usersCollection = 'users';

  /// Binds [uid] to this device's OneSignal subscription.
  ///
  /// `login` is OneSignal's name for "this device now belongs to this external
  /// id"; passing the Firebase uid is what lets the Worker address a *person*
  /// rather than a device. It is idempotent — re-logging the same uid is cheap
  /// — which matters because the auth stream fires it on every launch.
  ///
  /// The player id is written under a merge so nothing else on the profile is
  /// disturbed. It is read back from the SDK rather than generated here: the id
  /// is assigned by OneSignal and only becomes available after `login`, so a
  /// null id is a normal outcome on a device where push has not come up yet —
  /// it is logged and skipped, not treated as a failure.
  static Future<void> linkUser(String uid) async {
    if (uid.isEmpty) return;
    try {
      OneSignal.login(uid);
      final String? playerId = OneSignal.User.pushSubscription.id;
      debugPrint('ONESIGNAL: login uid=$uid, playerId=$playerId');
      if (playerId == null || playerId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection(usersCollection)
          .doc(uid)
          .set(
            <String, dynamic>{
              playerIdField: playerId,
              'oneSignalPlayerIdUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      debugPrint('ONESIGNAL: playerId written to users/$uid');
    } on Object catch (error) {
      debugPrint('OneSignal link for $uid failed: $error');
    }
  }

  /// Detaches this device from whoever was signed in.
  ///
  /// Must run on sign-out: without it the next account on this phone would keep
  /// receiving the previous user's messages, and the previous user's account
  /// would keep pointing at a device they no longer control.
  static Future<void> unlinkUser() async {
    try {
      OneSignal.logout();
      debugPrint('ONESIGNAL: logged out');
    } on Object catch (error) {
      debugPrint('OneSignal logout failed: $error');
    }
  }

  /// The player id this device currently holds, or null before [linkUser].
  static String? get playerId {
    try {
      return OneSignal.User.pushSubscription.id;
    } on Object catch (error) {
      debugPrint('OneSignal playerId unavailable: $error');
      return null;
    }
  }

  /// Asks OneSignal to deliver a push to [receiverUid]'s devices.
  ///
  /// The request goes to the project's Cloudflare Worker, which owns the REST
  /// key, resolves `users/{receiverUid}.oneSignalPlayerId` and calls OneSignal.
  /// Returns true only on a 2xx — callers treat a false as "no push went out"
  /// and carry on, because the message itself is already written.
  ///
  /// Never awaited on a send path: the local write is what the user sees, and
  /// blocking a message on a push round-trip would trade a guaranteed delivery
  /// for an optional one.
  static Future<bool> sendNotificationToUser({
    required String receiverUid,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (receiverUid.isEmpty) return false;
    try {
      final http.Response response = await http
          .post(
            Uri.parse(AppSecrets.oneSignalWorkerUrl),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'receiverUid': receiverUid,
              'title': title,
              'body': body,
              'data': data ?? <String, dynamic>{},
            }),
          )
          .timeout(const Duration(seconds: 10));
      final bool ok = response.statusCode == 200 || response.statusCode == 201;
      if (!ok) {
        debugPrint(
          'OneSignal send to $receiverUid failed: HTTP ${response.statusCode} '
          '${response.body}',
        );
      }
      return ok;
    } on Object catch (error) {
      debugPrint('OneSignal send to $receiverUid threw: $error');
      return false;
    }
  }
}
