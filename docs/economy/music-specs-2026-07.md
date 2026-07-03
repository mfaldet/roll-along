# Legendary music composition briefs — celestial, mysterium, opus

**Status: SPECS ONLY — awaiting Mac's audio-production decision.**

An honest header first: the **entire music category is identifiers today**.
`MusicTrack` (Cosmetics.swift:1376-1431) is a pure enum — the shop and
settings render and price the catalogue, but there are **no `.m4a` assets in
the bundle and no AVAudioPlayer wiring**; the code's own comment defers both
to V1.1. Nothing in this document changes that. These briefs exist so that
the three spec-less Legendary tracks stop being the only 1,500-coin items in
the catalogue with *no written bar at all* — when Mac green-lights audio
production (open ruling #5 in [standards-cosmetics.md](standards-cosmetics.md)
§6), each commission can cite its brief the way every visual cosmetic PR must
cite its §3 checklist lines. Until then, do not commission, generate, or
wire any audio from this document alone.

## The bar these briefs must clear

From [standards-cosmetics.md](standards-cosmetics.md) §3 (Music), Legendary:

> a bespoke signature piece: ≥3 min, or evolving/layered structure that never
> reads as a loop; a unique motif owned by the track.

Plus the QA gate that applies at every tier: mastering/loudness parity —
a Legendary track is bigger in ambition, never merely louder. All three
briefs below target **3:00+ with evolving structure** (both halves of the
"or", deliberately — these are the flagship purchases) and each names the
motif that makes it recognizable blind. The fourth Legendary, `aurora`, is
excluded here: it already has a spec direction ("ambient, drifting pads…
recognizably *the Aurora sound*", standards §3 + Cosmetics.swift:1407).

Shared production constraints (all three):

- **Context**: underscore for a tilt-based marble game — plays beneath
  gameplay SFX (coin pings, bounces, goal fanfares) and menus alike. Keep
  the 2–5 kHz band uncluttered so SFX cut through; no transient-heavy leads
  fighting the coin sound.
- **Delivery**: `.m4a` (AAC), seamless loop point or composed tail-to-head
  crossfade at the 3min+ mark; the evolving structure hides the seam.
- **Dynamics**: real arcs are wanted, but within a comfortable game-audio
  window (≈ -16 LUFS integrated, matching whatever the Standard tracks
  master to — parity is the gate, the number is provisional until a first
  master exists).

## celestial — "the void looks back, kindly"

| | |
|---|---|
| Mood | vast, weightless wonder; deep-space serenity with an undertow of awe — the track you want equipped with the planet balls |
| Tempo | ~64 BPM felt pulse (largely beatless; pulse implied by pad swells) |
| Key/mode | C Lydian — bright #4 keeps "space" hopeful, never horror-void |
| Instrumentation | slow-attack analog-style pads, high shimmering harmonics (bowed crotales / glass), deep sub swells, distant wordless choir, and a celesta/bell voice for the motif |
| Signature motif | a rising five-note bell figure ("the ascent") that climbs an octave and hangs unresolved on the Lydian #4 — first heard alone at ~0:40, owned by the celesta voice throughout |

**Structure (target 3:40, evolving — never reads as a loop):**

1. **0:00 Void** — near-silence, one pad blooming out of nothing; sub swell
   every ~20s.
2. **0:40 First light** — the ascent motif, solo celesta, twice; harmonics
   begin shimmering underneath.
3. **1:20 Starfield** — pads layer into slow 3-part motion; choir enters at
   the edge of audibility; motif answered by the choir in inversion.
4. **2:20 Nova** — the one dynamic peak: full pad stack, sub at its warmest,
   motif stated in octaves. Still gentle — a bloom, not a drop.
5. **3:00 Drift home** — layers thin one per phrase back toward the void
   texture, ending on the motif's first three notes only (the loop seam:
   the tail's thinning texture is the head's near-silence).

## mysterium — "a question that likes being unanswered"

| | |
|---|---|
| Mood | enigmatic, shadowed curiosity; candle-lit arcana — mysterious, not menacing (this sits next to gameplay, not a horror set-piece) |
| Tempo | ~78 BPM, loose grid; rubato phrase ends |
| Key/mode | E minor with Phrygian colour (♭2 as a spice note, not a wall) |
| Instrumentation | low sustained strings, a detuned music-box, glass-armonica-like sine swells, sparse deep frame-drum hits, whisper-textured noise beds, occasional plucked waterphone accents |
| Signature motif | a four-note question (up a minor 3rd, up a semitone, fall a 5th) stated by the music-box and *never* given its resolving fifth note — every section reharmonizes the same unanswered question |

**Structure (target 3:20, evolving):**

1. **0:00 Threshold** — noise bed + one low string pedal; the question motif
   alone on the music-box at 0:20.
2. **0:50 Corridor** — frame drum enters at half-density; strings move in
   slow parallel 5ths under two reharmonized statements of the question.
3. **1:40 Inner chamber** — the closest thing to warmth: glass swells major-
   mode borrow for eight bars, motif in augmentation (double length) —
   the "you almost understood it" moment.
4. **2:30 Retreat** — Phrygian ♭2 returns, layers strip back, waterphone
   accents answer the motif like an echo down a hallway.
5. **3:05 The question, again** — solo music-box, one final unanswered
   statement over the bare noise bed (seam back to Threshold).

## opus — "the magnum opus; the one the credits would roll over"

| | |
|---|---|
| Mood | grand, warm, earned triumph — the signature theme of the whole game; the track a player equips after finishing the climb |
| Tempo | 100 BPM opening, pushing to ~112 at the peak, relaxing back |
| Key/mode | B♭ major, with a IV-minor borrow reserved for the development section |
| Instrumentation | piano-led over full orchestra: solo piano statement, strings in sections, French horn counter-line, light timpani + suspended cymbal for the build, woodwind filigree in the recap |
| Signature motif | "the Opus theme" — an eight-bar singable melody, wide first interval (rising 6th), stated complete in the first 30 seconds; every other section is honestly derived from it (fragment, invert, reharmonize), nothing generic imported |

**Structure (target 4:00, classical arc — A / B / development / recap):**

1. **0:00 A — the theme** — solo piano states the full eight bars, then
   repeats with quiet string halo.
2. **0:55 B — counter-subject** — horns carry a derived counter-line, piano
   moves to accompaniment; first timpani colour.
3. **1:50 Development** — the IV-minor borrow: theme fragments passed
   between sections, harmonically restless, the only minor-shaded stretch;
   builds on a rising string line + cymbal swell.
4. **2:50 Recap, tutti** — the theme full-orchestra at 112 BPM, woodwinds
   adding filigree above; the triumphant peak.
5. **3:30 Coda** — piano alone again, the theme's last four bars slowing
   to the opening tempo (seam: coda piano hands directly back to the A
   statement).

## What acceptance looks like (when production is green-lit)

Per the new-item rule in standards §4, each delivered track must be able to
quote its lines: **≥3:00**, **evolving structure per its section map above**,
**its named motif identifiable blind**, and **mastering parity** with the
rest of the catalogue. A delivered track that is a 60-second loop stretched
to three minutes fails the same way a flat gradient fails the Legendary
ball bar. Grading is by ear against this document — which is only possible
once there is audio to grade, which is Mac's call to make.
