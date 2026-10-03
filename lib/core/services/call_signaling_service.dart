import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Where a call document has got to.
///
/// Mirrored into `calls/{callId}.status` as [name].
///
/// The lifecycle is `ringing → accepted → ended`, with `declined` and `missed`
/// as the two ways a call can fail to connect. [active] is the pre-rename
/// spelling of [accepted]: documents written by an older build still say
/// `active`, so it is read as an alias and never written.
enum CallStatus { ringing, accepted, active, ended, declined, missed }

/// A call document, `calls/{callId}`.
///
/// Parsed from plain maps rather than from WebRTC types on purpose: the
/// signalling layer must not need a peer connection to be understood or tested,
/// and `RTCSessionDescription` cannot be built in a unit test.
///
/// ### One document, two providers
///
/// The same document rings the phone for both call providers:
///
///   * **WebRTC** stores an SDP offer/answer and ICE candidates in it, because
///     the two peers have to negotiate a direct connection.
///   * **Agora** stores none of that — the SFU owns the session — but it still
///     writes the document, because the document is what makes the other
///     device's phone ring and what records the call afterwards.
///
/// So [offer] and [answer] are optional and only the WebRTC path fills them in;
/// nothing in the ring or the lifecycle depends on them being present.
@immutable
class CallDocument {
  const CallDocument({
    required this.id,
    this.callerId = '',
    this.callerName = '',
    this.calleeId = '',
    this.isVideo = false,
    this.status = CallStatus.ringing,
    this.channelName = '',
    this.offer,
    this.answer,
    this.callerCandidates = const <Map<String, dynamic>>[],
    this.calleeCandidates = const <Map<String, dynamic>>[],
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
  });

  static const String fieldCallerId = 'callerId';
  static const String fieldCallerName = 'callerName';

  /// The callee's uid, as the directive names it.
  ///
  /// Written together with the legacy [fieldCalleeId] so a document is readable
  /// by either spelling; [calleeId] accepts both when reading.
  static const String fieldReceiverId = 'receiverId';

  /// The legacy spelling of [fieldReceiverId]. Still written, for compatibility
  /// with any client that predates the rename.
  static const String fieldCalleeId = 'calleeId';

  /// `'voice'` or `'video'`, as the directive names it. Written alongside the
  /// boolean [fieldIsVideo]; either is accepted when reading.
  static const String fieldType = 'type';

  static const String fieldIsVideo = 'isVideo';
  static const String fieldStatus = 'status';

  /// The Agora channel both peers join, or empty on the WebRTC path.
  ///
  /// Carried on the document so the callee joins the channel the caller
  /// actually used, instead of independently re-deriving one from the uid pair
  /// and depending on both sides hashing identically forever.
  static const String fieldChannelName = 'channelName';

  static const String fieldOffer = 'offer';
  static const String fieldAnswer = 'answer';
  static const String fieldCallerCandidates = 'callerCandidates';
  static const String fieldCalleeCandidates = 'calleeCandidates';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldAcceptedAt = 'acceptedAt';
  static const String fieldEndedAt = 'endedAt';

  final String id;
  final String callerId;

  /// The caller's display name at the time of the call.
  ///
  /// Carried on the document so the callee can render a ring — which is a
  /// full-screen, time-critical UI — without first resolving a profile. Empty
  /// when the lookup failed, in which case the UI falls back to "Unknown".
  final String callerName;

  /// The callee's uid. Populated from `receiverId`, falling back to the legacy
  /// `calleeId`.
  final String calleeId;

  final bool isVideo;
  final CallStatus status;

  /// The Agora channel for this call, or empty on the WebRTC path.
  final String channelName;

  /// The caller's SDP offer, `{type, sdp}`. WebRTC only.
  final Map<String, dynamic>? offer;

  /// The callee's SDP answer, `{type, sdp}`. WebRTC only.
  final Map<String, dynamic>? answer;

  /// ICE candidates gathered by the caller, for the callee to consume.
  final List<Map<String, dynamic>> callerCandidates;

  /// ICE candidates gathered by the callee, for the caller to consume.
  final List<Map<String, dynamic>> calleeCandidates;

  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;

  bool get hasOffer => _sessionOf(offer) != null;
  bool get hasAnswer => _sessionOf(answer) != null;

  /// `'video'` or `'voice'` — the directive's spelling of [isVideo].
  String get type => isVideo ? 'video' : 'voice';

  /// True once the callee has picked up.
  ///
  /// Covers [CallStatus.active] because that is what an older build wrote.
  bool get isAccepted =>
      status == CallStatus.accepted || status == CallStatus.active;

