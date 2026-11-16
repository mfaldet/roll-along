# Competitive minigame opponents: how they work and how to tune them

**Status: built (2026-11-15), not yet played.** The proposal below was
approved and is in the code. It could not be compiled or played where it was
written, so every number is still a starting guess to be checked on a phone.
The sections after "Where the numbers live" are the original report and
describe the opponents as they were BEFORE this change.

## Where the numbers live

Every tuning number is in one table: `OpponentTuning` in
`RollAlong/GameState.swift`. Change a value, raise `OpponentTuning.version`
by one, rebuild.

| Number | Easy | Normal | Hard |
|---|---|---|---|
| Reaction delay | 0.45 s | 0.30 s | 0.18 s |
| Aiming error (held 0.5 s) | 25° | 14° | 7° |
| Mistake about every | 4 s | 7 s | 12 s |
| Mistake lasts | 0.8 s | 0.6 s | 0.4 s |
| Effort (share of full opponent push) | 40% | 55% | 70% |
| Smash and Grab top speed | 72% | 85% | 100% |
| Sumo Survival shove | 0.30 | 0.40 | 0.50 |
| King of the Hill opponents going for the zone at once | 1 | 2 | 3 |

"Full opponent push" is each game's own opponent base push (`aiAccelBase` in
that game's file), which is already a little below the player's full-tilt
push.

Setup numbers in the same table: Sumo Survival start ring and first-target
time, King of the Hill start ring, turn length, hang-back and overshoot
distances, Comet Clash obstacle delay share, Smash and Grab coin spreading,
Marble Cup sudden-death length.

What was built:

- **Shared:** `OpponentBrain` (same file) gives each opponent a delayed view
  of its target, a held aiming error, scheduled mistakes and an effort share.
  The old sway and one-frame dips are gone.
- **Comet Clash:** chases where the spark was; notices a blocked path late;
  during a mistake stops checking for obstacles.
- **Sumo Survival:** all four marbles start evenly spaced on one ring (nobody
  in the middle). Each opponent's first target is another opponent, for 4
  seconds, then whoever is nearest. Shove strength follows difficulty. During
  a mistake it ignores the rim.
- **Paint Ball:** a mistake sends it to floor it has already painted, puddles
  not avoided.
- **Smash and Grab:** the bully's charge uses the same delayed, imperfect
  aim. Opponents prefer different coins. A mistake sends one after the
  farthest coin.
- **Marble Cup:** a level score at full time goes to sudden death (next goal
  wins) for up to 30 seconds. Still level is a draw: no win, no loss, not
  counted in the win rate. During a mistake the opponent attacks the ball
  from the wrong side. In 2v2 your teammate has the same limits.
- **King of the Hill:** all four marbles start the same distance from the
  first zone. Opponents take turns going for the zone (1 at a time on Easy, 2
  on Normal, all 3 on Hard), switching every 6 seconds. A mistake is an
  overshoot.
- **Analytics:** `minigame_result` now also carries `placement`, `score`,
  `best_rival_score`, `duration_s`, `draw` and `ai_version` (the tuning
  version). Query 6 in `docs/soft-launch-metrics.sql` is rewritten to use it.

Targets are now 70% / 50% / 30% (Easy / Normal / Hard).

---

# Original report (before the change)

## The main finding

The opponents are too strong mostly because of one mismatch, not because
they are clever.

- **The player's push depends on how far they tilt.** At a comfortable 20 to
  30 degrees a player gets roughly a third to a half of the game's nominal
  acceleration.
- **Opponents always push at full strength**, scaled only by difficulty: 55%
  on Easy, 78% on Normal, 100% on Hard.

So an Easy opponent at 55% still out-accelerates a typical player at 35 to
50%. The code comments say opponents are "a touch slower than you", which is
only true for a player holding the phone at 90 degrees.

Three other things add to it:

- **Opponents see everything and react instantly.** Every opponent reads the
  exact current position of every marble, coin, ball and zone 60 times a
  second. There is no reaction delay anywhere.
- **The existing "human" touches do not cause mistakes.** Easy and Normal add
  a slow sway to the opponent's aim and a random one-frame dip in push. The
  sway is re-aimed at the true target every frame, so it bends the path
  without missing; the dips average out to a small cut in push. Hard has
  neither.
- **Several games are stacked against the player by their setup** (listed per
  game below).

The code already records intended win rates of 80% Easy, 45% Normal and 22%
Hard, but nothing uses them. The only measurement in the repo is a simulation
of Smash and Grab, which found Normal and Hard indistinguishable (54% each
against a scripted player who tilted far harder than real players do).

## What differs between difficulties today

| Setting | Easy | Normal | Hard | Used by |
|---|---|---|---|---|
| Push strength | 55% | 78% | 100% | All six |
| Top speed | 72% | 85% | 100% | Smash and Grab only |
| Aim sway | wide | narrow | none | All except Comet Clash |
| One-frame push dips | 28% of frames | 8% of frames | never | All except Comet Clash |
| Coin payout | ×1 | ×1.5 | ×2 | All six |

