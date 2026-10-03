def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            print(f"!! NOT FOUND in {path}: {old[:60]!r}")
            continue
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

edit('lib/core/services/contact_service.dart', [
    ("await fc.FlutterContacts.create(contact);", "await fc.FlutterContacts.insertContact(contact);"),
])

# connectivity: return inside try without await
edit('lib/core/services/connectivity_service.dart', [
    ("""  Future<bool> openSettings() => openAppSettings();""",
     """  Future<bool> openSettings() => openAppSettings();"""),
])

# media_service: await the import loop return
s = open('lib/core/services/media_service.dart', encoding='utf-8').read()
s = s.replace("""      final List<Attachment> attachments = <Attachment>[];
      for (final XFile file in files.take(multiple ? 20 : 1)) {""",
"""      final List<Attachment> attachments = <Attachment>[];
      for (final XFile file in files.take(multiple ? 20 : 1)) {""")
open('lib/core/services/media_service.dart','w',encoding='utf-8').write(s)
print("done")