  bool get isOver =>
      status == CallStatus.ended ||
      status == CallStatus.declined ||
      status == CallStatus.missed;

  /// Candidates produced by the *other* side, i.e. the ones to add locally.
  List<Map<String, dynamic>> candidatesFrom({required bool caller}) =>
      caller ? calleeCandidates : callerCandidates;

  /// True when both halves of the SDP exchange have landed.
  bool get isNegotiated => hasOffer && hasAnswer;

  /// A session map is only usable with both a type and a body.
  static Map<String, dynamic>? _sessionOf(Map<String, dynamic>? value) {
    if (value == null) return null;
    final Object? sdp = value['sdp'];
    final Object? type = value['type'];
    if (sdp is! String || sdp.isEmpty) return null;
    if (type is! String || type.isEmpty) return null;
    return value;
  }

  static CallDocument? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    return CallDocument.fromMap(doc.id, data);
  }

  /// Parses a raw call document.
  ///
  /// Split out from [fromDoc] because a [DocumentSnapshot] cannot be built in a
  /// unit test — this is the half worth testing.
  static CallDocument fromMap(String id, Map<String, dynamic> data) {
    return CallDocument(
      id: id,
      callerId: data[fieldCallerId] as String? ?? '',
      callerName: data[fieldCallerName] as String? ?? '',
      // `receiverId` is the current spelling; `calleeId` is what an older
      // document carries. Either satisfies the field.
      calleeId: (data[fieldReceiverId] as String?) ??
          (data[fieldCalleeId] as String?) ??
          '',
      // Likewise `type` supersedes the `isVideo` boolean, but both are read.
      isVideo: _isVideoOf(data),
      status: _statusOf(data[fieldStatus]),
      channelName: data[fieldChannelName] as String? ?? '',
      offer: _sessionOf(_mapOf(data[fieldOffer])),
      answer: _sessionOf(_mapOf(data[fieldAnswer])),
      callerCandidates: _candidatesOf(data[fieldCallerCandidates]),
      calleeCandidates: _candidatesOf(data[fieldCalleeCandidates]),
      createdAt: _dateOf(data[fieldCreatedAt]),
      acceptedAt: _dateOf(data[fieldAcceptedAt]),
      endedAt: _dateOf(data[fieldEndedAt]),
    );
  }

  /// `type` wins when present because it is the richer field; the boolean is
  /// the fallback for documents written before the rename.
  static bool _isVideoOf(Map<String, dynamic> data) {
    final Object? type = data[fieldType];
    if (type is String && type.isNotEmpty) return type == 'video';
    return data[fieldIsVideo] == true;
  }

  static CallStatus _statusOf(Object? value) {
    if (value is! String) return CallStatus.ringing;
    return CallStatus.values.firstWhere(
      (CallStatus s) => s.name == value,
      orElse: () => CallStatus.ringing,
    );
  }

  static Map<String, dynamic>? _mapOf(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static List<Map<String, dynamic>> _candidatesOf(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> c) => c['candidate'] is String)
        .toList(growable: false);
  }

  static DateTime? _dateOf(Object? value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        _ => null,
      };
}

/// Firestore signalling for calls, shared by both call providers.
///
/// Firestore is the *rendezvous* channel. For WebRTC it carries the SDP
/// offer/answer and ICE candidates so two devices that cannot see each other can
/// agree on how to talk; media never touches it. For Agora it carries only the
/// ring and the lifecycle — the SFU owns the session — but that is still the
/// half the other phone needs in order to ring at all.
///
/// ### Why this shape
///
/// Offer, answer and both candidate lists live in one document rather than a
/// subcollection each. A call produces a handful of small writes, the whole
/// state is readable in the console with one lookup, and [watchCall] gives the
/// peer everything it needs in a single stream — no ordering races between
/// separate collections.
///
/// ### Failure policy
///
/// Every write is best-effort. Firestore being unreachable must not take the
/// call screen down; the caller simply never connects.
class CallSignalingService {
  CallSignalingService({FirebaseFirestore? firestore}) : _db = firestore;

  static const String callsCollection = 'calls';

  FirebaseFirestore? _db;

  FirebaseFirestore get _firestore => _db ??= FirebaseFirestore.instance;

