#!/usr/bin/env python3
"""List every HELD cosmetic piece, for planning new collections.

A piece is ON SALE only if it belongs to a full active collection (all six
slots: ball, goal, trail, floor, pit, boundary) — `CosmeticSale` in
RollAlong/Cosmetics.swift.  Everything else is held, except the Roll Along
defaults and the exempt earned / purchase-only pieces.

Run from the repository root:

    python3 tools/cosmetic-calendar/held_inventory.py            # print
    python3 tools/cosmetic-calendar/held_inventory.py --write    # also write docs/proposals/held-pieces.md

Read-only on the Swift sources.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bundle_rarity import tier_tables, PRICE  # noqa: E402

COSMETICS = "RollAlong/Cosmetics.swift"
BALLS = "RollAlong/BallSkin.swift"
OUT = "docs/proposals/held-pieces.md"
PLURAL = {"Ball": "Balls", "Goal": "Goals", "Trail": "Trails", "Floor": "Floors", "Pit": "Pits", "Boundary": "Boundaries"}

SLOTS = [("balls", "BallSkin", "Ball"), ("goals", "GoalSkin", "Goal"),
         ("trails", "TrailColor", "Trail"), ("floors", "Floor", "Floor"),
         ("pits", "Pit", "Pit"), ("boundaries", "Boundary", "Boundary")]
TIER_NAME = {"starter": "Iconic", "standard": "Standard", "rare": "Rare",
             "premium": "Epic", "exclusive": "Legendary"}
# Earned or purchase-only, never sold for coins (CosmeticSale.exempt*).
EXEMPT = {("BallSkin", "diamond"): "comes with the Diamond Balls purchase; Locker only",
          ("BallSkin", "moneyBall"): "comes with the first 10,000-coin pack",
          ("BallSkin", "trophy"): "earned by finishing the Golden Gauntlet track; also the Champion set's ball",
          ("TrailColor", "moneyRoll"): "purchase-only Money piece (no way to get it in 1.0)",
          ("Floor", "moneyFull"): "purchase-only Money piece (no way to get it in 1.0)",
          ("BallSkin", "waitingRoom"): "end room gift (1.1); never sold",
          ("Floor", "waitingRoom"): "end room gift (1.1); never sold",
          ("Pit", "waitingRoom"): "end room gift (1.1); never sold",
          ("Boundary", "waitingRoom"): "end room gift (1.1); never sold"}
# Replaced inside an active collection during the quality round.
DISPLACED = {("GoalSkin", "meadow"): "Nature", ("BallSkin", "silver"): "Sketchbook",
             ("GoalSkin", "archery"): "Sketchbook", ("GoalSkin", "flame"): "Citrus",
             ("TrailColor", "ember"): "Citrus", ("Floor", "dusk"): "Citrus",
             ("Pit", "sunset"): "Citrus", ("Floor", "mirage"): "Midas",
             ("Pit", "mirage"): "Midas", ("GoalSkin", "obsidian"): "Haunted",
             ("TrailColor", "snake"): "Ancient Temple"}
# Replaced inside an active collection at the owner's request, after the audit.
OWNER_DISPLACED = {("GoalSkin", "leafWreath"): "Nature"}
# Replaced inside a scheduled collection during the audit against the quality standard.
AUDIT_DISPLACED = {("GoalSkin", "mosaic"): "Nightclub", ("TrailColor", "rainbow"): "Nightclub",
                   ("TrailColor", "air"): "Golf", ("TrailColor", "sky"): "Ocean",
                   ("Floor", "parchment"): "Bloom", ("Pit", "parchment"): "Bloom",
                   ("Floor", "blueprint"): "Ocean", ("Pit", "blueprint"): "Ocean"}


VERDICTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "held_verdicts.json")
VERDICT_LABEL = {"meets": "Meets", "borderline": "Borderline", "fails": "Fails"}


def load_verdicts():
    """{"<Slot>:<id>": {verdict, rules, reason, theme?}} — pieces missing here print "not audited"."""
    try:
        with open(VERDICTS, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def enum_body(src, name):
    i = src.index("enum " + name + ":")
    j = src.index("var id: String", i)
    return src[i:j]


def cases(src, name):
    """[(caseName, rawValue)] in declaration order."""
    out = []
    body = re.sub(r"//[^\n]*", "", enum_body(src, name))
    for line in re.findall(r"^\s*case ([^\n]+)$", body, re.M):
        for part in line.split(","):
            m = re.match(r"\s*(\w+)(?:\s*=\s*\"([^\"]*)\")?\s*$", part)
            if m:
                out.append((m.group(1), m.group(2) or m.group(1)))
    return out


def display_names(src, name):
    i = src.index("enum " + name + ":")
    j = src.index("var displayName: String {", i)
    k = src.index("\n    }\n", j)
    table = {}
    for cm in re.finditer(r"case ([^:]+):\s*return \"([^\"]*)\"", src[j:k]):
        for c in re.findall(r"\.(\w+)", cm.group(1)):
            table[c] = cm.group(2)
    return table


def main():
    cos = open(COSMETICS, encoding="utf-8").read()
    balls = open(BALLS, encoding="utf-8").read()
    tiers = tier_tables(cos)
    verdicts = load_verdicts()

    items = {}      # enum -> [(case, displayName)]
    for _, enum, _ in SLOTS:
        src = balls if enum == "BallSkin" else cos
        cs = cases(src, enum)
        names = {} if enum == "BallSkin" else display_names(cos, enum)
        items[enum] = [(c, raw if enum == "BallSkin" else names.get(c, c)) for c, raw in cs]

    i = cos.index("    static let catalogue: [CosmeticBundle] = [")
    j = cos.index("\n    ]\n", i)
    blocks = re.split(r"\n        CosmeticBundle\(", cos[i:j])[1:]
    a = cos.index("static let activeIDs: [String] = [") + len("static let activeIDs: [String] = [")
    active_ids = set(re.findall(r'"([^"]+)"', re.sub(r"//[^\n]*", "", cos[a:cos.index("]", a)])))

    collections = []
    for b in blocks:
        bid = re.search(r'id:\s*"([^"]+)"', b).group(1)
        name = re.search(r'displayName:\s*"([^"]+)"', b).group(1)
        seasonal = "availableUntil" in b
        slots = {}
        for slot, enum, _ in SLOTS:
            m = re.search(r"\b" + slot + r":\s*\[([^\]]*)\]", b)
            slots[enum] = re.findall(r"\.(\w+)", m.group(1)) if m else []
        complete = all(slots[e] for _, e, _ in SLOTS)
        active = bid in active_ids and not seasonal
        status = "active" if active else ("seasonal" if seasonal else "retired")
        collections.append(dict(id=bid, name=name, status=status, slots=slots,
                                full=active and complete, complete=complete))

    packs = {}
    p0 = cos.index("    static let catalogue: [BallPack] = [")
    for pb in re.split(r"\n        BallPack\(", cos[p0:cos.index("\n    ]\n", p0)])[1:]:
        pname = re.search(r'displayName:\s*"([^"]+)"', pb).group(1)
        skins = re.findall(r"\.(\w+)", re.search(r"skins:\s*\[([^\]]*)\]", pb, re.S).group(1))
        packs[pname] = skins

    on_sale = {(e, it) for c in collections if c["full"] for e, its in c["slots"].items() for it in its}

    lines = []
    out = lines.append
    out("# Held pieces: inventory for planning")
    out("")
    out("Generated by `tools/cosmetic-calendar/held_inventory.py --write`. Do not edit by hand.")
    out("")
    out("A cosmetic is on sale only as part of a **full active collection** (all six slots filled). "
        "Every other piece is **held**: not shown, not sold, not announced. Held pieces keep their "
        "code and ids, and a player who already owns one keeps it and can equip it from the Locker.")
    out("")
    full = [c for c in collections if c["full"]]
    incomplete = [c for c in collections if c["status"] == "active" and not c["complete"]]
    out(f"- Full active collections on sale: **{len(full)}** (plus the free Roll Along set).")
    out("- Active collections that are NOT full (their pieces would be held): "
        + (", ".join(c["name"] for c in incomplete) if incomplete else "**none**") + ".")
    out("")

    out("## Exempt pieces (not held, never sold for coins)")
    out("")
    out("| Slot | Piece | How a player gets it |")
    out("|---|---|---|")
    for slot, enum, label in SLOTS:
        for c, name in items[enum]:
            if (enum, c) in EXEMPT:
                out(f"| {label} | {name} | {EXEMPT[(enum, c)]} |")
    out("")

    out("## Ball packs")
    out("")
    out("A pack is on sale only when every ball in it is on sale. None qualifies today, so all packs are held "
        "(owners keep and can equip them).")
    out("")
    out("| Pack | Balls | On sale in a full collection | Held |")
    out("|---|---|---|---|")
    ball_name = dict(items["BallSkin"])
    for pname, skins in packs.items():
        sale = [ball_name.get(s, s) for s in skins if ("BallSkin", s) in on_sale]
        held = [ball_name.get(s, s) for s in skins if ("BallSkin", s) not in on_sale]
        out(f"| {pname} | {len(skins)} | {', '.join(sale) or '—'} | {', '.join(held) or '—'} |")
    out("")

    out("## Every held piece")
    out("")
    out("\"Approved?\" is from the quality round: only pieces in the collections on sale were graded. "
        "A piece marked *displaced* was replaced inside an active collection in that round or in the later audit; "
        "*not graded* means it was never reviewed.")
    out("")
    out("\"Verdict vs standard\" is an audit against `docs/cosmetics/quality-standard.md` (rules R1 to R9), "
        "made by reading each piece's drawing code, not by looking at it on screen. The verdicts live in "
        "`tools/cosmetic-calendar/held_verdicts.json`. Held pieces were **not changed**; a piece that is "
        "borderline or fails needs a redraw before it can anchor a collection.")
    out("")
    counts = {}
    tally = {label: {} for _, _, label in SLOTS}
    ready = {}
    for slot, enum, label in SLOTS:
        rows = []
        for c, name in items[enum]:
            tier = tiers.get(enum, {}).get(c, "?")
            if tier == "starter" or (enum, c) in EXEMPT or (enum, c) in on_sale:
                continue
            src = [f"{col['name']} ({col['status']})" for col in collections
                   if c in col["slots"][enum] and not col["full"]]
            in_packs = [p for p, skins in packs.items() if enum == "BallSkin" and c in skins]
            src += [f"{p} pack" for p in in_packs]
            if (enum, c) in DISPLACED:
                src.insert(0, f"{DISPLACED[(enum, c)]} (displaced in the quality round)")
                approved = "No: displaced (replaced in the quality round)"
            elif (enum, c) in OWNER_DISPLACED:
                src.insert(0, f"{OWNER_DISPLACED[(enum, c)]} (replaced at the owner's request)")
                approved = "No: replaced at the owner's request"
            elif (enum, c) in AUDIT_DISPLACED:
                src.insert(0, f"{AUDIT_DISPLACED[(enum, c)]} (displaced in the audit)")
                approved = "No: displaced (replaced in the audit)"
            else:
                approved = "Not graded"
            v = verdicts.get(f"{label}:{c}")
            if v:
                rules = ", ".join(v.get("rules", []))
                verdict = VERDICT_LABEL.get(v["verdict"], v["verdict"]) + (f" ({rules})" if rules else "")
                why = v.get("reason", "")
                tally[label][v["verdict"]] = tally[label].get(v["verdict"], 0) + 1
                if v["verdict"] == "meets":
                    ready.setdefault(v.get("theme", "Other"), []).append((label, name))
            else:
                verdict, why = "not audited", ""
                tally[label]["not audited"] = tally[label].get("not audited", 0) + 1
            rows.append((name, c, TIER_NAME.get(tier, tier), PRICE.get(tier, 0),
                         "; ".join(src) or "in no collection", approved, verdict, why))
        counts[label] = len(rows)
        out(f"### {PLURAL[label]} held: {len(rows)}")
        out("")
        out("| Slot | Name | id | Tier | Price | Came from | Approved in the quality round? | Verdict vs standard | Why |")
        out("|---|---|---|---|---|---|---|---|---|")
        for name, c, tier, price, src, approved, verdict, why in rows:
            out(f"| {label} | {name} | `{c}` | {tier} | {price:,} | {src} | {approved} | {verdict} | {why} |")
        out("")

    out("## Counts per slot")
    out("")
    out("| Slot | Held pieces |")
    out("|---|---|")
    for _, _, label in SLOTS:
        out(f"| {label} | {counts[label]} |")
    out(f"| **Total** | **{sum(counts.values())}** |")
    out("")
    low = min(counts.values())
    short = [l for l, n in counts.items() if n == low]
    out(f"The scarcest slot is **{', '.join(short)}** with {low} held piece(s), so at most **{low}** new full "
        "collection(s) could be built from held pieces alone. Each further collection needs new art in every "
        "slot that has run out, in this order of scarcity: "
        + ", ".join(f"{l} ({n})" for l, n in sorted(counts.items(), key=lambda kv: kv[1])) + ".")
    out("")

    out("## Verdicts per slot")
    out("")
    out("| Slot | Held | Meets | Borderline | Fails | Not audited |")
    out("|---|---|---|---|---|---|")
    tot = {"meets": 0, "borderline": 0, "fails": 0, "not audited": 0}
    for _, _, label in SLOTS:
        t = tally[label]
        for k in tot:
            tot[k] += t.get(k, 0)
        out(f"| {label} | {counts[label]} | {t.get('meets', 0)} | {t.get('borderline', 0)} | "
            f"{t.get('fails', 0)} | {t.get('not audited', 0)} |")
    out(f"| **Total** | **{sum(counts.values())}** | **{tot['meets']}** | **{tot['borderline']}** | "
        f"**{tot['fails']}** | **{tot['not audited']}** |")
    out("")

    out("## Ready to build collections around")
    out("")
    out("Held pieces that already meet the standard, grouped by a theme they could serve. A new collection "
        "needs one piece in every slot; a theme with gaps needs new art for the missing slots.")
    out("")
    out("| Theme | Ball | Goal | Trail | Floor | Pit | Boundary | Slots still missing |")
    out("|---|---|---|---|---|---|---|---|")
    order = [label for _, _, label in SLOTS]
    for theme in sorted(ready, key=lambda th: (-len({l for l, _ in ready[th]}), th)):
        by = {l: [n for l2, n in ready[theme] if l2 == l] for l in order}
        missing = [l for l in order if not by[l]]
        out(f"| {theme} | " + " | ".join(", ".join(by[l]) or "—" for l in order)
            + f" | {', '.join(missing) or 'none'} |")
    out("")
    meets = {label: tally[label].get("meets", 0) for _, _, label in SLOTS}
    out("**New art needed.** Counting only held pieces that meet the standard, and ignoring whether their "
        "themes match, each slot has: "
        + ", ".join(f"{l} {n}" for l, n in meets.items()) + ". To build N new collections from them:")
    out("")
    out("| New collections | " + " | ".join(order) + " |")
    out("|---|" + "---|" * len(order))
    for n in (1, 2, 3, 5):
        out(f"| {n} | " + " | ".join(
            ("enough" if meets[l] >= n else f"{n - meets[l]} new") for l in order) + " |")
    out("")
    out("Themes rarely line up across slots, so in practice most new collections will need new trails, "
        "floors and pits drawn for them, with held balls, goals and boundaries as the starting point.")
    out("")

    text = "\n".join(lines)
    print(text)
    if "--write" in sys.argv:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"\nwrote {OUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
