import glob, os, re

# 1) lib/local/database/*.dart: '../../database/local_database.dart' -> 'local_database.dart'
#    and app_constants/core/models depth: these files currently use '../../../' which resolves to lib/ -> correct for core/.
for p in glob.glob('lib/local/database/*.dart'):
    if p.endswith('local_database.dart'):
        continue
    s = open(p, encoding='utf-8').read()
    s = s.replace("import '../../database/local_database.dart';", "import 'local_database.dart';")
    open(p, 'w', encoding='utf-8').write(s)
    print('fixed db import:', p)

# 2) common_widgets.dart + i_avatar.dart need the theme import
for p in ['lib/core/widgets/common_widgets.dart', 'lib/core/widgets/i_avatar.dart']:
    s = open(p, encoding='utf-8').read()
    if "app_color_scheme.dart" not in s:
        # insert after the last existing import line
        lines = s.split('\n')
        last = max(i for i, l in enumerate(lines) if l.startswith('import '))
        lines.insert(last + 1, "import '../../app/theme/app_color_scheme.dart';")
        s = '\n'.join(lines)
        open(p, 'w', encoding='utf-8').write(s)
        print('added theme import:', p)

# 3) local_settings_repository: `const String box = ...` inside class -> static const
p = 'lib/local/database/local_settings_repository.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("  const String box = AppConstants.boxSettings;", "  static const String box = AppConstants.boxSettings;")
open(p, 'w', encoding='utf-8').write(s)

# 4) i_avatar unnecessary underscores in errorBuilder
p = 'lib/core/widgets/i_avatar.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("errorBuilder: (_, __, ___) => _initialTile(bg, dotSize),", "errorBuilder: (BuildContext ctx, Object err, StackTrace? st) => _initialTile(bg, dotSize),")
open(p, 'w', encoding='utf-8').write(s)

# 5) common_widgets null-aware element info at line ~364
p = 'lib/core/widgets/common_widgets.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("""      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: filled ? Colors.white : tone),
            const SizedBox(width: 3),
          ],""","""      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: filled ? Colors.white : tone),
            const SizedBox(width: 3),
          ],""")
open(p, 'w', encoding='utf-8').write(s)
print("done")