  /// Opens a call: creates the document and returns its id.
  ///
  /// The caller's display name is resolved here rather than passed in, so the
  /// caller's UI does not have to thread its own profile through the call
  /// service — and so the callee gets a name in the same write that makes the
  /// phone ring, instead of a second round trip that could arrive late.
  ///
  /// [channelName] is only meaningful on the Agora path; the WebRTC path leaves
  /// it empty and negotiates over the offer instead.
  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required bool isVideo,
    String channelName = '',
  }) async {
    final DocumentReference<Map<String, dynamic>> doc =
        _firestore.collection(callsCollection).doc();
    try {
      await doc.set(<String, dynamic>{
        CallDocument.fieldCallerId: callerId,
        CallDocument.fieldCallerName: await _displayNameOf(callerId),
        // Both spellings of the callee, and both spellings of the media mode:
        // the document is read by the call screen, the history list and any
        // older client, and none of them should have to know which one is
        // current.
        CallDocument.fieldReceiverId: calleeId,
        CallDocument.fieldCalleeId: calleeId,
        CallDocument.fieldType: isVideo ? 'video' : 'voice',
        CallDocument.fieldIsVideo: isVideo,
        CallDocument.fieldStatus: CallStatus.ringing.name,
        if (channelName.isNotEmpty)
          CallDocument.fieldChannelName: channelName,
        CallDocument.fieldCallerCandidates: <Map<String, dynamic>>[],
        CallDocument.fieldCalleeCandidates: <Map<String, dynamic>>[],
        CallDocument.fieldCreatedAt: FieldValue.serverTimestamp(),
      });
    } on Object catch (error) {
      debugPrint('createCall failed: $error');
    }
    return doc.id;
  }

  /// Best-effort lookup of a user's display name for the ring screen.
  ///
  /// Returns an empty string rather than throwing: a missing name costs the
  /// callee a "Unknown" label, which is not worth failing a call over.
  Future<String> _displayNameOf(String uid) async {
    if (uid.isEmpty) return '';
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _firestore.collection('users').doc(uid).get();
      return (doc.data()?['name'] as String?)?.trim() ?? '';
    } on Object catch (error) {
      debugPrint('Caller name lookup for $uid failed: $error');
      return '';
    }
  }

  /// Publishes the caller's offer, which is also what starts the peer ringing.
  Future<void> setOffer(String callId, Map<String, dynamic> offer) async {
    await _write(callId, <String, dynamic>{CallDocument.fieldOffer: offer});
  }

  /// Publishes the callee's answer, and marks the call picked up.
  Future<void> setAnswer(String callId, Map<String, dynamic> answer) async {
    await _write(callId, <String, dynamic>{
      CallDocument.fieldAnswer: answer,
      CallDocument.fieldStatus: CallStatus.accepted.name,
      CallDocument.fieldAcceptedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Appends one ICE candidate to the side that produced it.
  ///
  /// Candidates are a list, not a single field: a peer gathers several, they
  /// arrive in any order, and each one has to reach the other device.
  Future<void> addCandidate(
    String callId,
    Map<String, dynamic> candidate, {
    required bool fromCaller,
  }) async {
    final String field = fromCaller
        ? CallDocument.fieldCallerCandidates
        : CallDocument.fieldCalleeCandidates;
    await _write(callId, <String, dynamic>{
      field: FieldValue.arrayUnion(<Map<String, dynamic>>[candidate]),
    });
  }

  /// Moves a call to a new state, stamping the matching timestamp.
  ///
  /// The stamps are written here rather than at each call site so that
  /// "accepted" can never be recorded without an `acceptedAt`, and so the
  /// terminal states all record when they finished — which is what the call log
  /// reads to compute a duration.
  Future<void> setStatus(String callId, CallStatus status) async {
    await _write(callId, <String, dynamic>{
      CallDocument.fieldStatus: status.name,
      if (status == CallStatus.accepted)
        CallDocument.fieldAcceptedAt: FieldValue.serverTimestamp(),
      if (status == CallStatus.ended ||
          status == CallStatus.declined ||
          status == CallStatus.missed)
        CallDocument.fieldEndedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Marks the callee as having picked up.
  Future<void> markAccepted(String callId) =>
      setStatus(callId, CallStatus.accepted);

  /// Marks the call finished, optionally as never answered.
  Future<void> markEnded(String callId, {bool missed = false}) => setStatus(
        callId,
        missed ? CallStatus.missed : CallStatus.ended,
      );

  Future<void> _write(String callId, Map<String, dynamic> values) async {
    if (callId.isEmpty) return;
    try {
      await _firestore.collection(callsCollection).doc(callId).set(
        <String, dynamic>{
          ...values,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object catch (error) {
      debugPrint('call signalling write to $callId failed: $error');
    }
  }

  /// Live view of one call: offer, answer, candidates and status.
  ///
  /// Re-opens the snapshot listener when it errors and forwards the error once
  /// the retries are spent — the same policy as [watchIncoming], for the same
  /// reason.
  ///
  /// It used to use a bare `handleError`, and that was the ring bug again in a
  /// worse place. A handler that returns normally *marks the error handled*, so
  /// the error vanished, the stream ended, and the call service's subscription
  /// simply stopped delivering. A Firestore snapshot stream **closes** when it
  /// errors, so one blip ended signalling for the rest of the call. The symptom
  /// is the worst kind: the phone rings, the callee accepts, and the call then
  /// hangs on "Ringing…" forever because the answer and the ICE candidates never
  /// arrive — with nothing on screen and nothing in the log to say why. Visible
  /// beats silent, so this now retries and then rethrows.
  Stream<CallDocument?> watchCall(String callId) {
    if (callId.isEmpty) return const Stream<CallDocument?>.empty();
    return watchDocuments(
      () => _firestore.collection(callsCollection).doc(callId).snapshots(),
      callId: callId,
    );
  }

  /// How many times a call listener is opened before its failure is reported.
  ///
  /// The same budget as the ring: both are snapshot listeners on the same
  /// collection, so they fail for the same reasons and deserve the same answer.
  static const int callAttempts = ringAttempts;

  /// The retry-and-forward policy [watchCall] applies to a snapshot listener.
  ///
  /// Split out from [watchCall] so the policy is testable without a Firestore
  /// instance — [open] is the only part that needs one, so a test can hand it a
  /// stream that errors.
  @visibleForTesting
  static Stream<CallDocument?> watchDocuments(
    Stream<DocumentSnapshot<Map<String, dynamic>>> Function() open, {
    String callId = '',
    int attempts = callAttempts,
    Duration delay = const Duration(seconds: 2),
  }) {
    return retrying<CallDocument?>(
      () => open().map(CallDocument.fromDoc),
      attempts: attempts,
      delay: delay,
      onError: (Object error, int attempt) => debugPrint(
        'watchCall($callId) failed (attempt $attempt of $attempts): $error',
      ),
    );
  }

  /// Calls currently ringing for [uid].
  ///
  /// Drives the incoming-call UI. Only `ringing` documents are emitted — an
  /// answered or finished call must not resurrect a ring on the callee's device.
  ///
  /// Deliberately does *not* wait for an SDP offer. It used to, which meant the
  /// ring only ever appeared on the WebRTC path: the Agora path has no offer, so
  /// an Agora call would ring out on the caller's phone and never appear on the
  /// callee's. The WebRTC service now waits for the offer itself, inside
  /// `acceptIncoming`, so the ring can be shown the moment the document exists.
  Stream<List<CallDocument>> watchIncoming(String uid) {
    if (uid.isEmpty) return const Stream<List<CallDocument>>.empty();
    return retrying<List<CallDocument>>(
      () => _firestore
          .collection(callsCollection)
          .where(CallDocument.fieldReceiverId, isEqualTo: uid)
          .where(CallDocument.fieldStatus, isEqualTo: CallStatus.ringing.name)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(CallDocument.fromDoc)
              .whereType<CallDocument>()
              .toList(growable: false)),
      onError: (Object error, int attempt) => debugPrint(
        'watchIncoming($uid) failed (attempt $attempt of $ringAttempts): $error',
      ),
    );
  }

  /// How many times a ring listener is opened before its failure is reported.
  static const int ringAttempts = 3;

  /// Re-opens [open] when it errors, up to [attempts] times, then forwards.
  ///
  /// A Firestore snapshot stream **closes** when it errors, so without this a
  /// single transient failure — a moment offline, a dropped connection — would
  /// kill the ring for the rest of the session. Worse, it would do it
  /// *silently*: the symptom of a dead ring listener is a phone that never
  /// rings, which is indistinguishable from an app that is simply broken. That
  /// is the failure this exists to stop, so the error is retried *and*, once the
  /// retries are exhausted, forwarded to the consumer rather than swallowed.
  ///
  /// A permanent cause — a missing composite index, a rules denial — costs
  /// [attempts] quick failures and then surfaces. Visible beats silent.
  @visibleForTesting
  static Stream<T> retrying<T>(
    Stream<T> Function() open, {
    int attempts = ringAttempts,
    Duration delay = const Duration(seconds: 2),
    void Function(Object error, int attempt)? onError,
  }) async* {
    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        // `await for` and not `yield*`: an error from a `yield*` source is
        // forwarded straight to the consumer and the `yield*` expression itself
        // completes normally, so a `catch` around it never fires and the retry
        // would silently never happen. `await for` rethrows it here, where it
        // can be handled.
        await for (final T value in open()) {
          yield value;
        }
        // The source completed on its own; there is nothing to retry.
        return;
      } on Object catch (error) {
        onError?.call(error, attempt);
        if (attempt == attempts) rethrow;
      }
      await Future<void>.delayed(delay);
    }
  }
}
