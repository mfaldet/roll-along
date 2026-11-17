# Preset names

Roll Along has no typed text that another player can see. A nickname is two
words from the fixed lists below; a clan name is two words plus a number. The
lists live in `PresetNames` in `RollAlong/SocialClient.swift` and, identically,
in `docs/social-schema-v4.sql`, which makes the database refuse anything else.
**Change both together.**

| | Before (Nov 16) | Now |
|---|---|---|
| Nickname first words | 117 | 173 |
| Nickname second words | 129 | 206 |
| **Distinct nicknames** | **15,093** | **35,638** |
| Clan first words | 165 | 221 |
| Clan second words | 199 | 202 |
| Clan numbers | 995 | 995 |
| **Distinct clan names** | **32,670,825** | **44,418,790** |

- A nickname is `<first word><second word>`, for example `SwiftComet`. It
  has **no number**. Nickname words are five letters or fewer, so a nickname
  never exceeds 10 characters and always fits an in-game name tag with the
  level badge. The default for a signed-in player who has not picked one is
  `Roller`.
- A player's **Adventure level** is shown as part of the name everywhere:
  `SwiftComet` followed by the level badge. The level is not stored in the
  name; it comes from the player's progress.
- A clan name is `<first word> <second word> <number>`, for example
  `Swift Rockets 42`. Its tag is the two initials and the number (`SR42`).
- The clan numbers 69, 88, 420 and 666 are never offered or accepted.
- Nicknames are not unique; the level beside the name tells players apart, and
  friend requests, gifts and clan membership all go by account, never by name.
  Clan names are unique.

## Player and clan second words are separate

No second word is used for both players and clans, in any form: a player word
never appears as a clan word in the singular or the plural ("Wolf" is a
nickname word, so there is no "Wolves" clan). First words may be shared.

To make that true, 130 plural words whose singular is a nickname word
were removed from the clan list, including "Rollers" (the default nickname is
"Roller"):

Acorns, Aspens, Atlases, Bears, Bison, Blazes, Bolts, Brooks, Camels, Cedars, Cliffs, Clouds, Cobras, Comets, Cranes, Creeks, Crows, Cubs, Daisies, Dawns, Deltas, Dingoes, Doves, Drakes, Drifts, Dunes, Eagles, Embers, Ferns, Finches, Fjords, Flames, Flares, Foxes, Frosts, Gales, Geckos, Geese, Gems, Glades, Glows, Groves, Gulls, Hares, Hawks, Heaths, Herons, Hippos, Horses, Ibises, Jets, Kites, Koalas, Koi, Lakes, Larks, Leaves, Lemurs, Llamas, Lotuses, Lynxes, Mangoes, Maples, Marshes, Mesas, Mice, Moons, Moose, Moths, Newts, Novas, Oaks, Oceans, Orbs, Orcas, Otters, Owls, Pandas, Peaks, Pearls, Pilots, Pines, Pixels, Plumes, Ponies, Prisms, Pumas, Quail, Quests, Quills, Racers, Ravens, Reefs, Rhinos, Ridges, Rivers, Robins, Rollers, Rooks, Rovers, Sables, Sharks, Skies, Sloths, Snails, Sparks, Squid, Stags, Stars, Stones, Storks, Storms, Suns, Swans, Tapirs, Tides, Tigers, Torches, Trout, Tulips, Vales, Vipers, Voles, Waves, Whales, Winds, Wolves, Wrens, Yaks, Zebras.

They were replaced by 133 new clan words, all longer words that are not
nickname words in any form.

A test (`testPlayerAndClanSecondWordsShareNoStem`) checks this on every build:
it turns each clan word back into every singular it could come from (-s, -es,
-ies to -y, -ves to -f or -fe, plus a table of irregular plurals such as
Geese, Mice and Leaves) and fails if any of them is a nickname word.

## How the lists were checked

A script built every nickname (35,638 word pairs) and every clan word
pair (44,642) and searched each, lowercased, for about 100
rude or unpleasant letter sequences, including ones that only appear across
the join between two words. Every new word was also read against every word
of the other list by hand for combinations that read badly.

