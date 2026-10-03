"""Insert a `dispose()` into every Hive repository that owns a StreamController.

Each replacement is verified to match exactly once, so a silent no-op (or a
duplicate insertion) fails loudly instead of corrupting the file.
"""

import pathlib
import sys

DISPOSE = """  /// Closes the change-notification stream.
  ///
  /// Wired to `ref.onDispose` in the owning provider, so the controller is
  /// released when the [ProviderContainer] is torn down instead of leaking.
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
"""

# (file, unique text that ends the class body just before its closing brace)
EDITS = [
    (
        'lib/local/database/local_chat_repository.dart',
        '        (c) => c.copyWith(unreadCount: c.isMuted ? c.unreadCount : c.unreadCount + 1),\n      );\n',
    ),
    (
        'lib/local/database/local_contact_repository.dart',
        '      ..sort((a, b) => a.sortedKey.compareTo(b.sortedKey));\n  }\n',
    ),
    (
        'lib/local/database/local_group_repository.dart',
        '            g.description.toLowerCase().contains(q))\n        .toList();\n  }\n',
    ),
    (
        'lib/local/database/local_group_repository.dart',
        '    return _cache[index];\n  }\n',
    ),
    (
        'lib/local/database/local_group_repository.dart',
        '            c.category.toLowerCase().contains(q))\n        .toList();\n  }\n',
    ),
    (
        'lib/local/database/local_status_repository.dart',
        '            s.caption.toLowerCase().contains(q))\n        .toList();\n  }\n',
    ),
    (
        'lib/local/database/local_status_repository.dart',
        '    return all.where((c) => c.contactName.toLowerCase().contains(q)).toList();\n  }\n',
    ),
]

ok = True
for path_str, anchor in EDITS:
    path = pathlib.Path(path_str)
    src = path.read_text(encoding='utf-8')
    count = src.count(anchor)
    if count != 1:
        print(f'FAIL {path_str}: anchor matched {count} times (expected 1)')
        ok = False
        continue
    if 'Future<void> dispose() async' in src.split(anchor)[0][-800:]:
        print(f'SKIP {path_str}: dispose already present near anchor')
        continue
    # Insert the dispose method after the last method, before the class brace.
    # The anchor's own trailing "  }\n" closes the last method; the class's
    # closing brace stays untouched right after the inserted text.
    src = src.replace(anchor, anchor + '\n' + DISPOSE, 1)
    path.write_text(src, encoding='utf-8')
    print(f'OK   {path_str}')

sys.exit(0 if ok else 1)
