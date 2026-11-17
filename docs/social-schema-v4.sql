-- ===========================================================================
-- Roll Along — social schema v4: PRESET NAMES ONLY (no free text).
--
-- A NICKNAME is two preset words and nothing else ('SwiftComet').  It has no
-- number and does not need to be unique; the app shows the player's
-- Adventure level beside it.  A CLAN NAME is two words and a number
-- ('Swift Rockets 42') and is unique.
--
-- GENERATED from the same word lists as `PresetNames` in
-- RollAlong/SocialClient.swift.  Change both together.
--
-- What this does
--   1. Rewrites any existing free-text value to a preset-format one:
--        players.display_name  -> the same two words without the number when
--                                 it is an old-format nickname
--                                 ('SwiftComet42' -> 'SwiftComet'), else 'Roller'
--        clans.name            -> 'Swift Rockets <n>'  (n unique per clan)
--        clans.tag             -> derived from the name (two initials + number)
--        clans.description     -> ''
--   2. Adds CHECK constraints so the database itself refuses anything that is
--      not assembled from the preset lists — a modified client cannot store
--      free text with the public key.
--
-- Run ONCE in the Supabase SQL editor, after the earlier schema files.
-- It is safe to re-run.  Section 1 changes existing rows: read it first.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0 · Validators
-- ---------------------------------------------------------------------------
create or replace function public.ra_is_preset_nickname(n text)
returns boolean language sql immutable as $$
    select n = 'Roller'
        or n ~ '^(Able|Agile|Airy|Alert|Alpha|Amber|Aqua|Astro|Avid|Azure|Balmy|Blue|Bold|Brave|Brisk|Busy|Calm|Chief|Chill|Clear|Comfy|Cool|Coral|Cozy|Crisp|Curly|Cute|Cyan|Daily|Dandy|Deft|Dewy|Dizzy|Dusty|Eager|Early|Elite|Epic|Fair|Fancy|Fast|Fiery|Fine|First|Fizzy|Fleet|Foamy|Fresh|Funny|Fuzzy|Giant|Giddy|Glad|Gold|Goofy|Grand|Great|Green|Gutsy|Handy|Happy|Hardy|Hasty|Hazel|Hefty|Hyper|Icy|Ideal|Inky|Iron|Ivory|Jade|Jazzy|Jolly|Jumbo|Jumpy|Keen|Kind|Kooky|Lanky|Light|Lilac|Lime|Lofty|Loyal|Lucid|Lucky|Lunar|Magic|Major|Mega|Merry|Mild|Mint|Misty|Mocha|Mossy|Neat|Neon|Nifty|Noble|Olive|Onyx|Opal|Peach|Peppy|Pink|Plum|Plush|Polar|Prime|Proud|Pure|Quick|Quiet|Rainy|Rapid|Regal|Retro|Rocky|Rosy|Rowdy|Royal|Ruby|Rusty|Sage|Sandy|Savvy|Shiny|Silky|Silly|Sleek|Smart|Snowy|Snug|Solar|Solid|Sonic|Spry|Stark|Steel|Stony|Sunny|Super|Sweet|Swift|Tame|Tangy|Tawny|Teal|Tidy|Tiny|Topaz|Tough|Trim|True|Turbo|Urban|Vast|Vital|Vivid|Wacky|Warm|Wavy|Wild|Windy|Wise|Witty|Young|Zany|Zen|Zesty|Zippy)(Acorn|Aspen|Atlas|Bear|Bee|Bison|Blaze|Bloom|Bolt|Brook|Bunny|Calf|Camel|Cedar|Chalk|Charm|Chime|Cliff|Cloud|Coast|Cobra|Colt|Comet|Cove|Crane|Creek|Crest|Crow|Cub|Daisy|Dart|Dawn|Deer|Delta|Dingo|Dove|Drake|Drift|Duck|Dune|Eagle|Echo|Egret|Elk|Elm|Ember|Emu|Fable|Fawn|Fern|Field|Finch|Fjord|Flame|Flare|Flash|Flint|Foal|Forge|Fox|Frog|Frost|Gale|Gecko|Gem|Glade|Glow|Gnome|Gnu|Goose|Grove|Gull|Gust|Hail|Hare|Hawk|Heath|Heron|Hippo|Holly|Horse|Hound|Ibex|Ibis|Inlet|Iris|Ivy|Jay|Jet|Jewel|Kite|Kiwi|Knoll|Koala|Koi|Lake|Lamb|Lark|Leaf|Lemur|Lily|Lion|Llama|Lotus|Lynx|Macaw|Mango|Manta|Maple|Marsh|Mesa|Mink|Mist|Moon|Moose|Moss|Moth|Mouse|Nest|Newt|Nova|Oak|Oasis|Ocean|Okapi|Orb|Orbit|Orca|Otter|Owl|Panda|Peak|Pearl|Petal|Pika|Pilot|Pine|Pixel|Plume|Pluto|Pony|Poppy|Prism|Puma|Pup|Quail|Quark|Quest|Quill|Racer|Radar|Rain|Raven|Ray|Reed|Reef|Rhino|Ridge|River|Robin|Rook|Rover|Sable|Sail|Shark|Sky|Sled|Slope|Sloth|Snail|Spark|Squid|Stag|Star|Stone|Stork|Storm|Sun|Surf|Swan|Tapir|Tern|Tetra|Tide|Tiger|Torch|Trail|Trout|Tulip|Tuna|Twig|Vale|Vapor|Vine|Viper|Vole|Wave|Whale|Wind|Wing|Wolf|Wren|Yak|Yew|Zebra|Zebu)$'