"Hardcore" exists only in Disco Ball, which has no opponents.

## Game by game

### Comet Clash
- **How the opponent decides.** It looks a short distance ahead. If anything
  is in the way (a trail, a wall, an asteroid, the edge) it turns toward the
  side with more room. Otherwise it heads for the nearest spark. It never
  targets the player.
- **Difficulty today.** Push strength only. No sway, no dips, on any level.
- **Why it is hard.** You win only by outliving all three opponents, each of
  which senses every obstacle perfectly and reacts in one frame.

### Sumo Survival
- **How the opponent decides.** It charges the nearest marble. Near the rim
  it pulls back toward the center.
- **Difficulty today.** Push strength, sway, dips. The strength of its shove
  in a collision does not change with difficulty.
- **Why it is hard.** The player starts in the center with the three
  opponents around them, each closer to the player than to each other, so all
  three charge the player first. Shove strength depends on tilt for the
  player but is fixed for opponents, so a gently tilting player is
  out-muscled. Opponents retreat from the rim perfectly.

### Paint Ball
- **How the opponent decides.** About once a second it picks a new spot,
  preferring unpainted floor far away, and rolls there. It avoids choosing a
  spot near a puddle.
- **Difficulty today.** Push strength, sway, dips.
- **Why it is hard.** It is the fairest of the six. Its edge is constant full
  push.

### Smash and Grab
- **How the opponent decides.** It heads for the nearest coin in a straight
  line. One opponent is a "bully": if anyone nearby has a higher score it
  chases them and charges on the exact frame it comes into range.
- **Difficulty today.** All four settings.
- **Why it is hard.** The bully's charge is frame-perfect and aimed
  perfectly, and it targets whoever is winning, which punishes a player in
  the lead. Opponents are steered away from the edges; the player is not. All
  three chase the same nearest coin, which is why Normal and Hard measured
  the same.

### Marble Cup
- **How the opponent decides.** When the ball is near its own goal it gets
  between ball and goal. Otherwise it goes to the spot directly behind the
  ball and pushes it toward the player's goal.
- **Difficulty today.** Push strength, sway, dips.
- **Why it is hard.** It always knows exactly where "behind the ball" is and
  goes there without delay. A draw counts as a loss, unlike the other games,
  where ties go to the player. The player's only advantage is the tap-dash.

### King of the Hill
- **How the opponent decides.** All three opponents head straight for the
  exact center of the zone, all the time.
- **Difficulty today.** Push strength, sway, dips. It has the highest base
  push of any game.
- **Why it is hard.** The zone holds one marble and time only counts when a
  marble is alone in it. Three opponents converging on it means the player is
  bumped or contested almost constantly. Opponents start near where the zone
  appears; the player starts at the bottom edge.

## Proposal: human limits per difficulty

Give every opponent the three limits a person has, set per difficulty, in one
shared place so all six games use the same model.

| Limit | What it means | Easy | Normal | Hard |
|---|---|---|---|---|
| Reaction delay | The opponent acts on where things were this long ago | 0.45 s | 0.30 s | 0.18 s |
| Aiming error | It aims off-target by up to this much, holding the same error for about half a second before picking a new one | 25° | 14° | 7° |
| Mistakes | Every so often it does the wrong thing for a moment | about every 4 s, for 0.8 s | about every 7 s, for 0.6 s | about every 12 s, for 0.4 s |
| Effort | Share of full push it uses, like a person who does not tilt to the limit | 40% | 55% | 70% |

These numbers are starting guesses. "Effort" is the most important row: it
puts opponents in the same range as a real player's tilt.

The difference from today's sway is that the aiming error is held for a
moment, so the opponent actually misses, and a mistake is a visible lapse,
not a one-frame dip.

**What a mistake looks like in each game**

| Game | Mistake |
|---|---|
| Comet Clash | Stops checking for obstacles for a moment |
| Sumo Survival | Keeps charging when it should pull back from the rim, or drifts with no push |
| Paint Ball | Rolls to a spot it has already painted, or through a puddle |
| Smash and Grab | Goes for a far coin, or charges late and misses |
| Marble Cup | Runs at the ball from the wrong side |
| King of the Hill | Overshoots the zone |

**Setup fixes, without which the limits will not be enough**

- **Sumo Survival:** opponents pick a target at random among the others at
  the start, not the nearest, so they do not all charge the player. Scale
  their shove strength with difficulty.
- **King of the Hill:** on Easy and Normal, at most one or two opponents
  contest the zone at a time while the others hang back. Start the player no
  farther from the first zone than the opponents.
- **Smash and Grab:** give the bully the same reaction delay and aiming error
  on its charge. Have the three opponents prefer different coins. Apply the
  edge steering to nobody or to everyone.
- **Marble Cup:** decide whether a draw should count as a loss. Counting it
  as "no result" would raise the win rate without touching the opponent.
- **Comet Clash:** winning means beating three opponents at once, so this
  game needs the weakest opponents of the six to reach the same win rate.

### Targets

About 70% wins on Easy, 50% on Normal and 30% on Hard for an average player.