- Words removed because of a hit or a double meaning: Shore (contains "hore"),
  Seed ("ClearSeed" contains "arse"), Igloo ("GreenIgloo" contains a slur
  across the join), Thyme ("LimeThyme"), Butterflies, Compasses, Knights,
  Titans and Iguanas (each contains a blocked sequence), Waterfalls and
  Horizons (blocked sequences across the join).
- Nicknames: no word pair contains any blocked sequence.
- Clan names: no pair contains one as shown (with the space). 39 pairs
  contain one only when the space is taken out (for example "Fearless
  Explorers"). Clan names are always shown with the space, so they were kept.
- Every word is letters only and capitalized; no nickname text can be built
  two ways.

No list is proof against every reading; if a combination bothers you,
removing one word from the list removes it everywhere.

## Nickname first words (173)

Able, Agile, Airy, Alert, Alpha, Amber, Aqua, Astro, Avid, Azure, Balmy, Blue, Bold, Brave, Brisk, Busy, Calm, Chief, Chill, Clear, Comfy, Cool, Coral, Cozy, Crisp, Curly, Cute, Cyan, Daily, Dandy, Deft, Dewy, Dizzy, Dusty, Eager, Early, Elite, Epic, Fair, Fancy, Fast, Fiery, Fine, First, Fizzy, Fleet, Foamy, Fresh, Funny, Fuzzy, Giant, Giddy, Glad, Gold, Goofy, Grand, Great, Green, Gutsy, Handy, Happy, Hardy, Hasty, Hazel, Hefty, Hyper, Icy, Ideal, Inky, Iron, Ivory, Jade, Jazzy, Jolly, Jumbo, Jumpy, Keen, Kind, Kooky, Lanky, Light, Lilac, Lime, Lofty, Loyal, Lucid, Lucky, Lunar, Magic, Major, Mega, Merry, Mild, Mint, Misty, Mocha, Mossy, Neat, Neon, Nifty, Noble, Olive, Onyx, Opal, Peach, Peppy, Pink, Plum, Plush, Polar, Prime, Proud, Pure, Quick, Quiet, Rainy, Rapid, Regal, Retro, Rocky, Rosy, Rowdy, Royal, Ruby, Rusty, Sage, Sandy, Savvy, Shiny, Silky, Silly, Sleek, Smart, Snowy, Snug, Solar, Solid, Sonic, Spry, Stark, Steel, Stony, Sunny, Super, Sweet, Swift, Tame, Tangy, Tawny, Teal, Tidy, Tiny, Topaz, Tough, Trim, True, Turbo, Urban, Vast, Vital, Vivid, Wacky, Warm, Wavy, Wild, Windy, Wise, Witty, Young, Zany, Zen, Zesty, Zippy

New in this revision: Able, Airy, Astro, Balmy, Busy, Chill, Comfy, Curly, Cute, Dewy, Dizzy, Fizzy, Foamy, Fuzzy, Giddy, Goofy, Gutsy, Hasty, Hefty, Hyper, Inky, Jumpy, Kooky, Lanky, Lime, Lofty, Mild, Mocha, Mossy, Peach, Pink, Plum, Plush, Pure, Rainy, Retro, Rocky, Rowdy, Savvy, Silky, Silly, Snug, Stark, Steel, Stony, Sweet, Tame, Tangy, Tawny, Tiny, Tough, Trim, Vital, Wacky, Young, Zany.

## Nickname second words (206)

Acorn, Aspen, Atlas, Bear, Bee, Bison, Blaze, Bloom, Bolt, Brook, Bunny, Calf, Camel, Cedar, Chalk, Charm, Chime, Cliff, Cloud, Coast, Cobra, Colt, Comet, Cove, Crane, Creek, Crest, Crow, Cub, Daisy, Dart, Dawn, Deer, Delta, Dingo, Dove, Drake, Drift, Duck, Dune, Eagle, Echo, Egret, Elk, Elm, Ember, Emu, Fable, Fawn, Fern, Field, Finch, Fjord, Flame, Flare, Flash, Flint, Foal, Forge, Fox, Frog, Frost, Gale, Gecko, Gem, Glade, Glow, Gnome, Gnu, Goose, Grove, Gull, Gust, Hail, Hare, Hawk, Heath, Heron, Hippo, Holly, Horse, Hound, Ibex, Ibis, Inlet, Iris, Ivy, Jay, Jet, Jewel, Kite, Kiwi, Knoll, Koala, Koi, Lake, Lamb, Lark, Leaf, Lemur, Lily, Lion, Llama, Lotus, Lynx, Macaw, Mango, Manta, Maple, Marsh, Mesa, Mink, Mist, Moon, Moose, Moss, Moth, Mouse, Nest, Newt, Nova, Oak, Oasis, Ocean, Okapi, Orb, Orbit, Orca, Otter, Owl, Panda, Peak, Pearl, Petal, Pika, Pilot, Pine, Pixel, Plume, Pluto, Pony, Poppy, Prism, Puma, Pup, Quail, Quark, Quest, Quill, Racer, Radar, Rain, Raven, Ray, Reed, Reef, Rhino, Ridge, River, Robin, Rook, Rover, Sable, Sail, Shark, Sky, Sled, Slope, Sloth, Snail, Spark, Squid, Stag, Star, Stone, Stork, Storm, Sun, Surf, Swan, Tapir, Tern, Tetra, Tide, Tiger, Torch, Trail, Trout, Tulip, Tuna, Twig, Vale, Vapor, Vine, Viper, Vole, Wave, Whale, Wind, Wing, Wolf, Wren, Yak, Yew, Zebra, Zebu

New in this revision: Bee, Bloom, Bunny, Calf, Chalk, Charm, Chime, Coast, Colt, Cove, Crest, Dart, Deer, Duck, Echo, Egret, Elk, Elm, Emu, Fable, Fawn, Field, Flash, Flint, Foal, Forge, Frog, Gnome, Gnu, Gust, Hail, Holly, Hound, Ibex, Inlet, Iris, Ivy, Jay, Jewel, Kiwi, Knoll, Lamb, Lily, Lion, Macaw, Manta, Mink, Mist, Moss, Nest, Oasis, Okapi, Orbit, Petal, Pika, Pluto, Poppy, Pup, Quark, Radar, Rain, Ray, Reed, Sail, Sled, Slope, Surf, Tern, Tetra, Trail, Tuna, Twig, Vapor, Vine, Wing, Yew, Zebu.

## Clan first words (221)

The nickname first words, plus: Ancient, Arctic, Blazing, Bronze, Clever, Cobalt, Copper, Cosmic, Crimson, Crystal, Daring, Electric, Emerald, Endless, Eternal, Fearless, Frosted, Galactic, Gentle, Golden, Granite, Hidden, Humble, Lightning, Lively, Marble, Mellow, Mighty, Modern, Moonlit, Nimble, Radiant, Rainbow, Rising, Roaring, Rolling, Scarlet, Shining, Silver, Soaring, Steady, Stellar, Sunlit, Thunder, Tumbling, Valiant, Vibrant, Wandering.

## Clan second words (202)

Acrobats, Adventurers, Albatrosses, Alchemists, Alligators, Alpacas, Anchors, Antelopes, Architects, Armadillos, Arrows, Artists, Astronauts, Avalanches, Aviators, Badgers, Banners, Beacons, Bells, Blizzards, Bobcats, Boomerangs, Boulders, Breezes, Buccaneers, Buffaloes, Builders, Canyons, Captains, Caribou, Cascades, Champions, Cheetahs, Chinchillas, Chipmunks, Climbers, Commanders, Condors, Craters, Crickets, Crowns, Currents, Cyclones, Dalmatians, Defenders, Diamonds, Dolphins, Dragonflies, Dragons, Dreamers, Drummers, Eclipses, Engineers, Evergreens, Explorers, Falcons, Feathers, Ferrets, Fireflies, Fireworks, Flags, Flamingos, Fountains, Galaxies, Gardens, Gazelles, Gears, Geysers, Gibbons, Giraffes, Glaciers, Gorillas, Griffins, Grizzlies, Guardians, Hammers, Hamsters, Harbors, Hedgehogs, Helmets, Hummingbirds, Huskies, Icebergs, Inventors, Islands, Jackrabbits, Jaguars, Jesters, Jugglers, Jungles, Kangaroos, Kingfishers, Ladybugs, Lagoons, Lanterns, Legends, Leopards, Lighthouses, Lobsters, Magicians, Magnets, Mammoths, Manatees, Marbles, Mariners, Marmots, Mavericks, Meadows, Medals, Meerkats, Meteors, Mirrors, Mongooses, Mountains, Mustangs, Narwhals, Navigators, Nebulas, Ninjas, Nomads, Ocelots, Octopuses, Orangutans, Orchards, Ospreys, Ostriches, Paddles, Paladins, Panthers, Parrots, Pebbles, Pelicans, Penguins, Pennants, Pheasants, Pinwheels, Pioneers, Pirates, Planets, Platypuses, Porcupines, Prairies, Puffins, Puzzles, Pythons, Raccoons, Rainbows, Rangers, Rascals, Redwoods, Ribbons, Riders, Roadrunners, Rockets, Runners, Sailors, Salamanders, Saplings, Sapphires, Satellites, Scouts, Seekers, Sentinels, Sequoias, Shields, Skaters, Skippers, Snowflakes, Sparrows, Sprinters, Sprockets, Squirrels, Starlings, Strikers, Summits, Sunbeams, Telescopes, Tokens, Tornadoes, Tortoises, Toucans, Travelers, Trekkers, Trophies, Trumpets, Tumblers, Turtles, Unicorns, Valleys, Vikings, Volcanoes, Voyagers, Wagons, Walruses, Wanderers, Whistles, Wildcats, Willows, Wizards, Wolverines, Yetis, Zephyrs

New in this revision: Adventurers, Albatrosses, Alchemists, Alligators, Alpacas, Antelopes, Architects, Armadillos, Arrows, Artists, Astronauts, Avalanches, Banners, Beacons, Bells, Blizzards, Bobcats, Boomerangs, Boulders, Buccaneers, Buffaloes, Caribou, Cascades, Cheetahs, Chinchillas, Climbers, Commanders, Condors, Craters, Crickets, Crowns, Currents, Dalmatians, Defenders, Diamonds, Drummers, Eclipses, Engineers, Evergreens, Feathers, Ferrets, Fireworks, Flags, Fountains, Gardens, Gazelles, Gears, Geysers, Gibbons, Giraffes, Gorillas, Grizzlies, Hammers, Helmets, Hummingbirds, Huskies, Icebergs, Jackrabbits, Jesters, Jugglers, Jungles, Kangaroos, Kingfishers, Ladybugs, Lighthouses, Lobsters, Magicians, Magnets, Manatees, Mariners, Marmots, Medals, Meerkats, Mirrors, Mongooses, Mountains, Nebulas, Ninjas, Ocelots, Octopuses, Orangutans, Ospreys, Ostriches, Paddles, Paladins, Pebbles, Pennants, Pheasants, Pinwheels, Pirates, Platypuses, Porcupines, Prairies, Puzzles, Pythons, Rascals, Redwoods, Ribbons, Riders, Roadrunners, Runners, Sailors, Salamanders, Saplings, Sapphires, Satellites, Scouts, Seekers, Sequoias, Shields, Skaters, Skippers, Sprinters, Sprockets, Starlings, Strikers, Telescopes, Tokens, Tornadoes, Tortoises, Travelers, Trekkers, Trophies, Trumpets, Valleys, Vikings, Volcanoes, Wagons, Whistles, Wildcats, Willows, Wolverines, Zephyrs.
