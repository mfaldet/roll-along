Comet Clash — held back (replaced by Snacky in version 1.0)

SnakeGameView.swift here is the Comet Clash game as it was on 2026-11-18,
kept for reference the same way tools/pinball/ keeps Pinball. It is NOT in
any Xcode target and is not built into the app.

In the app, RollAlong/SnakeGameView.swift now holds Snacky (struct
SnackyView). Snacky kept Comet Clash's internal mode id "snake", so its
leaderboard rows, trophies and analytics continue under that id.

To bring Comet Clash back as a separate mode it would need its own mode id,
a new struct name (this file still declares `SnakeGameView`), its map data
(CometClashMaps in RollAlong/MinigameMaps.swift is still there) and its
tuning constants (removed from OpponentTuning on 2026-11-18; see git history).