$$;

-- A nickname in the format used BEFORE numbers were dropped
-- (<first word><second word><1-99>, e.g. 'SwiftComet42'): returns the two
-- words ('SwiftComet').  Returns null for anything else.
create or replace function public.ra_old_nickname_words(n text)
returns text language sql immutable as $$
    select case when n ~ '^(Able|Agile|Airy|Alert|Alpha|Amber|Aqua|Astro|Avid|Azure|Balmy|Blue|Bold|Brave|Brisk|Busy|Calm|Chief|Chill|Clear|Comfy|Cool|Coral|Cozy|Crisp|Curly|Cute|Cyan|Daily|Dandy|Deft|Dewy|Dizzy|Dusty|Eager|Early|Elite|Epic|Fair|Fancy|Fast|Fiery|Fine|First|Fizzy|Fleet|Foamy|Fresh|Funny|Fuzzy|Giant|Giddy|Glad|Gold|Goofy|Grand|Great|Green|Gutsy|Handy|Happy|Hardy|Hasty|Hazel|Hefty|Hyper|Icy|Ideal|Inky|Iron|Ivory|Jade|Jazzy|Jolly|Jumbo|Jumpy|Keen|Kind|Kooky|Lanky|Light|Lilac|Lime|Lofty|Loyal|Lucid|Lucky|Lunar|Magic|Major|Mega|Merry|Mild|Mint|Misty|Mocha|Mossy|Neat|Neon|Nifty|Noble|Olive|Onyx|Opal|Peach|Peppy|Pink|Plum|Plush|Polar|Prime|Proud|Pure|Quick|Quiet|Rainy|Rapid|Regal|Retro|Rocky|Rosy|Rowdy|Royal|Ruby|Rusty|Sage|Sandy|Savvy|Shiny|Silky|Silly|Sleek|Smart|Snowy|Snug|Solar|Solid|Sonic|Spry|Stark|Steel|Stony|Sunny|Super|Sweet|Swift|Tame|Tangy|Tawny|Teal|Tidy|Tiny|Topaz|Tough|Trim|True|Turbo|Urban|Vast|Vital|Vivid|Wacky|Warm|Wavy|Wild|Windy|Wise|Witty|Young|Zany|Zen|Zesty|Zippy)(Acorn|Aspen|Atlas|Bear|Bee|Bison|Blaze|Bloom|Bolt|Brook|Bunny|Calf|Camel|Cedar|Chalk|Charm|Chime|Cliff|Cloud|Coast|Cobra|Colt|Comet|Cove|Crane|Creek|Crest|Crow|Cub|Daisy|Dart|Dawn|Deer|Delta|Dingo|Dove|Drake|Drift|Duck|Dune|Eagle|Echo|Egret|Elk|Elm|Ember|Emu|Fable|Fawn|Fern|Field|Finch|Fjord|Flame|Flare|Flash|Flint|Foal|Forge|Fox|Frog|Frost|Gale|Gecko|Gem|Glade|Glow|Gnome|Gnu|Goose|Grove|Gull|Gust|Hail|Hare|Hawk|Heath|Heron|Hippo|Holly|Horse|Hound|Ibex|Ibis|Inlet|Iris|Ivy|Jay|Jet|Jewel|Kite|Kiwi|Knoll|Koala|Koi|Lake|Lamb|Lark|Leaf|Lemur|Lily|Lion|Llama|Lotus|Lynx|Macaw|Mango|Manta|Maple|Marsh|Mesa|Mink|Mist|Moon|Moose|Moss|Moth|Mouse|Nest|Newt|Nova|Oak|Oasis|Ocean|Okapi|Orb|Orbit|Orca|Otter|Owl|Panda|Peak|Pearl|Petal|Pika|Pilot|Pine|Pixel|Plume|Pluto|Pony|Poppy|Prism|Puma|Pup|Quail|Quark|Quest|Quill|Racer|Radar|Rain|Raven|Ray|Reed|Reef|Rhino|Ridge|River|Robin|Rook|Rover|Sable|Sail|Shark|Sky|Sled|Slope|Sloth|Snail|Spark|Squid|Stag|Star|Stone|Stork|Storm|Sun|Surf|Swan|Tapir|Tern|Tetra|Tide|Tiger|Torch|Trail|Trout|Tulip|Tuna|Twig|Vale|Vapor|Vine|Viper|Vole|Wave|Whale|Wind|Wing|Wolf|Wren|Yak|Yew|Zebra|Zebu)([1-9][0-9]?)$'
                 and substring(n from '[0-9]+$')::int not in (69, 88)
                then regexp_replace(n, '[0-9]+$', '')
                else null end
