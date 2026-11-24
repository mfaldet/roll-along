# Publishing the level pack

Adventure levels live in one file, the level pack. A copy ships inside the app
(`RollAlong/LevelOverrides.json`). From version 1.1 the game also looks for a
newer pack on the game's website each time it starts:

    https://mfaldet.github.io/roll-along/levels/level-pack.json

The address is one constant, `LevelPackStore.remoteURL` in
`RollAlong/LevelLayout.swift`.

## What the game does

1. At launch it uses the newest accepted pack it already holds: the pack from
   an earlier download, or else the one inside the app.
2. In the background it downloads the published file. If the file is accepted
   it is saved and used **from the next launch**. A pack never changes during
   a run.
3. If the download fails, or the file is refused, the game keeps the pack it
   has. Nothing is shown to the player.

## When a published pack is accepted

All four must hold. Otherwise the game keeps the pack it has.

1. The file parses completely. One level that cannot be read refuses the
   whole file. The file must state `packVersion`.
2. Its `packVersion` is higher than the pack in use.
3. It contains every level from 1 to its last, with no gaps.
4. It has at least as many levels as the pack in use.

Because of rule 4 a published pack can add levels and change levels, but can
never take a level away, so it never removes a player's progress.

## How to publish

The website is the `gh-pages` branch of this repository.

1. Export the pack from Marble Mapper as usual.
2. Raise `packVersion` in the file by one. Every level must carry its own
   `targetTime` and `goldTime`; the game uses them exactly as written.
3. Check it:

       node scripts/verify-levels.mjs path/to/the/pack.json

   Fix anything it reports as BROKEN.
4. Put the same file in two places:
   - `RollAlong/LevelOverrides.json` on the working branch, so the next app
     version ships it;
   - `levels/level-pack.json` on the `gh-pages` branch, so players get it now.
5. Commit and push `gh-pages`. The file is live within a few minutes. Open the
   address above in a browser to confirm.

Only players on version 1.1 or later download packs. Version 1.0 uses the
levels it shipped with.

## How to check it in the simulator

Settings > Debug (debug builds only):

- **Check for a published level pack now** downloads the file and shows the
  result in plain words under the buttons.
- The line under the buttons shows the version in use, how many levels it
  has, and whether it came from the app or from a download.
- **Forget the downloaded level pack** removes a saved download, so the next
  launch uses the pack inside the app again.

## Taking a published pack back

Publish a new file with a higher `packVersion` and the levels you want.
Publishing a lower version does nothing: phones that already hold the higher
one keep it. Deleting the published file also does nothing for phones that
already downloaded it.
