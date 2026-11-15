-- ===========================================================================
-- Roll Along — social schema v4: PRESET NAMES ONLY (no free text).
--
-- GENERATED from the same word lists as `PresetNames` in
-- RollAlong/SocialClient.swift.  Change both together.
--
-- What this does
--   1. Rewrites any existing free-text value to a preset-format one:
--        players.display_name  -> 'Roller'
--        clans.name            -> 'Swift Comets <n>'  (n unique per clan)
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
        or case when n ~ '^(Agile|Alert|Alpha|Amber|Aqua|Avid|Azure|Blue|Bold|Brave|Brisk|Calm|Chief|Clear|Cool|Coral|Cozy|Crisp|Cyan|Daily|Dandy|Deft|Dusty|Eager|Early|Elite|Epic|Fair|Fancy|Fast|Fiery|Fine|First|Fleet|Fresh|Funny|Giant|Glad|Gold|Grand|Great|Green|Handy|Happy|Hardy|Hazel|Icy|Ideal|Iron|Ivory|Jade|Jazzy|Jolly|Jumbo|Keen|Kind|Light|Lilac|Loyal|Lucid|Lucky|Lunar|Magic|Major|Mega|Merry|Mint|Misty|Neat|Neon|Nifty|Noble|Olive|Onyx|Opal|Peppy|Polar|Prime|Proud|Quick|Quiet|Rapid|Regal|Rosy|Royal|Ruby|Rusty|Sage|Sandy|Shiny|Sleek|Smart|Snowy|Solar|Solid|Sonic|Spry|Sunny|Super|Swift|Teal|Tidy|Topaz|True|Turbo|Urban|Vast|Vivid|Warm|Wavy|Wild|Windy|Wise|Witty|Zen|Zesty|Zippy)(Acorn|Aspen|Atlas|Bear|Bison|Blaze|Bolt|Brook|Camel|Cedar|Cliff|Cloud|Cobra|Comet|Crane|Creek|Crow|Cub|Daisy|Dawn|Delta|Dingo|Dove|Drake|Drift|Dune|Eagle|Ember|Fern|Finch|Fjord|Flame|Flare|Fox|Frost|Gale|Gecko|Gem|Glade|Glow|Goose|Grove|Gull|Hare|Hawk|Heath|Heron|Hippo|Horse|Ibis|Jet|Kite|Koala|Koi|Lake|Lark|Leaf|Lemur|Llama|Lotus|Lynx|Mango|Maple|Marsh|Mesa|Moon|Moose|Moth|Mouse|Newt|Nova|Oak|Ocean|Orb|Orca|Otter|Owl|Panda|Peak|Pearl|Pilot|Pine|Pixel|Plume|Pony|Prism|Puma|Quail|Quest|Quill|Racer|Raven|Reef|Rhino|Ridge|River|Robin|Rook|Rover|Sable|Shark|Sky|Sloth|Snail|Spark|Squid|Stag|Star|Stone|Stork|Storm|Sun|Swan|Tapir|Tide|Tiger|Torch|Trout|Tulip|Vale|Viper|Vole|Wave|Whale|Wind|Wolf|Wren|Yak|Zebra)([1-9][0-9]?)$'
                then substring(n from '[0-9]+$')::int not in (69, 88)
                else false end
$$;