$$;

create or replace function public.ra_is_preset_clan_name(n text)
returns boolean language sql immutable as $$
    select case when n ~ '^(Able|Agile|Airy|Alert|Alpha|Amber|Ancient|Aqua|Arctic|Astro|Avid|Azure|Balmy|Blazing|Blue|Bold|Brave|Brisk|Bronze|Busy|Calm|Chief|Chill|Clear|Clever|Cobalt|Comfy|Cool|Copper|Coral|Cosmic|Cozy|Crimson|Crisp|Crystal|Curly|Cute|Cyan|Daily|Dandy|Daring|Deft|Dewy|Dizzy|Dusty|Eager|Early|Electric|Elite|Emerald|Endless|Epic|Eternal|Fair|Fancy|Fast|Fearless|Fiery|Fine|First|Fizzy|Fleet|Foamy|Fresh|Frosted|Funny|Fuzzy|Galactic|Gentle|Giant|Giddy|Glad|Gold|Golden|Goofy|Grand|Granite|Great|Green|Gutsy|Handy|Happy|Hardy|Hasty|Hazel|Hefty|Hidden|Humble|Hyper|Icy|Ideal|Inky|Iron|Ivory|Jade|Jazzy|Jolly|Jumbo|Jumpy|Keen|Kind|Kooky|Lanky|Light|Lightning|Lilac|Lime|Lively|Lofty|Loyal|Lucid|Lucky|Lunar|Magic|Major|Marble|Mega|Mellow|Merry|Mighty|Mild|Mint|Misty|Mocha|Modern|Moonlit|Mossy|Neat|Neon|Nifty|Nimble|Noble|Olive|Onyx|Opal|Peach|Peppy|Pink|Plum|Plush|Polar|Prime|Proud|Pure|Quick|Quiet|Radiant|Rainbow|Rainy|Rapid|Regal|Retro|Rising|Roaring|Rocky|Rolling|Rosy|Rowdy|Royal|Ruby|Rusty|Sage|Sandy|Savvy|Scarlet|Shining|Shiny|Silky|Silly|Silver|Sleek|Smart|Snowy|Snug|Soaring|Solar|Solid|Sonic|Spry|Stark|Steady|Steel|Stellar|Stony|Sunlit|Sunny|Super|Sweet|Swift|Tame|Tangy|Tawny|Teal|Thunder|Tidy|Tiny|Topaz|Tough|Trim|True|Tumbling|Turbo|Urban|Valiant|Vast|Vibrant|Vital|Vivid|Wacky|Wandering|Warm|Wavy|Wild|Windy|Wise|Witty|Young|Zany|Zen|Zesty|Zippy) (Acrobats|Adventurers|Albatrosses|Alchemists|Alligators|Alpacas|Anchors|Antelopes|Architects|Armadillos|Arrows|Artists|Astronauts|Avalanches|Aviators|Badgers|Banners|Beacons|Bells|Blizzards|Bobcats|Boomerangs|Boulders|Breezes|Buccaneers|Buffaloes|Builders|Canyons|Captains|Caribou|Cascades|Champions|Cheetahs|Chinchillas|Chipmunks|Climbers|Commanders|Condors|Craters|Crickets|Crowns|Currents|Cyclones|Dalmatians|Defenders|Diamonds|Dolphins|Dragonflies|Dragons|Dreamers|Drummers|Eclipses|Engineers|Evergreens|Explorers|Falcons|Feathers|Ferrets|Fireflies|Fireworks|Flags|Flamingos|Fountains|Galaxies|Gardens|Gazelles|Gears|Geysers|Gibbons|Giraffes|Glaciers|Gorillas|Griffins|Grizzlies|Guardians|Hammers|Hamsters|Harbors|Hedgehogs|Helmets|Hummingbirds|Huskies|Icebergs|Inventors|Islands|Jackrabbits|Jaguars|Jesters|Jugglers|Jungles|Kangaroos|Kingfishers|Ladybugs|Lagoons|Lanterns|Legends|Leopards|Lighthouses|Lobsters|Magicians|Magnets|Mammoths|Manatees|Marbles|Mariners|Marmots|Mavericks|Meadows|Medals|Meerkats|Meteors|Mirrors|Mongooses|Mountains|Mustangs|Narwhals|Navigators|Nebulas|Ninjas|Nomads|Ocelots|Octopuses|Orangutans|Orchards|Ospreys|Ostriches|Paddles|Paladins|Panthers|Parrots|Pebbles|Pelicans|Penguins|Pennants|Pheasants|Pinwheels|Pioneers|Pirates|Planets|Platypuses|Porcupines|Prairies|Puffins|Puzzles|Pythons|Raccoons|Rainbows|Rangers|Rascals|Redwoods|Ribbons|Riders|Roadrunners|Rockets|Runners|Sailors|Salamanders|Saplings|Sapphires|Satellites|Scouts|Seekers|Sentinels|Sequoias|Shields|Skaters|Skippers|Snowflakes|Sparrows|Sprinters|Sprockets|Squirrels|Starlings|Strikers|Summits|Sunbeams|Telescopes|Tokens|Tornadoes|Tortoises|Toucans|Travelers|Trekkers|Trophies|Trumpets|Tumblers|Turtles|Unicorns|Valleys|Vikings|Volcanoes|Voyagers|Wagons|Walruses|Wanderers|Whistles|Wildcats|Willows|Wizards|Wolverines|Yetis|Zephyrs) ([1-9][0-9]{0,2})$'
                then split_part(n, ' ', 3)::int not in (69, 88, 420, 666)
                else false end