Five of the six games are one player against three. With four equal
competitors a player would win 25% of the time, so reaching 70% on Easy means
Easy opponents must be far weaker than the player, not slightly weaker. That
is expected, not a sign the tuning is wrong.

### How to get there

1. **Build the shared limits** and use them in each game's steering code.
   Each game makes its decision in one place, so this is roughly 10 to 25
   lines per game plus the shared part.
2. **Tune Smash and Grab with the calibration test (see the last section).** It is the only game that can play
   itself without a screen, and a test already runs 200 rounds per
   difficulty. Change its scripted player to tilt like a real one first.
3. **Tune the other five by hand** on a phone. They cannot simulate without
   significant rework (an earlier note in the repo estimates 300 to 450 lines
   per game).
4. **Adjust from real results after launch**, using the analytics below.
   Each adjustment is an app update; there is no way to change these numbers
   from the server, and adding one is not proposed here.

Size: about 250 to 350 lines of app code and tests. As with everything on
this branch, none of it can be compiled or played here, and this change is
all feel, so it needs the most time on a phone of anything proposed so far.

## Does the game already record what is needed to tune from real data?

**Yes, the essentials.** Every finished round of all six games sends one
event, `minigame_result`, with the game, the difficulty, whether the player
won, and the payout. That is enough to compute the win rate per game and
difficulty.

**Gaps**

- The shared event has no score, placement, round length or map.
- Each game also sends its own end-of-round event, and these are
  inconsistent: different names, Sumo's has no "won", and none carries the
  game as a property.
- `docs/soft-launch-metrics.sql` computes win rate from those per-game events
  and gets it wrong (Sumo would show 0%, and non-competitive games are swept
  in). It should use `minigame_result`.
- Marble Cup's one-against-one and two-against-two results are pooled.

**Smallest addition.** Add four properties to `minigame_result`:

| Property | Why |
|---|---|
| `placement` (1 to 4) | Losing by a little and losing badly look the same today |
| `score` and `best_rival_score` | The margin |
| `duration_s` | Spot rounds that end instantly |
| `ai_version` | Tell results before and after a tuning change apart |

And fix the query. That is about 30 lines.

**Privacy.** No change to the privacy answers. These are gameplay events tied
only to the random install ID, a type already declared as "Gameplay Content,
not linked, Analytics".

One limit of this data: events are per install, not per skill level. "An
average player" has to be approximated as the middle of the per-install win
rates, which the query can do.

## Smash and Grab after the first play test (2026-11-16, tuning v3)

**Withdrawn figures.** After the first build, win rates of 91% (Easy), 83.5%
(Normal) and 67% (Hard) were reported for Smash and Grab. They came from a
separate copy of the game's rules written in another language, not from the
game's own code, and real play contradicted them (Easy was lost). **Those
figures were wrong and are withdrawn.** That copy has been dropped. The only
simulation of this game is now `MinigameAICalibrationTests` in
`RollAlongTests/GameStateTests.swift`, which plays the real engine
(`GoldRushEngine`) through the same two inputs the screen uses: the tilt
value and the tap to dash. Its scripted player always knows where the
nearest coin is and never tires, so its output compares difficulties with
each other; it does not predict what a person will score.

**What the trace found**

- All the limits did reach the opponents. The reaction delay, aiming error,
  mistakes and push share were applied per opponent every tick; the brains
  were not being reset.
- Top speed was the same for all three opponents (the middle value of the
  difficulty). It is now each opponent's own.
- **The limits barely changed how many coins opponents took.** The board
  never holds more than 18 coins and gets a new one three times a second, so
  nearly every coin is picked up by somebody on every difficulty. Three
  opponents sweeping the board take about the same total whether they are a
  little faster or a little slower. That is why the three levels felt alike.
- **Each new round uses the next map.** "Play Again" moves to the next
  arena, so Easy, Normal and Hard played back to back are played on three
  different maps. On the "Box" map the four walls meet at the corners and
  close the middle off: every marble started inside, coins that landed
  outside could never be reached, and once 18 of them had piled up outside
  no more appeared. Scores on that map collapse for everyone. A different
  map in each round is the most likely reason opponents scored far less in
  the Hard round than in the Easy one. This could not be confirmed without
  the phone.

**What changed**

- Coins only appear, and marbles only start, where every marble can get to.
- Opponents now differ in ways that change how many coins they take: how
  long a coin lies there before they notice it, how far they can see, how
  long they coast after a pickup, how often the dashing opponent dashes, and
  whether they plan around walls. All per difficulty and per opponent skill.
- Each opponent draws its own skill for the round, so one is clumsy, one
  average and one sharp.
- During a mistake an opponent heads for the farthest coin and stops
  steering away from the edges, so it runs into the border.
- Coins knocked loose scale with the speed of the hit: a dash drops 3 to 6,
  a fast ordinary bump makes the slower marble drop 1 or 2, a slow bump
  drops nothing. A marble that just dropped coins cannot be made to drop
  more for one second.

Every number is in the "SMASH AND GRAB" block of `OpponentTuning`.
