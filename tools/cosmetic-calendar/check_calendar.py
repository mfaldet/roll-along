#!/usr/bin/env python3
"""Check that the app's built-in release calendar matches database step 11.

Run from the repository root:

    python3 tools/cosmetic-calendar/check_calendar.py

It reads the built-in dates in RollAlong/Cosmetics.swift (CosmeticSchedule
and the seasonal windows in the catalogue) and the seed rows in
docs/cosmetics/cosmetic-calendar.sql, and prints every difference.  Exit code
0 means they agree.  Read-only; touches no database.
"""
import re
import sys
from datetime import date

SWIFT = "RollAlong/Cosmetics.swift"
SQL = "docs/cosmetics/cosmetic-calendar.sql"


def swift_calendar():
    src = open(SWIFT, encoding="utf-8").read()
    permanent = {}
    block = src[src.index("static let drops:"):src.index("static let looseSlotIDs")]
    for y, m, d, ids in re.findall(r"CalendarDay\((\d+),\s*(\d+),\s*(\d+)\),\s*\[([^\]]*)\]", block):
        for cid in re.findall(r'"([^"]+)"', ids):
            permanent[cid] = date(int(y), int(m), int(d))
    for cid, y, m, d in re.findall(r'map\["(_loose-\d)"\] = CalendarDay\((\d+), (\d+), (\d+)\)', src):
        permanent[cid] = date(int(y), int(m), int(d))

    # Per-year rows for moving holidays.
    rows = {}
    block = src[src.index("static let builtInSeasonalWindows"):src.index("// MARK: Effective dates")]
    for cid, body in re.findall(r'"([^"]+)": \[(.*?)\n        \]', block, re.S):
        for yr, a, b in re.findall(
                r"(\d{4}): CalendarWindow\(from: CalendarDay\(([^)]*)\), until: CalendarDay\(([^)]*)\)\)", body):
            fa = date(*map(int, a.split(",")))
            ub = date(*map(int, b.split(",")))
            rows[(cid, int(yr))] = (fa, ub)

    # Yearly windows from the catalogue entries.
    base = {}
    for chunk in src.split("CosmeticBundle(\n")[1:]:
        m = re.search(
            r'^\s*id:\s+"([^"]+)",.*?availableFrom:\s+CosmeticBundle\.date\((\d+),\s*(\d+),\s*(\d+)\),\s*'
            r'availableUntil:\s+CosmeticBundle\.date\((\d+),\s*(\d+),\s*(\d+)\)', chunk, re.S)
        if not m:
            continue
        cid, fy, fm, fd, uy, um, ud = m.groups()
        base[cid] = (date(int(fy), int(fm), int(fd)), date(int(uy), int(um), int(ud)))

    def window(cid, year):
        if (cid, year) in rows:
            return rows[(cid, year)]
        f, u = base[cid]
        delta = year - f.year
        return (f.replace(year=f.year + delta), u.replace(year=u.year + delta))

    return permanent, base, window


def sql_calendar():
    src = open(SQL, encoding="utf-8").read()
    perm, seas = {}, {}
    for cid, start, end in re.findall(
            r"\('([^']+)', date '(\d{4}-\d\d-\d\d)', (null|date '\d{4}-\d\d-\d\d')", src):
        s = date.fromisoformat(start)
        if end == "null":
            perm[cid] = s
        else:
            seas[(cid, s.year)] = (s, date.fromisoformat(end[6:16]))
    return perm, seas


def main():
    problems = []
    app_perm, base, window = swift_calendar()
    db_perm, db_seas = sql_calendar()
    if app_perm != db_perm:
        for cid in sorted(set(app_perm) | set(db_perm)):
            if app_perm.get(cid) != db_perm.get(cid):
                problems.append(f"permanent {cid}: app {app_perm.get(cid)} vs sql {db_perm.get(cid)}")
    for (cid, year), w in sorted(db_seas.items()):
        if cid not in base:
            problems.append(f"seasonal {cid} is in the SQL but not a seasonal collection in the app")
            continue
        if window(cid, year) != w:
            problems.append(f"seasonal {cid} {year}: app {window(cid, year)} vs sql {w}")
    missing = set(base) - {cid for cid, _ in db_seas}
    for cid in sorted(missing):
        problems.append(f"seasonal {cid} has no SQL rows")
    print(f"permanent: {len(app_perm)} in app, {len(db_perm)} in SQL; seasonal SQL rows: {len(db_seas)}; "
          f"seasonal collections: {len(base)}")
    for p in problems:
        print("MISMATCH", p)
    print("OK: built-in calendar matches step 11" if not problems else f"{len(problems)} mismatch(es)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
