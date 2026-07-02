# 09 — Telemetry recheck: recompute the real earn rate

The reprice ([08-reprice.md](08-reprice.md)) prices the tier ladder off a
**modeled** blended earn rate of ~25 coins/min. This runbook replaces the model
with measured data once players have generated it. Scheduled first check:
**2026-07-16** (re-run later if data is thin — the check is only meaningful
~2 weeks after the reprice build reaches players).

## Where the data lives

`AnalyticsClient` posts to the Supabase `events` table (project
`mhwpcwauzvmtmuphtajs`, REST insert; schema in
[supabase-schema.sql](../supabase-schema.sql)): `event_name text`,
`properties jsonb`, `user_id`, `session_id`, `created_at`. The events that
matter here:

- `minigame_result` — `game, difficulty, won, base_payout, payout`
- `level_complete` (climb) / track + daily clear events — carry timing + coins
- `daily_challenge_level_cleared` — daily sub-level funnel

## Step 1 — data sufficiency

```sql
select event_name, count(*) as n, min(created_at) as first_seen
from events
where event_name in ('minigame_result','level_complete')
  and created_at > date '2026-07-02'      -- reprice build only
group by event_name;
```

Proceed only when `minigame_result` has **n ≥ 200 per game × difficulty cell**
you intend to act on (spot-check with the Step 3 query). Otherwise stop and
re-schedule.

## Step 2 — measured coins/min while in competitive play

```sql
-- payout per round + rounds per session-minute, by game and difficulty
select properties->>'game'        as game,
       properties->>'difficulty'  as difficulty,
       count(*)                   as rounds,
       avg((properties->>'payout')::numeric)                    as avg_payout,
       avg(case when (properties->>'won')::boolean then 1 else 0 end) as win_rate
from events
where event_name = 'minigame_result'
  and created_at > date '2026-07-02'
group by 1, 2
order by 1, 2;
```

Blend: weight each game's `avg_payout / (round_length + 8s overhead)` by its
observed share of rounds. Round lengths: KotH/PaintBall/SmashGrab 60s,
Snake ~60s, MarbleCup/Sumo ~90–128s (see 01-earning.md).

## Step 3 — win rates vs design targets (feeds AI calibration, workstream D)

```sql
select properties->>'game' as game, properties->>'difficulty' as difficulty,
       count(*) as n,
       round(avg(case when (properties->>'won')::boolean then 1 else 0 end)::numeric, 3) as observed,
       case properties->>'difficulty'
            when 'easy' then 0.80 when 'normal' then 0.45 else 0.22 end as target
from events
where event_name = 'minigame_result' and created_at > date '2026-07-02'
group by 1, 2
having count(*) >= 200
order by 1, 2;
```

Cells > ±10 points off target → adjust that mode's `aiAccelBase` per the
procedure in [minigame-difficulty.md](../minigame-difficulty.md). Also watch
the **Easy-camping question** (ruling 5 made Easy EV-optimal per attempt):
compare rounds-share by difficulty over time.

## Step 4 — act on the blended R

- Blended R within ~20% of 25 coins/min → no action; re-check monthly.
- R materially **higher** → time-to-afford is under target: nudge tier prices
  **upward only** (ruling 4's subtle inflation; keep every price EVEN so the
  sell-back half stays exact), or trim the hottest faucet's base payout.
- R materially **lower** → do NOT cut prices (loss-aversion; 08-reprice.md):
  raise weak payouts toward the band instead.

Record every recheck as a dated section appended to this file.