create or replace function public.ra_is_preset_clan_name(n text)
returns boolean language sql immutable as $$
    select case when n ~ '^(Agile|Alert|Alpha|Amber|Ancient|Aqua|Arctic|Avid|Azure|Blazing|Blue|Bold|Brave|Brisk|Bronze|Calm|Chief|Clear|Clever|Cobalt|Cool|Copper|Coral|Cosmic|Cozy|Crimson|Crisp|Crystal|Cyan|Daily|Dandy|Daring|Deft|Dusty|Eager|Early|Electric|Elite|Emerald|Endless|Epic|Eternal|Fair|Fancy|Fast|Fearless|Fiery|Fine|First|Fleet|Fresh|Frosted|Funny|Galactic|Gentle|Giant|Glad|Gold|Golden|Grand|Granite|Great|Green|Handy|Happy|Hardy|Hazel|Hidden|Humble|Icy|Ideal|Iron|Ivory|Jade|Jazzy|Jolly|Jumbo|Keen|Kind|Light|Lightning|Lilac|Lively|Loyal|Lucid|Lucky|Lunar|Magic|Major|Marble|Mega|Mellow|Merry|Mighty|Mint|Misty|Modern|Moonlit|Neat|Neon|Nifty|Nimble|Noble|Olive|Onyx|Opal|Peppy|Polar|Prime|Proud|Quick|Quiet|Radiant|Rainbow|Rapid|Regal|Rising|Roaring|Rolling|Rosy|Royal|Ruby|Rusty|Sage|Sandy|Scarlet|Shining|Shiny|Silver|Sleek|Smart|Snowy|Soaring|Solar|Solid|Sonic|Spry|Steady|Stellar|Sunlit|Sunny|Super|Swift|Teal|Thunder|Tidy|Topaz|True|Tumbling|Turbo|Urban|Valiant|Vast|Vibrant|Vivid|Wandering|Warm|Wavy|Wild|Windy|Wise|Witty|Zen|Zesty|Zippy) (Acorns|Acrobats|Anchors|Aspens|Atlases|Aviators|Badgers|Bears|Bison|Blazes|Bolts|Breezes|Brooks|Builders|Camels|Canyons|Captains|Cedars|Champions|Chipmunks|Cliffs|Clouds|Cobras|Comets|Cranes|Creeks|Crows|Cubs|Cyclones|Daisies|Dawns|Deltas|Dingoes|Dolphins|Doves|Dragonflies|Dragons|Drakes|Dreamers|Drifts|Dunes|Eagles|Embers|Explorers|Falcons|Ferns|Finches|Fireflies|Fjords|Flames|Flamingos|Flares|Foxes|Frosts|Galaxies|Gales|Geckos|Geese|Gems|Glaciers|Glades|Glows|Griffins|Groves|Guardians|Gulls|Hamsters|Harbors|Hares|Hawks|Heaths|Hedgehogs|Herons|Hippos|Horses|Ibises|Inventors|Islands|Jaguars|Jets|Kites|Koalas|Koi|Lagoons|Lakes|Lanterns|Larks|Leaves|Legends|Lemurs|Leopards|Llamas|Lotuses|Lynxes|Mammoths|Mangoes|Maples|Marbles|Marshes|Mavericks|Meadows|Mesas|Meteors|Mice|Moons|Moose|Moths|Mustangs|Narwhals|Navigators|Newts|Nomads|Novas|Oaks|Oceans|Orbs|Orcas|Orchards|Otters|Owls|Pandas|Panthers|Parrots|Peaks|Pearls|Pelicans|Penguins|Pilots|Pines|Pioneers|Pixels|Planets|Plumes|Ponies|Prisms|Puffins|Pumas|Quail|Quests|Quills|Raccoons|Racers|Rainbows|Rangers|Ravens|Reefs|Rhinos|Ridges|Rivers|Robins|Rockets|Rollers|Rooks|Rovers|Sables|Sentinels|Sharks|Skies|Sloths|Snails|Snowflakes|Sparks|Sparrows|Squid|Squirrels|Stags|Stars|Stones|Storks|Storms|Summits|Sunbeams|Suns|Swans|Tapirs|Tides|Tigers|Torches|Toucans|Trout|Tulips|Tumblers|Turtles|Unicorns|Vales|Vipers|Voles|Voyagers|Walruses|Wanderers|Waves|Whales|Winds|Wizards|Wolves|Wrens|Yaks|Yetis|Zebras) ([1-9][0-9]{0,2})$'
                then split_part(n, ' ', 3)::int not in (69, 88, 420, 666)
                else false end
$$;

-- The tag is derived from the name: two initials + the number ("SC42").
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
-- one ("Swift Comets 42" and "Solar Cedars 42" are both SC42).  The NAME index
-- already guarantees clans are unique; keeping the tag index would reject
-- free names as "taken".
drop index if exists public.clans_tag_unique_idx;

-- ---------------------------------------------------------------------------
-- 1 · Rewrite existing rows that are not preset-format
-- ---------------------------------------------------------------------------
update public.players
   set display_name = 'Roller'
 where not public.ra_is_preset_nickname(display_name);

-- Clans: give each non-conforming clan the first free 'Swift Comets <n>'.
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
            candidate := 'Swift Comets ' || n;
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
