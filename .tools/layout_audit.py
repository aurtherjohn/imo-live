"""Heuristic scan for RenderFlex overflow risk and fire-and-forget futures.

Overflow: a `Row`/`Column` child that is a bare `Text` (or a `Row` inside a
`Row`) with no `Expanded`/`Flexible` wrapper and no `overflow:`/`maxLines:`
handling will overflow once the text is long or the user scales fonts up.

Unawaited: an `async` helper invoked in a statement position inside a non-async
callback, where the returned Future is discarded.
"""

import pathlib
import re

print('=' * 74)
print('OVERFLOW RISK: bare Text directly inside a Row (no Expanded/Flexible)')
print('=' * 74)

overflow_hits = 0
for path in sorted(pathlib.Path('lib').rglob('*.dart')):
    src = path.read_text(encoding='utf-8', errors='replace')
    lines = src.splitlines()

    # Locate each `Row(` and inspect its immediate child list for bare Text.
    for m in re.finditer(r'\bRow\s*\(', src):
        start_line = src[:m.start()].count('\n')
        depth = 0
        block = []
        for i in range(start_line, min(len(lines), start_line + 60)):
            block.append(lines[i])
            depth += lines[i].count('(') - lines[i].count(')')
            if depth <= 0 and i > start_line:
                break
        text = '\n'.join(block)
        has_expandable = 'Expanded(' in text or 'Flexible(' in text
        has_bare_text = re.search(r'children:\s*<Widget>\[[\s\S]*?Text\(', text)
        if has_bare_text and not has_expandable:
            overflow_hits += 1
            print(f'  {path}:{start_line + 1}')

if not overflow_hits:
    print('  (none)')
print()

print('=' * 74)
print('DISCARDED FUTURES: async helper called in statement position')
print('=' * 74)

ASYNC_HELPERS = re.compile(r'(?:Future<[^>]*>|Future<void>)\s+(_\w+)\s*\(')
discarded = 0
for path in sorted(pathlib.Path('lib').rglob('*.dart')):
    src = path.read_text(encoding='utf-8', errors='replace')
    helpers = set(ASYNC_HELPERS.findall(src))
    if not helpers:
        continue
    for h in sorted(helpers):
        for m in re.finditer(r'(?<![\w.])' + re.escape(h) + r'\s*\(', src):
            line_start = src.rfind('\n', 0, m.start()) + 1
            line = src[line_start:src.find('\n', m.start())]
            stripped = line.strip()
            if stripped.startswith(('await ', 'return ', 'unawaited(', '//', '///')):
                continue
            if re.search(r'=\s*' + re.escape(h) + r'\s*\(', line):
                continue
            # Bare statement call -> the Future is discarded.
            if re.match(r'^' + re.escape(h) + r'\s*\(', stripped):
                ln = src[:m.start()].count('\n') + 1
                print(f'  {path}:{ln}  -> {stripped}')
                discarded += 1

if not discarded:
    print('  (none)')
print('=' * 74)
