#!/usr/bin/env python3
"""Print every collection's slot coverage, derived rarity and full price.

Mirrors `CosmeticBundle.rarity` (>= 2 legendary members -> Legendary,
>= 2 epic-or-legendary -> Rare, else Standard) and `fullPrice()` by reading
the tier switches and the catalogue straight out of RollAlong/Cosmetics.swift.
Run from the repository root:  python3 tools/cosmetic-calendar/bundle_rarity.py
(set SRC=<path> to read another copy of Cosmetics.swift).
"""
import os
import re
import sys
from collections import Counter

SRC = os.environ.get("SRC", "RollAlong/Cosmetics.swift")
SLOTS = {"balls": "BallSkin", "goals": "GoalSkin", "trails": "TrailColor",
         "floors": "Floor", "pits": "Pit", "boundaries": "Boundary",
         "music": "MusicTrack"}
# Music is not offered in 1.0 (CosmeticFeatures.musicEnabled = false), so it
# adds nothing to a collection's price and is not a missing slot.  Rarity
# still counts it, so no collection changes band (and the Standard gift pool
# stays the same).  Set WITH_MUSIC=1 to price music in as before.
MUSIC_OFFERED = bool(os.environ.get("WITH_MUSIC"))
# Each slot's default item: owned by everyone, so it adds nothing to a
# collection's price (CosmeticBundle.listPrice).
STARTER = {"BallSkin": "red", "GoalSkin": "target", "TrailColor": "classic",
           "Floor": "classic", "Pit": "classic", "Boundary": "classic",
           "MusicTrack": "none"}
PRICE = {"starter": 0, "standard": 750, "rare": 1000, "premium": 1250,
         "exclusive": 1500}


def tier_tables(s):
    tiers = {}
    for m in re.finditer(r"var tier: CosmeticTier \{", s):
        heads = list(re.finditer(r"\n(?:enum|extension) (\w+)", s[:m.start()]))
        body = s[m.end():]
        if not heads or body.lstrip().startswith("get"):
            continue
        head = heads[-1].group(1)
        depth, k = 1, 0
        while depth:
            if body[k] == "{":
                depth += 1
            elif body[k] == "}":
                depth -= 1
            k += 1
        table = {}
        code = re.sub(r"//[^\n]*", "", body[:k])
        for cm in re.finditer(r"case ([^:]+):\s*return \.(\w+)", code):
            for name in re.findall(r"\.(\w+)", cm.group(1)):
                table[name] = cm.group(2)
        tiers[head] = table
    return tiers


def main():
    s = open(SRC).read()
    tiers = tier_tables(s)
    i = s.index("    static let catalogue: [CosmeticBundle] = [")
    j = s.index("\n    ]\n", i)
    blocks = re.split(r"\n        CosmeticBundle\(", s[i:j])[1:]
    bands = Counter()
    bad = 0
    for b in blocks:
        bid = re.search(r'id:\s*"([^"]+)"', b).group(1)
        leg = hi = full = 0
        missing = []
        for slot, enum in SLOTS.items():
            m = re.search(r"\b" + slot + r":\s*\[([^\]]*)\]", b)
            items = re.findall(r"\.(\w+)", m.group(1)) if m else []
            offered = slot != "music" or MUSIC_OFFERED
            if not items and offered:
                missing.append(slot)
            for it in items:
                t = tiers.get(enum, {}).get(it)
                if t is None:
                    print(f"UNKNOWN {enum}.{it} in {bid}")
                    bad += 1
                    continue
                if offered:
                    full += 0 if it == STARTER[enum] else PRICE[t]
                leg += t == "exclusive"
                hi += t in ("premium", "exclusive")
        rarity = "legendary" if leg >= 2 else "rare" if hi >= 2 else "standard"
        kind = "seasonal " if "availableUntil" in b else "permanent"
        bands[rarity] += 1
        print(f"{bid:20} {kind} {rarity:9} {full:6}  missing: {', '.join(missing) or '-'}")
    print(f"{len(blocks)} collections; " + ", ".join(f"{k} {v}" for k, v in sorted(bands.items())))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
