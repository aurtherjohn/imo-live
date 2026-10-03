"""Static lifecycle audit for the Imo LIVE Flutter app.

Flags any declared controller / timer / stream subscription that never has a
matching dispose() / cancel() call in the same file, plus fire-and-forget
`.listen()` calls that cannot be cancelled.
"""

import pathlib
import re

CTRL = (
    r'(?:TextEditingController|ScrollController|AnimationController|'
    r'PageController|TabController|FocusNode|TransformationController|'
    r'ValueNotifier|StreamController)'
)

DECL = re.compile(
    r'(?:late\s+final\s+|late\s+|final\s+|const\s+)?'
    r'(?:' + CTRL + r'|Timer|StreamSubscription)\??\s*'
    r'(?:<[^>]*>)?\s*(\w+)\s*[;=]'
)
ASSIGN = re.compile(r'\b(\w+)\s*=\s*(?:' + CTRL + r'|Timer|StreamSubscription)\b')
SKIP = {'dispose', 'build', 'initState', 'context', 'widget', 'state', 'key', 'super', 'main'}

leaks = []
listens = []

for path in sorted(pathlib.Path('lib').rglob('*.dart')):
    src = path.read_text(encoding='utf-8', errors='replace')

    names = set()
    for m in DECL.finditer(src):
        if m.group(1) not in SKIP:
            names.add(m.group(1))
    for m in ASSIGN.finditer(src):
        if m.group(1) not in SKIP:
            names.add(m.group(1))

    undisposed = [
        n for n in sorted(names)
        # A name injected via `required this.x` / `this.x` is a widget field
        # owned by the *parent* widget, which is responsible for disposing it.
        if not re.search(r'\bthis\.' + re.escape(n) + r'\b', src)
        and not re.search(
            r'\b' + re.escape(n) + r'\??\.(dispose|cancel|close)\s*\(', src
        )
    ]
    if undisposed:
        leaks.append((str(path), undisposed))

    # Fire-and-forget listen() where the result is not stored in a field.
    for m in re.finditer(r'^(\s*)([^=\n;]*?)\.listen\(', src, re.MULTILINE):
        lhs = m.group(2).strip()
        if lhs.endswith('.') or lhs == '':
            continue
        if not re.match(r'^[\w.]+$', lhs):
            continue
        line = src[:m.start()].count('\n') + 1
        listens.append((str(path), line, lhs))

print('=' * 72)
if leaks:
    print('POTENTIAL LIFECYCLE LEAKS (declared, never disposed):')
    for f, n in leaks:
        print(f'  {f}\n      -> {", ".join(n)}')
else:
    print('OK: every declared controller/timer/subscription is disposed or cancelled')

print('=' * 72)
if listens:
    print('UN-STORED .listen() CALLS (cannot be cancelled):')
    for f, line, lhs in listens:
        print(f'  {f}:{line}  <- {lhs}.listen(...)')
else:
    print('OK: no un-stored .listen() calls')
print('=' * 72)
