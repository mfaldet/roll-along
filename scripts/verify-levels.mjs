#!/usr/bin/env node
// ===========================================================================
// verify-levels.mjs — numeric checker for the authored climb levels in
// RollAlong/LevelOverrides.json.  No dependencies; run with:
//
//     node scripts/verify-levels.mjs [path/to/LevelOverrides.json]
//
// GAME FACTS MIRRORED (sources: RollAlong/LevelLayout.swift,
// RollAlong/BallGameView.swift):
//   • The DTO decoder auto-prepends side-walls x∈[0,0.12] and x∈[0.88,1.0]
//     (full height).  Easy-tier levels (last digit 1-4) have side-walls
//     STRIPPED at play time (full width playable); hard (6-9) and
//     veryHard (0,5) keep them.                     (LevelLayout.layout(for:))
//   • Ball radius = 18pt on a ~390pt arena → ≈0.0462 unit radius.
//   • Coin radius = 9pt → pickup when dist(ball,coin) < 27pt ≈ 0.0692.
//                                        (BallGameView coinRadius / line 5232)
//   • HOLE CAPTURE IS CENTER-BASED: the ball falls when its CENTER is inside
//     a hole rect (BallGameView.isInHole → rect.contains(position)).  The
//     ball may visually overlap hole edges without falling — hard-tier
//     levels use gaps narrower than the ball diameter on purpose.
//   • targetTime = 4·dist(start,goal) + 0.35·designedHoleCount + 2.5 and
//     goldTime = 2.8·dist + 0.20·holes + 1.8, BEFORE the tier multiplier
//     (side-walls do NOT count toward holeCount). (LevelLayout.defaultTimes)
//
// CHECKS PER LEVEL
//   1. coin count == 3 (economy assumes a fixed coins-per-level payout)
//   2. coins inside the tier's playable area; INSIDE a hole rect = BROKEN
//      (depth noted; technically grazeable if depth < pickup reach), within
//      ball radius of a hole edge = RISKY
//   3. start & goal similarly valid + sane start→goal separation
//   4. solvability, two models on a 0.01 grid flood fill:
//        a. GAME PHYSICS (center-based capture): start→goal must connect and
//           every coin must be pickable from a reachable cell — failures are
//           BROKEN / UNSOLVABLE.
//        b. FULL CLEARANCE (holes inflated by the ball radius): failures are
//           TIGHT advisories — the ball must squeeze past overlapping a hole
//           edge somewhere (expected on hard/veryHard, suspicious on easy).
//   5. tier sanity: digit-rule tier vs a difficulty heuristic (designed-hole
//      blocked-area fraction of the playable band + bottleneck corridor
//      width on the start→goal path, via binary-searched inflation radius)
//   6. targetTime/goldTime consistency: explicit values must match the
//      formula (omitted values are auto-computed, hence always consistent)
//
// Exit code: 2 if any BROKEN flag, 1 if only advisory flags, 0 when clean.
// ===========================================================================

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// ---------------------------------------------------------------------------
// Constants mirrored from the game
// ---------------------------------------------------------------------------
const ARENA_PT = 390;
const BALL_R = 18 / ARENA_PT;          // ≈ 0.0462
const COIN_R = 9 / ARENA_PT;           // ≈ 0.0231
const PICKUP = BALL_R + COIN_R;        // ≈ 0.0692 (coin pickup reach)
const SIDE_WALLS = [
  { x: 0.0, y: 0, w: 0.12, h: 1 },
  { x: 0.88, y: 0, w: 0.12, h: 1 },
];
const GRID = 0.01;
const N = Math.round(1 / GRID) + 1;    // 101 nodes per axis
const EPS_CLEAR = 1e-6;                // "center strictly inside" clearance

// Tunables (checker policy, not game truth)
const MIN_START_GOAL_DIST = 0.25;      // below this the level is trivially short
const TIME_EPS = 0.02;                 // tolerance for explicit target/gold times
// Tier-sanity thresholds, calibrated on the shipped 100-level distribution:
//   easy levels measure corridor 0.12–0.24 / frac 0.035–0.28,
//   hard+veryHard corridor 0.02–0.20 / frac 0.08–0.56.
const HARD_LOOKS_OPEN = { maxFrac: 0.10, minCorridor: 0.155 }; // .155 absorbs grid quantization on a true 0.16 gap
const EASY_LOOKS_HARD = { minFrac: 0.20, maxCorridor: 0.13 };

