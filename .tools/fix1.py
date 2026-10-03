p='lib/core/services/media_service.dart'
s=open(p,encoding='utf-8').read()
old = """      final List<XFile> files = fromCamera
          ? <XFile>[
              if (await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 88,
                  ) !=
                  null)
                (await _picker.pickImage(source: ImageSource.camera))!,
            ]
          : await _picker.pickMultiImage(imageQuality: 88);
"""
new = """      final List<XFile> files =
          fromCamera ? await _captureSingle() : await _picker.pickMultiImage(imageQuality: 88);
"""
assert old in s, "pickImages block not found"
s=s.replace(old,new)
old2 = """  /// Single-shot camera capture returning an imported attachment.
  Future<MediaPickResult> capturePhoto() async {"""
new2 = """  Future<List<XFile>> _captureSingle() async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    return shot == null ? <XFile>[] : <XFile>[shot];
  }

  /// Single-shot camera capture returning an imported attachment.
  Future<MediaPickResult> capturePhoto() async {"""
assert old2 in s
s=s.replace(old2,new2)
s=s.replace("FileStorageService.sizeOfFile(","MediaFileHelper.sizeOf(")
old3 = """/// Small helper so media code does not reach into `dart:io` directly.
extension FileStorageServiceSize on FileStorageService {
  static Future<int> sizeOfFile(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return 0;
      return file.length();
    } on FileSystemException {
      return 0;
    }
  }
}"""
new3 = """/// Small helper so media code does not reach into `dart:io` directly.
class MediaFileHelper {
  const MediaFileHelper._();

  static Future<int> sizeOf(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return 0;
      return file.length();
    } on FileSystemException {
      return 0;
    }
  }
}"""
assert old3 in s, "helper block not found"
s=s.replace(old3,new3)
open(p,'w',encoding='utf-8').write(s)
print("media_service fixed")

# local_group_repository: GroupRole import
p2='lib/local/database/local_group_repository.dart'
s2=open(p2,encoding='utf-8').read()
s2=s2.replace("import '../../../core/models/group.dart';","import '../../../core/models/group.dart';")
open(p2,'w',encoding='utf-8').write(s2)
