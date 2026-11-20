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
    python3 tools/cosmetic-calendar/locked_pieces_check.py --lock "Nature:Goal"
                                    # lock one pending piece the owner has now approved:
                                    # finds its drawing code, records the hashes and takes
                                    # it off the "pending" list
    python3 tools/cosmetic-calendar/locked_pieces_check.py --lock-missing
                                    # the same for every catalog piece that is neither
                                    # locked nor pending (ONLY when the owner approved them)

Exit status 1 when any locked piece differs from its recorded hash, or when the
catalog and the lock list disagree: every piece of a collection on sale or
scheduled, and of Roll Along, must be either locked or on the "pending" list
(pieces waiting for the owner's approval).

Each piece lists "anchors": the pieces of code that decide how it looks.
  {"file": F, "decl": REGEX}                      a whole func / var body
  {"file": F, "decl": REGEX, "case": ".name"}     one case of a switch inside that body
  {"file": F, "enum": E, "decl": REGEX, "case": ".name"}   the same, inside `enum E`
  {"file": F, "scope": REGEX, "decl": REGEX, ...}  the same, inside the top-level type(s)
                                                   whose first line matches `scope`
                                                   (every `extension` of it included)
Shared code every trail / pit / boundary depends on is listed under "shared".

How anchors are found (--lock, --lock-missing): for a piece `.id` in slot S, every
switch case that names `.id` inside the code that draws S (the enum's own tables,
its overlay / skin view, PitArt, drawRichTrail), then every member function or
computed property those cases call, followed through to the helpers they call.
Only the CASE BODY is hashed for a switch shared with other pieces, so adding or
changing another piece's case does not flag this one.

Known coarse spots (a change here flags several pieces at once, by design):
  - helper art types are hashed whole: StormArt (all Storm pieces), EmberFloorArt,
    SeededRNG, SkinTimeline / SkinTick (every animated ball);
  - PitArt's small shared helpers (fill, inset, raggedRect, edgeSpots, line), the
    boundary `ring` / `borderTrimSegment` helpers, `trailTapered`, and
    GoalSkin.bandedTargetPreview are hashed whole for every piece that calls them;
  - "Shop tile freeze moments for goals" (CosmeticTileHero) is one shared hash, so
    adding a freeze moment for a new goal flags it; re-record with --update after
    checking that no locked goal's entry changed.
Not covered: display names, tiers and prices, membership lists written as array or
set literals, and gameplay routing outside the drawing types (for example which
screen draws an animated floor overlay). Read those by hand in a review.
"""
import collections
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
            # Comment lines at the end of a case introduce the NEXT case, so a
            # new neighbor (with its own heading comment) is not a change here.
            # Closing braces at the end are dropped too, so the last case of a
            # switch reads the same once another case is added after it.
            found.append(re.sub(r'(?:\s*(?://[^\n]*|\}))+\s*$', '', seg[m.end():]))
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
    if 'scope' in anchor:
        scopes = blocks(src, anchor['scope'])
        if not scopes:
            return None
        src = '\n'.join(scopes)
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
    s = s.replace('[ \\t]*', '').replace('[ t]*', '')
    if 'scope' in anchor:
        m = re.search(r'(struct|enum|extension|class) (\w+)', anchor['scope'])
        s = (m.group(2) if m else '?') + '.' + s
    if 'case' in anchor:
        s += ' [case ' + anchor['case'] + ']'
    return f"{os.path.basename(anchor['file'])}: {s}"



# ---------------------------------------------------------------------------
# Finding the drawing code of a piece (used by --lock / --lock-missing)
# ---------------------------------------------------------------------------
FILES = ['RollAlong/BallSkinView.swift', 'RollAlong/BallSkin.swift',
         'RollAlong/BallGameView.swift', 'RollAlong/Cosmetics.swift']

DECL = re.compile(
    r'^([ \t]*)((?:@\w+(?:\([^)\n]*\))?[ \t]+)*(?:(?:private|fileprivate|internal|public|static|final|'
    r'nonisolated|mutating|override|class)[ \t]+)*)(func|var|let|struct|enum|extension|class)[ \t]+'
    r'([A-Za-z_]\w*)', re.M)

# slot -> list of (file, type name) roots whose members draw that slot
CONTEXT = {
    'Ball': [('RollAlong/BallSkinView.swift', 'BallSkinView'), ('RollAlong/BallSkin.swift', 'BallSkin'),
             ('RollAlong/Cosmetics.swift', 'BallSkin')],
    'Goal': [('RollAlong/Cosmetics.swift', 'GoalSkin'), ('RollAlong/BallGameView.swift', 'GoalSkinView')],
    'Trail': [('RollAlong/Cosmetics.swift', 'TrailColor'), ('RollAlong/Cosmetics.swift', None)],
    'Floor': [('RollAlong/Cosmetics.swift', 'Floor'), ('RollAlong/BallGameView.swift', 'FloorOverlayView'),
              ('RollAlong/BallGameView.swift', 'PaperFloorOverlayView')],
    'Pit': [('RollAlong/Cosmetics.swift', 'Pit'), ('RollAlong/BallGameView.swift', 'PitOverlayView'),
            ('RollAlong/BallGameView.swift', 'PitArt')],
    'Boundary': [('RollAlong/Cosmetics.swift', 'Boundary'), ('RollAlong/BallGameView.swift', 'BoundaryOverlayView')],
}
CONTEXT_ROOTS = {t for v in CONTEXT.values() for _, t in v if t}
# members that say nothing about look or motion
SKIP_DECL = {'displayName', 'tier', 'coinCost', 'contentSummary', 'displaySummary', 'isBundleExclusive',
             'isLockerOnly', 'isCoinPurchasable', 'isIconic', 'rarityLabel', 'isAnimated', 'collectionCaption',
             'accessibilityName', 'sortKey', 'shopCaption', 'category'}
STOP = {'body', 'color', 'colors', 'displayName', 'tier', 'id', 'init', 'size', 'path', 'self', 'Self',
        'TrailMarks', 'TrailFrame', 'pitDepthShade', 'motionClock', 'borderRing', 'PitDepthShade'}
HELPER_TYPE = re.compile(r'(Art|RNG|Clock|Timeline|Tick|Frame|Shade)$')


def match_braces(src):
    """Map index of each `{` to its matching `}` (strings and comments skipped)."""
    out = {}
    stack = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and src[i:i + 2] == '//':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and src[i:i + 2] == '/*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            if src[i:i + 3] == '"""':
                j = src.find('"""', i + 3)
                i = n if j < 0 else j + 3
                continue
            j = i + 1
            while j < n and src[j] != '"' and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            i = j + 1
            continue
        if c == '{':
            stack.append(i)
        elif c == '}':
            if stack:
                out[stack.pop()] = i
        i += 1
    return out


class Index:
    def __init__(self, path, src):
        self.path, self.src = path, src
        braces = match_braces(src)
        decls = []
        for m in DECL.finditer(src):
            kind, name, indent = m.group(3), m.group(4), len(m.group(1).expandtabs(4))
            line_end = src.find('\n', m.end())
            line = src[m.start():line_end]
            start = m.start()
            if kind in ('var', 'let'):
                rest = src[m.end():line_end]
                if '=' in rest.split('{')[0] or '{' not in rest:
                    continue                      # stored property / local binding
                b = src.find('{', m.end())
            else:
                j = m.end()
                if kind == 'func':
                    p = src.find('(', j)
                    depth = 0
                    while p < len(src):
                        if src[p] == '(':
                            depth += 1
                        elif src[p] == ')':
                            depth -= 1
                            if depth == 0:
                                break
                        p += 1
                    j = p
                b = src.find('{', j)
                if b < 0 or b - j > 400:
                    continue
            if b not in braces:
                continue
            decls.append(dict(kind=kind, name=name, indent=indent, start=start, end=braces[b] + 1,
                              first=line.strip()))
        decls.sort(key=lambda d: d['start'])
        stack = []
        for d in decls:
            while stack and stack[-1]['end'] <= d['start']:
                stack.pop()
            d['parent'] = stack[-1] if stack else None
            stack.append(d)
        self.decls = decls
        self.by_name = collections.defaultdict(list)
        for d in decls:
            self.by_name[d['name']].append(d)

    def text(self, d):
        return self.src[d['start']:d['end']]

    def root(self, d):
        while d['parent'] is not None:
            d = d['parent']
        return d

    def is_member(self, d):
        """Top-level, or directly inside a type (not a local function inside a function)."""
        p = d['parent']
        return p is None or p['kind'] in ('struct', 'enum', 'extension', 'class')


def case_bodies(block, name):
    starts = [m.start() for m in re.finditer(r'^[ \t]*(?:case\b|default\s*:)', block, re.M)]
    token = re.compile(r'\.' + re.escape(name) + r'\b')
    found = []
    for a, b in zip(starts, starts[1:] + [len(block)]):
        seg = block[a:b]
        m = re.match(r'[ \t]*case\b(.*?):(?=\s)', seg, re.S)
        if m and token.search(m.group(1)):
            found.append(seg[m.end():])
    return found


def decl_regex(d):
    first = d['first']
    first = re.sub(r'\s*\{\s*$', '', first)
    return '^[ \\t]*' + re.escape(first).replace('\\ ', ' ')


def scope_of(ix, d):
    r = ix.root(d)
    if r is d or r['kind'] not in ('struct', 'enum', 'extension', 'class'):
        return None
    return '^(?:private |fileprivate |final )*' + r['kind'] + ' ' + r['name'] + r'\b'


def derive(indexes, slot, case):
    """Anchors (list of dicts without sha) for one piece."""
    anchors, seen = [], set()

    def add(ix, d, case_name=None):
        key = (ix.path, d['start'], case_name)
        if key in seen:
            return False
        seen.add(key)
        a = {'file': ix.path, 'decl': decl_regex(d)}
        sc = scope_of(ix, d)
        if sc:
            a['scope'] = sc
        if case_name:
            a['case'] = '.' + case_name
        anchors.append(a)
        return True

    def follow(ix, text, home):
        text = re.sub(r'//[^\n]*', '', text)
        for name in set(re.findall(r'\b([A-Za-z_]\w*)\b', text)):
            if name in STOP or name not in ix.by_name:
                continue
            for d in [d for d in ix.by_name[name] if ix.is_member(d)]:
                r = ix.root(d)
                if d['kind'] in ('enum', 'struct'):
                    # helper art types are locked whole (their members are not followed one by one)
                    if (d['parent'] is None and HELPER_TYPE.search(name)
                            and name not in CONTEXT_ROOTS and add(ix, d)):
                        pass
                    continue
                if d['kind'] not in ('func', 'var') or d['name'] in SKIP_DECL:
                    continue
                top_func = d['parent'] is None and d['kind'] == 'func'
                if not (top_func or in_slot_context(ix, d)):
                    continue                    # members of unrelated types / helper types (locked whole)
                if d['kind'] == 'func':
                    if not re.search(r'\b' + re.escape(name) + r'\s*\(', text):
                        continue
                else:
                    if len(name) < 6 or not re.search(r'(?<![.\w])' + re.escape(name) + r'\b(?!\s*[:=(])', text):
                        continue
                body = ix.text(d)
                cb = case_bodies(body, case)
                if cb:
                    if add(ix, d, case):
                        for seg in cb:
                            follow(ix, seg, r)
                elif is_dispatcher(body):
                    continue        # a dispatcher over the enum that does not name this piece
                else:
                    if add(ix, d):
                        follow(ix, body, r)

    def in_slot_context(ix, d):
        r = ix.root(d)
        for f, t in CONTEXT[slot]:
            if f != ix.path:
                continue
            if t is None and (r is d and d['kind'] == 'func'):
                return True
            if t is not None and r['name'] == t:
                return True
        return False

    def is_dispatcher(body):
        return len(re.findall(r'^[ \t]*case \.', body, re.M)) >= 6

    for ix in indexes:
        for d in ix.decls:
            if d['kind'] not in ('func', 'var') or not ix.is_member(d) or d['name'] in SKIP_DECL:
                continue
            if not in_slot_context(ix, d):
                continue
            cb = case_bodies(ix.text(d), case)
            if not cb:
                continue
            if add(ix, d, case):
                for seg in cb:
                    follow(ix, seg, ix.root(d))
    return anchors


def load_indexes(root='.'):
    return [Index(p, open(os.path.join(root, p), encoding='utf-8').read()) for p in FILES]




# ---------------------------------------------------------------------------
# The catalog: which pieces must be locked or pending
# ---------------------------------------------------------------------------
SLOTS = [('balls', 'BallSkin', 'Ball'), ('goals', 'GoalSkin', 'Goal'), ('trails', 'TrailColor', 'Trail'),
         ('floors', 'Floor', 'Floor'), ('pits', 'Pit', 'Pit'), ('boundaries', 'Boundary', 'Boundary')]
COSMETICS = 'RollAlong/Cosmetics.swift'


def catalog(rev=None):
    """[(collection display name, slot label, case id)] for Roll Along and every collection on
    sale or scheduled (active, not seasonal)."""
    cos = source(rev, COSMETICS)
    starters = {}
    for _, enum, _ in SLOTS:
        m = re.search(r'static var starter: ' + enum + r' \{ \.(\w+) \}', cos)
        if m:
            starters[enum] = m.group(1)
    out = []
    if cos.find('static let rollAlong = CosmeticBundle(') >= 0:
        for _, enum, label in SLOTS:
            if enum in starters:
                out.append(('Roll Along', label, starters[enum]))
    i = cos.index('    static let catalogue: [CosmeticBundle] = [')
    j = cos.index('\n    ]\n', i)
    a = cos.find('static let activeIDs: [String] = [')
    if a < 0:
        return out
    a += len('static let activeIDs: [String] = [')
    active = set(re.findall(r'"([^"]+)"', re.sub(r'//[^\n]*', '', cos[a:cos.index(']', a)])))
    for b in re.split(r'\n        CosmeticBundle\(', cos[i:j])[1:]:
        bid = re.search(r'id:\s*"([^"]+)"', b).group(1)
        if bid not in active or 'availableUntil' in b:
            continue
        name = re.search(r'displayName:\s*"([^"]+)"', b).group(1)
        for slot, enum, label in SLOTS:
            m = re.search(r'\b' + slot + r':\s*\[([^\]]*)\]', b)
            for cid in (re.findall(r'\.(\w+)', m.group(1)) if m else []):
                out.append((name, label, cid))
    return out


def display_name(rev, label, cid):
    enum = {l: e for _, e, l in SLOTS}[label]
    if enum == 'BallSkin':
        src = source(rev, 'RollAlong/BallSkin.swift')
        m = re.search(r'\bcase\b[^\n]*\b' + re.escape(cid) + r'\s*=\s*"([^"]*)"', src)
        return m.group(1) if m else cid
    src = source(rev, COSMETICS)
    i = src.index('enum ' + enum + ':')
    j = src.index('var displayName: String {', i)
    k = src.index('\n    }\n', j)
    for cm in re.finditer(r'case ([^:]+):\s*return "([^"]*)"', src[j:k]):
        if cid in re.findall(r'\.(\w+)', cm.group(1)):
            return cm.group(2)
    return cid


def coverage_problems(data, rev):
    problems = []
    try:
        cat = catalog(rev)
    except (ValueError, subprocess.CalledProcessError):
        return [('catalog', COSMETICS, 'could not read the collection catalog at this revision')]
    locked = {(p['collection'], p['slot']): p.get('id') for p in data['pieces']}
    pending = {(p['collection'], p['slot']) for p in data.get('pending', [])}
    seen = set()
    for col, slot, cid in cat:
        seen.add((col, slot))
        if (col, slot) in pending:
            continue
        if (col, slot) not in locked:
            problems.append((f'{slot} {cid} ({col})', 'catalog',
                             'NOT LOCKED: in a collection on sale or scheduled, but neither locked nor pending'))
        elif locked[(col, slot)] != cid:
            problems.append((f'{slot} {cid} ({col})', 'catalog',
                             f"REPLACED: the locked piece here is `{locked[(col, slot)]}`; the catalog now has `{cid}`"))
    for (col, slot), cid in locked.items():
        if (col, slot) not in seen:
            problems.append((f'{slot} {cid} ({col})', 'catalog',
                             'GONE: a locked piece is no longer in its collection'))
    for col, slot in pending:
        if (col, slot) not in seen:
            problems.append((f'{slot} ({col})', 'catalog', 'PENDING entry does not match any catalog slot'))
    return problems


def lock(targets, all_missing=False):
    """Record anchors + hashes for pieces the owner has approved."""
    with open(JSON_PATH, encoding='utf-8') as f:
        data = json.load(f)
    locked = {(p['collection'], p['slot']) for p in data['pieces']}
    pending = {(p['collection'], p['slot']) for p in data.get('pending', [])}
    indexes = load_indexes(ROOT)
    order = {l: n for n, (_, _, l) in enumerate(SLOTS)}
    added = 0
    cat = catalog(None)
    for col, slot, cid in cat:
        key = (col, slot)
        wanted = key in targets or (all_missing and key not in locked and key not in pending)
        if not wanted or key in locked:
            continue
        anchors = derive(indexes, slot, cid)
        bad = [a for a in anchors if anchor_text(None, a) is None]
        if not anchors or bad:
            print(f'COULD NOT LOCK {slot} {cid} ({col}): '
                  + ('no drawing code found' if not anchors else f'{len(bad)} anchor(s) do not resolve: '
                     + '; '.join(label(a) for a in bad)))
            return 1
        for a in anchors:
            a['sha'] = digest(anchor_text(None, a))
        data['pieces'].append({'collection': col, 'slot': slot, 'name': display_name(None, slot, cid),
                               'id': cid, 'anchors': anchors})
        data['pending'] = [p for p in data.get('pending', []) if (p['collection'], p['slot']) != key]
        added += 1
        print(f'locked {slot} {display_name(None, slot, cid)} ({col}): {len(anchors)} anchors')
    cols = []
    for col, _, _ in cat:
        if col not in cols:
            cols.append(col)
    data['pieces'].sort(key=lambda p: (cols.index(p['collection']) if p['collection'] in cols else 999,
                                       order.get(p['slot'], 9)))
    with open(JSON_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write('\n')
    print(f'{added} piece(s) locked; {len(data["pieces"])} locked in all, {len(data.get("pending", []))} pending.')
    return 0


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
    problems += coverage_problems(data, rev)
    if not problems:
        if not quiet:
            pend = data.get('pending', [])
            print(f"OK: all {len(data['pieces'])} locked pieces and {len(data.get('shared', []))} shared helpers "
                  f"match their approved drawing code ({where}).")
            print("    Every piece of Roll Along and of the collections on sale or scheduled is locked"
                  + (f", except {len(pend)} pending the owner's approval: "
                     + '; '.join(f"{p['collection']} {p['slot'].lower()}" for p in pend) + '.' if pend else '.'))
        return 0
    print(f"LOCKED PIECES CHECK FAILED ({where}): {len(problems)} problem(s)")
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
    if '--lock-missing' in args:
        sys.exit(lock(set(), all_missing=True))
    if '--lock' in args:
        col, slot = args[args.index('--lock') + 1].rsplit(':', 1)
        sys.exit(lock({(col.strip(), slot.strip().capitalize())}))
    sys.exit(run(rev=rev, update='--update' in args))
