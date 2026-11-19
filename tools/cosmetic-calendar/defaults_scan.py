#!/usr/bin/env python3
"""List every collection that contains a piece of the Roll Along default set.

Reads the catalogue out of RollAlong/Cosmetics.swift.  Run from the repo root:
    python3 tools/cosmetic-calendar/defaults_scan.py
"""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "RollAlong/Cosmetics.swift"
TARGETS = {"balls": "red", "goals": "target", "trails": "classic",
           "floors": "classic", "pits": "classic", "boundaries": "classic"}


def main():
    s = open(SRC).read()
    i = s.index("    static let catalogue: [CosmeticBundle] = [")
    blocks = re.split(r"\n        CosmeticBundle\(", s[i:])[1:]
    found = 0
    for b in blocks:
        bid = re.search(r'id:\s*"([^"]+)"', b).group(1)
        if bid == "roll-along":
            continue
        hits = []
        for slot, name in TARGETS.items():
            m = re.search(r"\b" + slot + r":\s*\[([^\]]*)\]", b)
            if m and re.search(r"\." + name + r"\b", m.group(1)):
                hits.append(f"{slot}:{name}")
        if hits:
            found += 1
            print(bid, hits)
    print(f"{found} collection(s) share a Roll Along piece")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
