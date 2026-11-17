# Minigame preview clips

Home → Game Modes → **Minigames** opens a two-column grid of every minigame.
Pressing and holding a tile plays that game's preview clip, muted and
looping, until the finger lifts. A quick tap still chooses the game. A game
with no clip shows its icon; nothing breaks if a clip is missing.

## What to record

| | |
|---|---|
| **Length** | 4 to 6 seconds. It loops, so a stretch that ends roughly where it started looks best. |
| **Shape** | Portrait **4:5** (width : height). The tile is 4:5, and a clip of any other shape is cropped to fill it. |
| **Resolution** | At least **720 × 900** pixels. A tile is about 160 to 195 points wide depending on the iPhone (up to about 580 × 730 pixels on screen), so more than 1080 × 1350 is wasted. |
| **Format** | What an iPhone screen recording gives you: H.264 or HEVC video in a **.mov** or **.mp4** file (**.m4v** also works). |
| **Sound** | Not needed. Clips always play muted. |
| **File size** | Keep each under about 3 MB. Every clip makes the app download bigger. |

## File names

One clip per game, named `clip_` plus the game's id:

| Game | File name |
|---|---|
| Roll Up | `clip_rollup.mov` |
| Disco Ball | `clip_disco.mov` |
| Comet Clash | `clip_snake.mov` |
| Sumo Survival | `clip_sumo.mov` |
| Paint Ball | `clip_paintball.mov` |
| Smash and Grab | `clip_goldrush.mov` |
| Marble Cup | `clip_marblecup.mov` |
| King of the Hill | `clip_koth.mov` |
| Gold Rush | `clip_coinpit.mov` |
| Zen Garden | `clip_zen.mov` |

Two names look swapped but are right: **Smash and Grab is `goldrush`** and
**Gold Rush is `coinpit`** (the games were renamed; their ids were not).
`.mp4` instead of `.mov` is fine for any of them. Roll Out is held back from
1.0; when it returns its clip will be `clip_rollout.mov`.

## Where they go

In the project folder: `RollAlong/MinigameClips/`. In Xcode it shows as a
blue folder called **MinigameClips**. Xcode copies everything in that folder
into the app, so adding a clip needs no change to the project.

## How to make and add one

1. On the iPhone, open Control Center and tap **Screen Recording**.
2. Play a few seconds of the game, then stop the recording.
3. In Photos, open the recording and tap **Edit**.
4. Drag the ends of the timeline to keep 4 to 6 seconds.
5. Tap the crop button, tap the aspect-ratio button, choose **8:10**, and make
   sure it is taller than wide (tap the portrait/landscape toggle if needed).
   Frame the action, then tap **Done**.
6. AirDrop the clip to the Mac. It lands in Downloads.
7. Rename it to the file name from the table above, for example
   `clip_rollup.mov`.
8. In Finder, open the project folder, then `RollAlong`, then `MinigameClips`,
   and drag the file in.
9. In Xcode, choose **Product → Clean Build Folder** (needed once after adding
   files to the folder), then run on the phone.

To replace a clip, drop the new file in with the same name, replacing the
old one, and repeat step 9.

## How to check it plays

1. On the phone: Home → Game Modes → Minigames.
2. Press and hold the game's tile. After about a third of a second the clip
   plays inside the tile, with the game's name along the bottom.
3. Lift your finger: the icon comes back and the game is **not** chosen.
4. Tap the tile normally: the game is chosen and you return Home.

If holding shows nothing, check the file name (it must match the table
exactly, including lowercase) and that the file is inside `MinigameClips`.
