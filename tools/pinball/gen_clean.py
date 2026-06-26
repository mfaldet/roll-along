#!/usr/bin/env python3
"""Emit clean_table.json: the COMPOSED table (from clean_table.py / sim.py) in
playfield FRACTIONS, for the iOS Chipmunk scene to embed + decode. Same geometry
the pymunk harness uses, so tuning transfers."""
import json, os

def quad(p0, p1, p2, n=24):
    o = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        o.append([round(u*u*p0[0]+2*u*t*p1[0]+t*t*p2[0], 4),
                  round(u*u*p0[1]+2*u*t*p1[1]+t*t*p2[1], 4)])
    return o

shell = [[0.40,0.95]]
shell += quad([0.40,0.95],[0.10,0.93],[0.05,0.74])
shell += [[0.05,0.16]]
shell += quad([0.05,0.16],[0.05,0.035],[0.26,0.022])
shell += quad([0.26,0.022],[0.50,0.004],[0.74,0.022])
shell += quad([0.74,0.022],[0.93,0.06],[0.93,0.22])
shell += [[0.93,0.95],[0.84,0.95]]
divider = [[0.84,0.95],[0.84,0.25]]
funnel = [[0.50,0.95]] + quad([0.50,0.95],[0.80,0.94],[0.84,0.72])

out = {
    "aspect": 1.9,
    "walls": [shell, divider, funnel],
    "bumpers": [{"x":0.30,"y":0.30,"r":0.046},{"x":0.57,"y":0.30,"r":0.046},{"x":0.435,"y":0.22,"r":0.046}],
    "slings": [[[0.20,0.78],[0.30,0.83],[0.20,0.85]], [[0.64,0.78],[0.54,0.83],[0.64,0.85]]],
    "flippers": [{"pivot":[0.27,0.865],"tip":[0.42,0.915],"side":"L"},
                 {"pivot":[0.61,0.865],"tip":[0.45,0.915],"side":"R"}],
    "ballStart": {"x":0.885,"y":0.92},
    "drain": {"x":0.45,"y":0.965,"w":0.12,"h":0.02},
}
json.dump(out, open("clean_table.json","w"), separators=(",",":"))
print("walls", len(out["walls"]), "pts", sum(len(w) for w in out["walls"]),
      "size", os.path.getsize("clean_table.json"))