$$;

-- The tag is derived from the name: two initials + the number ("SR42").
create or replace function public.ra_clan_tag_for(n text)
returns text language sql immutable as $$
    select upper(left(split_part(n, ' ', 1), 1) || left(split_part(n, ' ', 2), 1))
           || split_part(n, ' ', 3)
$$;

create or replace function public.ra_is_preset_clan_description(d text)
returns boolean language sql immutable as $$
    select d = '' or d in (
        'Friendly clan. Everyone is welcome.',
        'Daily players who share lives.',
        'Casual players. No pressure.',
        'Chasing the top of the leaderboard.',
        'Minigame fans.',
        'Trophy hunters.',
        'Friends and family.',
        'New players welcome. We help each other out.'
    )
$$;

-- ---------------------------------------------------------------------------
-- 0b · Tags no longer need to be unique
-- ---------------------------------------------------------------------------
-- A derived tag is two initials + the number, so two different names can share
-- one ("Swift Rockets 42" and "Solar Rangers 42" are both SR42).  The NAME index
-- already guarantees clans are unique; keeping the tag index would reject
-- free names as "taken".
drop index if exists public.clans_tag_unique_idx;

-- ---------------------------------------------------------------------------
-- 1 · Rewrite existing rows that are not preset-format
-- ---------------------------------------------------------------------------
-- Players.  The nickname rule may already be in place from an earlier run of
-- this file with the old format (two words and a number), so lift it first.
alter table public.players drop constraint if exists players_display_name_preset;

