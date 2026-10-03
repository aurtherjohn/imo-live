import re

def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            print(f"!! NOT FOUND in {path}: {old[:70]!r}")
            continue
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)
    print("patched", path)

# ---- app_theme.dart
edit('lib/app/theme/app_theme.dart', [
    ("import 'app_tokens.dart';", "import 'app_color_scheme.dart';\nimport 'app_tokens.dart';"),
    ("        showDragHandle: false,\n        constraintEnd: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),\n", "        showDragHandle: false,\n"),
    ("          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),\n", ""),
    ("      pageTransitionsTheme: const PageTransitionsTheme(\n        builders: <TargetPlatform, PageTransitionsBuilder>{\n          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),\n          \n        },\n      ),", "      pageTransitionsTheme: const PageTransitionsTheme(\n        builders: <TargetPlatform, PageTransitionsBuilder>{\n          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),\n        },\n      ),"),
])

# ---- app_color_scheme unnecessary const
edit('lib/app/theme/app_color_scheme.dart', [
    ("    overlay: const Color(0x99000000),", "    overlay: Color(0x99000000),"),
    ("    overlay: const Color(0x66000000),", "    overlay: Color(0x66000000),"),
])

# ---- audio_location_service: geolocator openMapsUrl + amplitude type + formals
edit('lib/core/services/audio_location_service.dart', [
    ("""  LocationService({PermissionService permissions = const PermissionService()})
      : _permissions = permissions;

  final PermissionService _permissions;""",
     """  LocationService({this.permissions = const PermissionService()});

  final PermissionService permissions;"""),
    ("""  /// Opens the platform map application for a coordinate pair.
  Future<bool> openInMaps(double latitude, double longitude) async {
    try {
      return await Geolocator.openMapsUrl(
        latitude: latitude,
        longitude: longitude,
      ).then((_) => true).catchError((Object _) => false);
    } on Exception {
      return false;
    }
  }""",
     """  /// Opens the platform map application for a coordinate pair.
  ///
  /// Uses `url_launcher` with a geo URI so no map SDK is required. The
  /// [MapProviderConfig] below is the integration point for a real map.
  Future<bool> openInMaps(double latitude, double longitude) async {
    final Uri uri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude');
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      final Uri web = Uri.parse(
        'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=17/$latitude/$longitude',
      );
      return launchUrl(web, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }"""),
    ("import 'package:record/record.dart';", "import 'package:record/record.dart';\nimport 'package:url_launcher/url_launcher.dart';"),
    ("""  AudioRecorderService({
    AudioRecorder? recorder,
    FileStorageService? storage,
    PermissionService permissions = const PermissionService(),
  })  : _recorder = recorder ?? AudioRecorder(),
        _storage = storage ?? FileStorageService(),
        _permissions = permissions;""",
     """  AudioRecorderService({
    AudioRecorder? recorder,
    FileStorageService? storage,
    this.permissions = const PermissionService(),
  })  : _recorder = recorder ?? AudioRecorder(),
        _storage = storage ?? FileStorageService();"""),
    ("  final PermissionService _permissions;", "  final PermissionService permissions;"),
    ("await _permissions.request(AppPermission.microphone)", "await permissions.request(AppPermission.microphone)"),
    ("""        final double? amplitude = await _recorder.getAmplitude();
        if (amplitude != null) {
          final double normalized =
              ((amplitude + 60) / 60).clamp(0.0, 1.0).toDouble();
          if (!_amplitude.isClosed) {
            _amplitude.add(<double>[normalized]);
          }
        }""",
     """        final Amplitude amplitude = await _recorder.getAmplitude();
        final double normalized =
            ((amplitude.current + 60) / 60).clamp(0.0, 1.0).toDouble();
        if (!_amplitude.isClosed) {
          _amplitude.add(<double>[normalized]);
        }"""),
])

# ---- contact_service: flutter_contacts API surface
edit('lib/core/services/contact_service.dart', [
    ("  const DeviceContactService({this.permissions = const PermissionService()});",
     "  const DeviceContactService({this.permissions = const PermissionService()});"),
    ("""      final fc.Contact contact = fc.Contact(
        name: fc.Name(first: firstName, last: lastName),
      );
      if (phone != null && phone.trim().isNotEmpty) {
        contact.phones = <fc.Phone>[fc.Phone(number: phone.trim())];
      }
      await fc.FlutterContacts.insert(contact);
      return true;""",
     """      final fc.Contact contact = fc.Contact(
        name: fc.Name(first: firstName, last: lastName),
      );
      if (phone != null && phone.trim().isNotEmpty) {
        contact.phones = <fc.Phone>[fc.Phone(phone.trim())];
      }
      await fc.FlutterContacts.insert(contact);
      return true;"""),
])

# ---- file_service: file_picker await + share_plus API
edit('lib/core/services/file_service.dart', [
    ("      final FilePickerResult? result = await FilePicker.platform.pickFiles(",
     "      final FilePickerResult? result = await FilePicker.platform.pickFiles("),
    ("""      final FilePickerResult? result = FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return <Attachment>[];
      return _import(result, AppConstants.dirDocuments, MessageType.document);""",
     """      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return <Attachment>[];
      return _import(result, AppConstants.dirDocuments, MessageType.document);"""),
    ("""      final FilePickerResult? result = FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.audio,
      );
      if (result == null || result.files.isEmpty) return <Attachment>[];
      return _import(result, AppConstants.dirAudio, MessageType.audio);""",
     """      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.audio,
      );
      if (result == null || result.files.isEmpty) return <Attachment>[];
      return _import(result, AppConstants.dirAudio, MessageType.audio);"""),
    ("""    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
    } on Exception {""",
     """    try {
      await Share.share(text, subject: subject);
    } on Exception {"""),
    ("""      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(path)],
          text: text,
        ),
      );""",
     """      await Share.shareXFiles(<XFile>[XFile(path)], text: text);"""),
])

# ---- media_service: permissions formal
edit('lib/core/services/media_service.dart', [
    ("""    FileStorageService? storage,
    PermissionService permissions = const PermissionService(),
  })  : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FileStorageService(),
        _permissions = permissions;

  final ImagePicker _picker;
  final FileStorageService _storage;
  final PermissionService _permissions;""",
     """    FileStorageService? storage,
    this.permissions = const PermissionService(),
  })  : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FileStorageService();

  final ImagePicker _picker;
  final FileStorageService _storage;
  final PermissionService permissions;"""),
    ("await _permissions.request(AppPermission.camera)", "await permissions.request(AppPermission.camera)"),
    ("await _permissions.request(\n      fromCamera ? AppPermission.camera : AppPermission.videos,\n    )", "await permissions.request(\n      fromCamera ? AppPermission.camera : AppPermission.videos,\n    )"),
])

# ---- notification_service: zonedSchedule args
edit('lib/core/services/notification_service.dart', [
    ("TZDateTime.from(at, tz.local)", "tz.TZDateTime.from(at, tz.local)"),
    ("""        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,""",
     """        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,"""),
])

# ---- common_widgets / i_avatar unused imports
edit('lib/core/widgets/common_widgets.dart', [
    ("import 'i_avatar.dart';\n", ""),
])
edit('lib/local/database/local_chat_repository.dart', [
    ("import '../../../core/models/message_parts.dart';\n", ""),
])
print("ALL PATCHED")