// ---------------------------------------------------------------------------
// Tier rule (LevelLayout.DifficultyTier.tier(for:))
// ---------------------------------------------------------------------------
function tierFor(level) {
  const d = Math.abs(level) % 10;
  if (d >= 1 && d <= 4) return "easy";
  if (d >= 6 && d <= 9) return "hard";
  return "veryHard"; // 0, 5
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const inRect = (p, r) =>
  p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
// Distance from a point to a rect boundary region (0 when inside).
function rectDist(p, r) {
  const dx = Math.max(r.x - p.x, 0, p.x - (r.x + r.w));
  const dy = Math.max(r.y - p.y, 0, p.y - (r.y + r.h));
  return Math.hypot(dx, dy);
}
// Depth of a point inside a rect (how far past the nearest edge; <0 outside).
function rectDepth(p, r) {
  if (!inRect(p, r)) return -rectDist(p, r);
  return Math.min(p.x - r.x, r.x + r.w - p.x, p.y - r.y, r.y + r.h - p.y);
}

// Play-time holes for a tier: designed holes, plus side-walls for
// hard/veryHard (the decoder prepends them; easy strips them again).
const effectiveHoles = (designed, tier) =>
  tier === "easy" ? designed : [...SIDE_WALLS, ...designed];

// ---------------------------------------------------------------------------
// Grid flood fill
// ---------------------------------------------------------------------------
// Blocked grid for ball-center positions with clearance c: a node is blocked
// when its center is closer than c to any hole region, or within c of the
// arena edge (outer walls stop the ball; c=EPS_CLEAR ≈ game physics, where
// only centers strictly inside a hole fall).
function buildBlocked(holes, c) {
  const blocked = new Uint8Array(N * N);
  for (let iy = 0; iy < N; iy++) {
    const y = iy * GRID;
    for (let ix = 0; ix < N; ix++) {
      const x = ix * GRID;
      let b =
        x < c - 1e-9 || x > 1 - c + 1e-9 || y < c - 1e-9 || y > 1 - c + 1e-9;
      if (!b) {
        for (const h of holes) {
          if (rectDist({ x, y }, h) < c - 1e-9) { b = true; break; }
        }
      }
      if (b) blocked[iy * N + ix] = 1;
    }
  }
  return blocked;
}

const nodeIndex = (p) => {
  const ix = Math.min(N - 1, Math.max(0, Math.round(p.x / GRID)));
  const iy = Math.min(N - 1, Math.max(0, Math.round(p.y / GRID)));
  return iy * N + ix;
};

// BFS from a start node over unblocked cells (4-connectivity).
// Returns a reachability mask, or null when the start itself is blocked.
function floodFill(blocked, startIdx) {
  if (blocked[startIdx]) return null;
  const seen = new Uint8Array(N * N);
  const queue = new Int32Array(N * N);
  let head = 0, tail = 0;
  seen[startIdx] = 1;
  queue[tail++] = startIdx;
  while (head < tail) {
    const idx = queue[head++];
    const ix = idx % N, iy = (idx / N) | 0;
    if (ix > 0     && !seen[idx - 1] && !blocked[idx - 1]) { seen[idx - 1] = 1; queue[tail++] = idx - 1; }
    if (ix < N - 1 && !seen[idx + 1] && !blocked[idx + 1]) { seen[idx + 1] = 1; queue[tail++] = idx + 1; }
    if (iy > 0     && !seen[idx - N] && !blocked[idx - N]) { seen[idx - N] = 1; queue[tail++] = idx - N; }
    if (iy < N - 1 && !seen[idx + N] && !blocked[idx + N]) { seen[idx + N] = 1; queue[tail++] = idx + N; }
  }
  return seen;
}

// Can the ball (center-based) pick up this coin? True when any reachable
// cell lies within pickup reach of the coin center.
function coinPickable(seen, coin) {
  if (!seen) return false;
  const ix0 = Math.max(0, Math.floor((coin.x - PICKUP) / GRID));
  const ix1 = Math.min(N - 1, Math.ceil((coin.x + PICKUP) / GRID));
  const iy0 = Math.max(0, Math.floor((coin.y - PICKUP) / GRID));
  const iy1 = Math.min(N - 1, Math.ceil((coin.y + PICKUP) / GRID));
  for (let iy = iy0; iy <= iy1; iy++) {
    for (let ix = ix0; ix <= ix1; ix++) {
      if (!seen[iy * N + ix]) continue;
      if (Math.hypot(ix * GRID - coin.x, iy * GRID - coin.y) < PICKUP) return true;
    }
  }
  return false;
}

function connects(holes, s, g, c) {
  const seen = floodFill(buildBlocked(holes, c), nodeIndex(s));
  return !!(seen && seen[nodeIndex(g)]);
}

// Largest clearance c (binary search) at which start→goal still connects.
// Corridor width ≈ 2c — the narrowest gap on the best start→goal route.
function bottleneckClearance(holes, s, g) {
  if (!connects(holes, s, g, 0.001)) return 0;
  let lo = 0.001, hi = 0.5;
  for (let i = 0; i < 12; i++) {
    const mid = (lo + hi) / 2;
    if (connects(holes, s, g, mid)) lo = mid; else hi = mid;
  }
  return lo;
}

// Fraction of the tier's playable band covered by DESIGNED holes (the
// side-walls define the band for hard/veryHard; they are not "difficulty").
function blockedFraction(designed, tier) {
  const x0 = tier === "easy" ? 0 : 0.12;
  const x1 = tier === "easy" ? 1 : 0.88;
  let blocked = 0, total = 0;
  const steps = 100;
  for (let iy = 0; iy <= steps; iy++) {
    const y = iy / steps;
    for (let ix = 0; ix <= steps; ix++) {
      const x = x0 + ((x1 - x0) * ix) / steps;
      total++;
      for (const h of designed) {
        if (inRect({ x, y }, h)) { blocked++; break; }
      }
    }
  }
  return blocked / total;
}

// ---------------------------------------------------------------------------
// Point validity vs playable area + holes
// ---------------------------------------------------------------------------
function classifyPoint(name, p, designed, tier) {
  const broken = [], risky = [];
  if (p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) {
    broken.push(`${name} (${p.x},${p.y}) outside the arena`);
    return { broken, risky };
  }
  if (tier !== "easy" && (p.x < 0.12 || p.x > 0.88)) {
    broken.push(
      `${name} (${p.x},${p.y}) inside the ${tier} side-wall band (playable x∈[0.12,0.88])`
    );
  }
  for (const h of designed) {
    const depth = rectDepth(p, h);
    const rect = `[${h.x},${h.y},${h.w},${h.h}]`;
    if (depth >= 0) {
      const graze = depth < PICKUP && name.startsWith("coin")
        ? `; depth ${depth.toFixed(3)} < pickup reach ${PICKUP.toFixed(3)}, grazeable from the rim but a fall-bait placement`
        : `; depth ${depth.toFixed(3)}`;
      broken.push(`${name} (${p.x},${p.y}) INSIDE hole ${rect}${graze}`);
    } else if (-depth < BALL_R) {
      risky.push(
        `${name} (${p.x},${p.y}) within ball radius of hole ${rect} (clearance ${(-depth).toFixed(3)} < ${BALL_R.toFixed(3)})`
      );
    }
  }
  return { broken, risky };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
const here = dirname(fileURLToPath(import.meta.url));
const jsonPath =
  process.argv[2] ?? join(here, "..", "RollAlong", "LevelOverrides.json");
const doc = JSON.parse(readFileSync(jsonPath, "utf8"));
const levels = doc.levels ?? {};
const ids = Object.keys(levels).map(Number).sort((a, b) => a - b);

let anyBroken = false, anyAdvisory = false, clean = 0;
const report = []; // { level, severity, msg }
const add = (level, severity, msg) => {
  report.push({ level, severity, msg });
  if (severity === "BROKEN") anyBroken = true; else anyAdvisory = true;
};

for (const id of ids) {
  const before = report.length;
  const lvl = levels[String(id)];
  const tier = tierFor(id);
  const designed = lvl.holes ?? [];
  const holes = effectiveHoles(designed, tier);
  const coins = lvl.coins ?? [];

  // -- hole rect sanity
  for (const h of designed) {
    if (h.w <= 0 || h.h <= 0 || h.x < 0 || h.y < 0 ||
        h.x + h.w > 1 + 1e-9 || h.y + h.h > 1 + 1e-9) {
      add(id, "BROKEN", `hole [${h.x},${h.y},${h.w},${h.h}] degenerate or out of the unit arena`);
    }
  }

  // -- (1) coin count
  if (coins.length !== 3) {
    add(id, "BROKEN", `coin count ${coins.length} != 3 — breaks the fixed coins-per-level economy assumption`);
  }

  // -- (2) coin placement, (3) start/goal placement
  const pts = [
    ...coins.map((c, i) => [`coin#${i + 1}`, c]),
    ["start", lvl.start],
    ["goal", lvl.goal],
  ];
  for (const [name, p] of pts) {
    const { broken, risky } = classifyPoint(name, p, designed, tier);
    for (const m of broken) add(id, "BROKEN", m);
    for (const m of risky) add(id, "RISKY", m);
  }
  const sg = dist(lvl.start, lvl.goal);
  if (sg < MIN_START_GOAL_DIST) {
    add(id, "RISKY", `start→goal separation ${sg.toFixed(3)} < ${MIN_START_GOAL_DIST} — trivially short`);
  }

  // -- (4a) solvability under game physics (center-based capture)
  const seenGame = floodFill(buildBlocked(holes, EPS_CLEAR), nodeIndex(lvl.start));
  if (!seenGame) {
    add(id, "BROKEN", `start (${lvl.start.x},${lvl.start.y}) spawns inside a hole — unplayable`);
  } else {
    if (!seenGame[nodeIndex(lvl.goal)]) {
      add(id, "BROKEN", `UNSOLVABLE: no center path start (${lvl.start.x},${lvl.start.y}) → goal (${lvl.goal.x},${lvl.goal.y}) even under center-based capture`);
    }
    coins.forEach((c, i) => {
      if (!coinPickable(seenGame, c)) {
        add(id, "BROKEN", `coin#${i + 1} (${c.x},${c.y}) not pickable: no reachable ball-center cell within pickup reach ${PICKUP.toFixed(3)}`);
      }
    });
  }

  // -- (4b) full-clearance flood fill (holes inflated by ball radius)
  const seenComf = floodFill(buildBlocked(holes, BALL_R), nodeIndex(lvl.start));
  const corridor = 2 * bottleneckClearance(holes, lvl.start, lvl.goal);
  const comfGoal = !!(seenComf && seenComf[nodeIndex(lvl.goal)]);
  if (!comfGoal) {
    const squeezeCoins = coins
      .map((c, i) => (!seenComf || !seenComf[nodeIndex(c)] ? i + 1 : null))
      .filter((x) => x !== null);
    add(id, "TIGHT", `no full-clearance path to goal (bottleneck corridor ${corridor.toFixed(3)} < ball diameter ${(2 * BALL_R).toFixed(3)}); ball must overlap hole edges${squeezeCoins.length ? `; coins #${squeezeCoins.join(",#")} also need squeezing` : ""} — playable under center-based capture`);
  } else if (seenComf) {
    coins.forEach((c, i) => {
      if (!seenComf[nodeIndex(c)] && coinPickable(seenGame, c)) {
        add(id, "TIGHT", `coin#${i + 1} (${c.x},${c.y}) has no full-clearance route (squeeze required)`);
      }
    });
  }

  // -- (5) tier sanity heuristic
  const frac = blockedFraction(designed, tier);
  const metrics = `blockedFrac=${frac.toFixed(3)}, corridor=${corridor.toFixed(3)}`;
  if (tier !== "easy" &&
      frac <= HARD_LOOKS_OPEN.maxFrac && corridor >= HARD_LOOKS_OPEN.minCorridor) {
    add(id, "TIER", `numbered ${tier} but layout looks open for the tier (${metrics})`);
  } else if (tier === "easy" &&
             (corridor < 2 * BALL_R ||
              (frac >= EASY_LOOKS_HARD.minFrac && corridor <= EASY_LOOKS_HARD.maxCorridor))) {
    add(id, "TIER", `numbered easy but layout measures hard (${metrics}${corridor < 2 * BALL_R ? "; corridor narrower than the ball" : ""})`);
  }

  // -- (6) targetTime / goldTime formula consistency
  const expTarget = 4 * sg + 0.35 * designed.length + 2.5;
  const expGold = 2.8 * sg + 0.2 * designed.length + 1.8;
  if (lvl.targetTime !== undefined && Math.abs(lvl.targetTime - expTarget) > TIME_EPS) {
    add(id, "BROKEN", `explicit targetTime ${lvl.targetTime} != formula ${expTarget.toFixed(3)} (4·${sg.toFixed(3)} + 0.35·${designed.length} + 2.5)`);
  }
  if (lvl.goldTime !== undefined && Math.abs(lvl.goldTime - expGold) > TIME_EPS) {
    add(id, "BROKEN", `explicit goldTime ${lvl.goldTime} != formula ${expGold.toFixed(3)} (2.8·${sg.toFixed(3)} + 0.20·${designed.length} + 1.8)`);
  }
  if (lvl.targetTime !== undefined && lvl.goldTime !== undefined &&
      lvl.goldTime >= lvl.targetTime) {
    add(id, "BROKEN", `goldTime ${lvl.goldTime} >= targetTime ${lvl.targetTime} — star thresholds inverted`);
  }

  if (report.length === before) clean++;
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------
const bySev = { BROKEN: 0, RISKY: 0, TIGHT: 0, TIER: 0 };
for (const r of report) bySev[r.severity]++;
console.log(
  `verify-levels: ${ids.length} levels checked, ${clean} fully clean — ` +
  `${bySev.BROKEN} BROKEN, ${bySev.RISKY} RISKY, ${bySev.TIGHT} TIGHT, ${bySev.TIER} TIER flag(s)\n`
);
for (const r of report) {
  console.log(`level ${r.level} [${tierFor(r.level)}] ${r.severity}: ${r.msg}`);
}
process.exit(anyBroken ? 2 : anyAdvisory ? 1 : 0);