-- An old-format nickname keeps its two words and loses the number
-- ('SwiftComet42' -> 'SwiftComet').  Anything else that is not a preset
-- nickname (free text) becomes 'Roller'.  Valid nicknames are not touched.
update public.players
   set display_name = coalesce(public.ra_old_nickname_words(display_name), 'Roller')
 where not public.ra_is_preset_nickname(display_name);

-- Clans: give each non-conforming clan the first free 'Swift Rockets <n>'.
do $$
declare
    c record;
    n int := 0;
    candidate text;
begin
    for c in select id from public.clans
              where not public.ra_is_preset_clan_name(name)
              order by created_at
    loop
        loop
            n := n + 1;
            if n > 999 then raise exception 'ran out of fallback clan names'; end if;
            candidate := 'Swift Rockets ' || n;
            exit when public.ra_is_preset_clan_name(candidate)   -- skips the blocked numbers
                  and not exists (
                select 1 from public.clans
                 where lower(name) = lower(candidate));
        end loop;
        update public.clans
           set name = candidate, tag = public.ra_clan_tag_for(candidate)
         where id = c.id;
    end loop;
end $$;

-- Clans whose NAME was already preset-format but whose tag is not the derived one.
update public.clans
   set tag = public.ra_clan_tag_for(name)
 where tag <> public.ra_clan_tag_for(name);

update public.clans
   set description = ''
 where not public.ra_is_preset_clan_description(description);

-- ---------------------------------------------------------------------------
-- 2 · Constraints (the database refuses free text from now on)
-- ---------------------------------------------------------------------------
alter table public.players drop constraint if exists players_display_name_preset;
alter table public.players add  constraint players_display_name_preset
    check (public.ra_is_preset_nickname(display_name));

alter table public.clans drop constraint if exists clans_name_preset;
alter table public.clans add  constraint clans_name_preset
    check (public.ra_is_preset_clan_name(name));

alter table public.clans drop constraint if exists clans_tag_derived;
alter table public.clans add  constraint clans_tag_derived
    check (tag = public.ra_clan_tag_for(name));

alter table public.clans drop constraint if exists clans_description_preset;
alter table public.clans add  constraint clans_description_preset
    check (public.ra_is_preset_clan_description(description));

-- ---------------------------------------------------------------------------
-- 3 · Check (should return three zeros)
-- ---------------------------------------------------------------------------
select
    (select count(*) from public.players where not public.ra_is_preset_nickname(display_name))      as bad_nicknames,
    (select count(*) from public.clans   where not public.ra_is_preset_clan_name(name)
                                             or tag <> public.ra_clan_tag_for(name))               as bad_clan_names_or_tags,
    (select count(*) from public.clans   where not public.ra_is_preset_clan_description(description)) as bad_descriptions;
