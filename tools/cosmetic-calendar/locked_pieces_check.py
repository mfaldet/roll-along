#!/usr/bin/env python3
"""Guard for owner-approved ("locked") cosmetic pieces.

A locked piece must never change its look or motion unless the owner says so
(docs/cosmetics/quality-standard.md, "Locked pieces").  This script hashes the
drawing code of every locked piece and compares it with the hashes recorded in
tools/cosmetic-calendar/locked_pieces.json.

    python3 tools/cosmetic-calendar/locked_pieces_check.py            # check the working tree
    python3 tools/cosmetic-calendar/locked_pieces_check.py --rev REV  # check a git revision
    python3 tools/cosmetic-calendar/locked_pieces_check.py --update   # re-record hashes
                                                                      # (ONLY after the owner
                                                                      # approves a change)

Exit status 1 when any locked piece differs from its recorded hash.

Each piece lists "anchors": the pieces of code that decide how it looks.
  {"file": F, "decl": REGEX}                      a whole func / var body
  {"file": F, "decl": REGEX, "case": ".name"}     one case of a switch inside that body
  {"file": F, "enum": E, "decl": REGEX, "case": ".name"}   the same, inside `enum E`
Shared code every trail / pit / boundary depends on is listed under "shared".
"""
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JSON_PATH = os.path.join(ROOT, 'tools', 'cosmetic-calendar', 'locked_pieces.json')


def source(rev, path, cache={}):
    key = (rev, path)
    if key not in cache:
        if rev is None:
            with open(os.path.join(ROOT, path), encoding='utf-8') as f:
                cache[key] = f.read()
        else:
            cache[key] = subprocess.run(['git', '-C', ROOT, 'show', f'{rev}:{path}'],
                                        capture_output=True, text=True, check=True).stdout
    return cache[key]


def block_at(src, start):
    """The text from `start` through the brace that closes the first `{` after it."""
    i = src.index('{', start)
    depth = 0
    j = i
    in_string = False
    while j < len(src):
        c = src[j]
        if in_string:
            if c == '\\':
                j += 2
                continue
            if c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c == '/' and src[j:j + 2] == '//':
                j = src.index('\n', j)
                continue
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return src[start:j + 1]
        j += 1
    return src[start:]


def blocks(src, pattern):
    out = []
    for m in re.finditer(pattern, src, re.M):
        line_start = src.rfind('\n', 0, m.start()) + 1
        out.append(block_at(src, line_start))
    return out


def case_body(block, name):
    """Body of the switch case whose label names `.name` (label excluded, so adding
    another case to a shared label is not reported as a change to this piece)."""
    starts = [m.start() for m in re.finditer(r'^[ \t]*(?:case\b|default\s*:)', block, re.M)]
    token = re.compile(r'\.' + re.escape(name.lstrip('.')) + r'\b')
    found = []
    for a, b in zip(starts, starts[1:] + [len(block)]):
        seg = block[a:b]
        m = re.match(r'[ \t]*case\b(.*?):(?=\s)', seg, re.S)
        if not m:
            continue
        if token.search(m.group(1)):
            found.append(seg[m.end():])
    return found


def normalize(text):
    # Whitespace-insensitive: reindenting or re-wrapping is not a change of look.
    return re.sub(r'\s+', ' ', text).strip()


def anchor_text(rev, anchor):
    src = source(rev, anchor['file'])
    if 'enum' in anchor:
        enums = blocks(src, r'^enum ' + re.escape(anchor['enum']) + r'\b')
        if len(enums) != 1:
            return None
        src = enums[0]
    found = blocks(src, anchor['decl'])
    if not found:
        return None
    if 'case' in anchor:
        bodies = []
        for blk in found:
            bodies += case_body(blk, anchor['case'])
        if not bodies:
            return None
        found = bodies
    return '\n'.join(normalize(x) for x in found)


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def label(anchor):
    s = anchor['decl']
    s = re.sub(r'\\(.)', r'\1', s).replace('$', '').replace('^', '')
    s = re.sub(r'\s*\{\s*$', '', s).strip()
    if 'enum' in anchor:
        s = anchor['enum'] + '.' + s
    if 'case' in anchor:
        s += ' [case ' + anchor['case'] + ']'
    return f"{os.path.basename(anchor['file'])}: {s}"


def run(rev=None, update=False, quiet=False):
    with open(JSON_PATH, encoding='utf-8') as f:
        data = json.load(f)
    problems = []
    entries = [('shared', s) for s in data.get('shared', [])] + [('piece', p) for p in data['pieces']]
    for kind, entry in entries:
        who = entry['name'] if kind == 'shared' else f"{entry['slot']} {entry['name']} ({entry['collection']})"
        for anchor in entry['anchors']:
            text = anchor_text(rev, anchor)
            if text is None:
                problems.append((who, label(anchor), 'MISSING: the code this piece is drawn by was not found'))
                continue
            h = digest(text)
            if update:
                anchor['sha'] = h
            elif anchor.get('sha') != h:
                problems.append((who, label(anchor), f"CHANGED: recorded {anchor.get('sha')}, now {h}"))
    if update:
        with open(JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
            f.write('\n')
        print(f"Recorded {sum(len(e['anchors']) for _, e in entries)} hashes for "
              f"{len(data['pieces'])} locked pieces and {len(data.get('shared', []))} shared helpers.")
        return 0
    where = 'working tree' if rev is None else rev
    if not problems:
        if not quiet:
            print(f"OK: all {len(data['pieces'])} locked pieces and {len(data.get('shared', []))} shared helpers "
                  f"match their approved drawing code ({where}).")
        return 0
    print(f"LOCKED PIECES CHANGED ({where}): {len(problems)} anchor(s)")
    for who, what, why in problems:
        print(f"  {who}\n      {what}\n      {why}")
    print("A locked piece may only change when the owner asks for it. Restore the code, or, after the "
          "owner approves the new look, run this script with --update.")
    return 1


if __name__ == '__main__':
    args = sys.argv[1:]
    rev = None
    if '--rev' in args:
        rev = args[args.index('--rev') + 1]
    sys.exit(run(rev=rev, update='--update' in args))
