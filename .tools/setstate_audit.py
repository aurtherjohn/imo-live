"""Audit for `setState()` reached across an async gap without a mounted guard.

`use_build_context_synchronously` catches BuildContext misuse but says nothing
about calling setState() on a disposed State. This walks each StatefulWidget's
methods and flags a setState() that is preceded by an `await` or a Timer
callback with no `mounted` check in between.
"""

import pathlib
import re

STATE_CLASS = re.compile(r'class\s+(\w+)\s+extends\s+(?:Consumer)?State<')

findings = []

for path in sorted(pathlib.Path('lib').rglob('*.dart')):
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()

    for idx, line in enumerate(lines):
        if 'setState(' not in line:
            continue

        # Walk backwards to the start of the enclosing method, stopping early
        # once we hit a mounted guard (which makes the call safe).
        # The guard is often on the very same line: `if (mounted) setState(...)`.
        guarded = 'mounted' in line
        saw_async_gap = False
        for back in range(idx - 1, max(-1, idx - 45), -1) if not guarded else ():
            text = lines[back]
            stripped = text.strip()

            if 'mounted' in stripped and ('if' in stripped or 'return' in stripped):
                guarded = True
                break

            # A new method/closure boundary means we have left this scope.
            if re.match(r'^(Future|void|Widget|@override|class|})', stripped):
                break

            if re.search(r'\bawait\b', stripped) or 'Timer(' in stripped:
                saw_async_gap = True
                break

        if saw_async_gap and not guarded:
            findings.append((str(path), idx + 1, line.strip()))

print('=' * 74)
if findings:
    print('setState() AFTER ASYNC GAP WITHOUT A mounted CHECK:')
    for f, ln, code in findings:
        print(f'  {f}:{ln}\n      {code}')
else:
    print('OK: every setState() that follows an await/Timer is guarded by mounted')
print('=' * 74)
