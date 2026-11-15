# Preset names

Roll Along has no typed text that another player can see. Nicknames and clan
names are assembled from the fixed lists below plus a number. The lists live
in `PresetNames` in `RollAlong/SocialClient.swift` and, identically, in
`docs/social-schema-v4.sql`, which makes the database refuse anything else.
**Change both together.**

| | Before | Now |
|---|---|---|
| Nickname first words | 40 | 117 |
| Nickname second words | 40 | 129 |
| Nickname numbers | 99 | 97 |
| **Distinct nicknames** | **158,400** | **1,464,021** |
| Clan first words | 40 | 165 |
| Clan second words | 40 | 199 |
| Clan numbers | 999 | 995 |
| **Distinct clan names** | **1,598,400** | **32,670,825** |

- A nickname is `<first word><second word><number>`, for example
  `SwiftComet42`. Nickname words are five letters or fewer so a nickname never
  exceeds 12 characters.
- A clan name is `<first word> <second word> <number>`, for example
  `Swift Comets 42`. Its tag is the two initials and the number (`SC42`).
- The numbers 69, 88, 420 and 666 are never offered or accepted.
- Nicknames do not have to be unique. Clan names do.

## How the lists were checked

A script built every nickname (15,093 word pairs) and every clan
word pair (32,835) and searched each, lowercased and run
together, for about 100 rude or unpleasant letter sequences, including ones
that only appear across the join between two words. Words that produced a
hit were removed (for example "Ultra", because "UltraPeak" contains one, and
"Seal", because "SolarSeal" does). Words with an obvious double meaning were
left out by hand. No list is proof against every reading; if a combination
bothers you, removing one word from the list removes it everywhere.

Nine clan pairs still contain such a sequence only when the space is taken
out (for example "Fearless Explorers"). Clan names are always shown with the
space, so they were kept.

## Nickname first words (117)

Agile, Alert, Alpha, Amber, Aqua, Avid, Azure, Blue, Bold, Brave, Brisk, Calm, Chief, Clear, Cool, Coral, Cozy, Crisp, Cyan, Daily, Dandy, Deft, Dusty, Eager, Early, Elite, Epic, Fair, Fancy, Fast, Fiery, Fine, First, Fleet, Fresh, Funny, Giant, Glad, Gold, Grand, Great, Green, Handy, Happy, Hardy, Hazel, Icy, Ideal, Iron, Ivory, Jade, Jazzy, Jolly, Jumbo, Keen, Kind, Light, Lilac, Loyal, Lucid, Lucky, Lunar, Magic, Major, Mega, Merry, Mint, Misty, Neat, Neon, Nifty, Noble, Olive, Onyx, Opal, Peppy, Polar, Prime, Proud, Quick, Quiet, Rapid, Regal, Rosy, Royal, Ruby, Rusty, Sage, Sandy, Shiny, Sleek, Smart, Snowy, Solar, Solid, Sonic, Spry, Sunny, Super, Swift, Teal, Tidy, Topaz, True, Turbo, Urban, Vast, Vivid, Warm, Wavy, Wild, Windy, Wise, Witty, Zen, Zesty, Zippy

## Nickname second words (129)

Acorn, Aspen, Atlas, Bear, Bison, Blaze, Bolt, Brook, Camel, Cedar, Cliff, Cloud, Cobra, Comet, Crane, Creek, Crow, Cub, Daisy, Dawn, Delta, Dingo, Dove, Drake, Drift, Dune, Eagle, Ember, Fern, Finch, Fjord, Flame, Flare, Fox, Frost, Gale, Gecko, Gem, Glade, Glow, Goose, Grove, Gull, Hare, Hawk, Heath, Heron, Hippo, Horse, Ibis, Jet, Kite, Koala, Koi, Lake, Lark, Leaf, Lemur, Llama, Lotus, Lynx, Mango, Maple, Marsh, Mesa, Moon, Moose, Moth, Mouse, Newt, Nova, Oak, Ocean, Orb, Orca, Otter, Owl, Panda, Peak, Pearl, Pilot, Pine, Pixel, Plume, Pony, Prism, Puma, Quail, Quest, Quill, Racer, Raven, Reef, Rhino, Ridge, River, Robin, Rook, Rover, Sable, Shark, Sky, Sloth, Snail, Spark, Squid, Stag, Star, Stone, Stork, Storm, Sun, Swan, Tapir, Tide, Tiger, Torch, Trout, Tulip, Vale, Viper, Vole, Wave, Whale, Wind, Wolf, Wren, Yak, Zebra

## Clan first words (165)

The nickname first words, plus: Ancient, Arctic, Blazing, Bronze, Clever, Cobalt, Copper, Cosmic, Crimson, Crystal, Daring, Electric, Emerald, Endless, Eternal, Fearless, Frosted, Galactic, Gentle, Golden, Granite, Hidden, Humble, Lightning, Lively, Marble, Mellow, Mighty, Modern, Moonlit, Nimble, Radiant, Rainbow, Rising, Roaring, Rolling, Scarlet, Shining, Silver, Soaring, Steady, Stellar, Sunlit, Thunder, Tumbling, Valiant, Vibrant, Wandering

## Clan second words (199)

Acorns, Acrobats, Anchors, Aspens, Atlases, Aviators, Badgers, Bears, Bison, Blazes, Bolts, Breezes, Brooks, Builders, Camels, Canyons, Captains, Cedars, Champions, Chipmunks, Cliffs, Clouds, Cobras, Comets, Cranes, Creeks, Crows, Cubs, Cyclones, Daisies, Dawns, Deltas, Dingoes, Dolphins, Doves, Dragonflies, Dragons, Drakes, Dreamers, Drifts, Dunes, Eagles, Embers, Explorers, Falcons, Ferns, Finches, Fireflies, Fjords, Flames, Flamingos, Flares, Foxes, Frosts, Galaxies, Gales, Geckos, Geese, Gems, Glaciers, Glades, Glows, Griffins, Groves, Guardians, Gulls, Hamsters, Harbors, Hares, Hawks, Heaths, Hedgehogs, Herons, Hippos, Horses, Ibises, Inventors, Islands, Jaguars, Jets, Kites, Koalas, Koi, Lagoons, Lakes, Lanterns, Larks, Leaves, Legends, Lemurs, Leopards, Llamas, Lotuses, Lynxes, Mammoths, Mangoes, Maples, Marbles, Marshes, Mavericks, Meadows, Mesas, Meteors, Mice, Moons, Moose, Moths, Mustangs, Narwhals, Navigators, Newts, Nomads, Novas, Oaks, Oceans, Orbs, Orcas, Orchards, Otters, Owls, Pandas, Panthers, Parrots, Peaks, Pearls, Pelicans, Penguins, Pilots, Pines, Pioneers, Pixels, Planets, Plumes, Ponies, Prisms, Puffins, Pumas, Quail, Quests, Quills, Raccoons, Racers, Rainbows, Rangers, Ravens, Reefs, Rhinos, Ridges, Rivers, Robins, Rockets, Rollers, Rooks, Rovers, Sables, Sentinels, Sharks, Skies, Sloths, Snails, Snowflakes, Sparks, Sparrows, Squid, Squirrels, Stags, Stars, Stones, Storks, Storms, Summits, Sunbeams, Suns, Swans, Tapirs, Tides, Tigers, Torches, Toucans, Trout, Tulips, Tumblers, Turtles, Unicorns, Vales, Vipers, Voles, Voyagers, Walruses, Wanderers, Waves, Whales, Winds, Wizards, Wolves, Wrens, Yaks, Yetis, Zebras
