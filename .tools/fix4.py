def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            print(f"!! NOT FOUND in {path}: {old[:60]!r}")
            continue
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

# audio_location: remaining _permissions refs
edit('lib/core/services/audio_location_service.dart', [
    ("final PermissionResult permission =\n          await _permissions.request(AppPermission.location);",
     "final PermissionResult permission =\n          await permissions.request(AppPermission.location);"),
    ("""      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }""",
     """      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }"""),
    ("      return launchUrl(web, mode: LaunchMode.externalApplication);",
     "      return await launchUrl(web, mode: LaunchMode.externalApplication);"),
])

# connectivity: await a sync-ish return
edit('lib/core/services/connectivity_service.dart', [
    ("    return _status;", "    return _status;"),
])

# contact_service: insert API
edit('lib/core/services/contact_service.dart', [
    ("await fc.FlutterContacts.insert(contact);", "await fc.FlutterContacts.create(contact);"),
])

# file_service: permission formal + await
edit('lib/core/services/file_service.dart', [
    ("""  FileService({
    FileStorageService? storage,
    PermissionService permissions = const PermissionService(),
  })  : _storage = storage ?? FileStorageService(),
        _permissions = permissions;

  final FileStorageService _storage;
  final PermissionService _permissions;""",
     """  FileService({
    FileStorageService? storage,
    this.permissions = const PermissionService(),
  }) : _storage = storage ?? FileStorageService();

  final FileStorageService _storage;
  final PermissionService permissions;"""),
    ("await _permissions.request(AppPermission.audio)", "await permissions.request(AppPermission.audio)"),
    ("      return _import(result, AppConstants.dirDocuments, MessageType.document);",
     "      return await _import(result, AppConstants.dirDocuments, MessageType.document);"),
    ("      return _import(result, AppConstants.dirAudio, MessageType.audio);",
     "      return await _import(result, AppConstants.dirAudio, MessageType.audio);"),
])

# media_service: last unawaited
edit('lib/core/services/media_service.dart', [
    ("      return MediaPickResult(attachments: attachments);", "      return MediaPickResult(attachments: attachments);"),
])

# i_avatar unused theme import
edit('lib/core/widgets/i_avatar.dart', [
    ("import '../../app/theme/app_color_scheme.dart';\n", ""),
])

# common_widgets null-aware element
s = open('lib/core/widgets/common_widgets.dart', encoding='utf-8').read()
s = s.replace("""        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: filled ? Colors.white : tone),
            const SizedBox(width: 3),
          ],
          Text(
            label,""","""        children: <Widget>[
          ?icon == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 11, color: filled ? Colors.white : tone),
                    const SizedBox(width: 3),
                  ],
                ),
          Text(
            label,""")
open('lib/core/widgets/common_widgets.dart','w',encoding='utf-8').write(s)
print("done")
