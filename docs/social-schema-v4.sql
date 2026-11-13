-- ===========================================================================
-- Roll Along — social schema v4: PRESET NAMES ONLY (no free text).
--
-- GENERATED from the same word lists as `PresetNames` in
-- RollAlong/SocialClient.swift.  Change both together.
--
-- What this does
--   1. Rewrites any existing free-text value to a preset-format one:
--        players.display_name  -> 'Climber'
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
    select n = 'Climber'
        or n ~ '^(Swift|Brave|Lucky|Happy|Calm|Bold|Quick|Sunny|Misty|Rapid|Jolly|Noble|Zippy|Witty|Merry|Royal|Solar|Lunar|Amber|Azure|Coral|Ivory|Jade|Mint|Neon|Ruby|Teal|Gold|Iron|Agile|Clear|Eager|Grand|Keen|Kind|Loyal|Proud|Vivid|Wise|Epic)(Orb|Comet|Star|Moon|Fox|Otter|Panda|Koala|Tiger|Eagle|Robin|Finch|Whale|Lynx|Wolf|Bear|Hawk|Owl|Maple|Cedar|Pine|River|Cloud|Storm|Spark|Flame|Pixel|Rover|Racer|Kite|Wave|Peak|Ridge|Dune|Stone|Pearl|Lark|Heron|Bison|Lotus)([1-9][0-9]?)$'
$$;

create or replace function public.ra_is_preset_clan_name(n text)
returns boolean language sql immutable as $$
    select n ~ '^(Swift|Brave|Lucky|Happy|Calm|Bold|Quick|Sunny|Misty|Rapid|Jolly|Noble|Zippy|Witty|Merry|Royal|Solar|Lunar|Amber|Azure|Coral|Ivory|Jade|Mint|Neon|Ruby|Teal|Gold|Iron|Agile|Clear|Eager|Grand|Keen|Kind|Loyal|Proud|Vivid|Wise|Epic) (Orbs|Comets|Stars|Moons|Foxes|Otters|Pandas|Koalas|Tigers|Eagles|Robins|Finches|Whales|Lynxes|Wolves|Bears|Hawks|Owls|Maples|Cedars|Pines|Rivers|Clouds|Storms|Sparks|Flames|Pixels|Rovers|Racers|Kites|Waves|Peaks|Ridges|Dunes|Stones|Pearls|Larks|Herons|Bison|Lotuses) ([1-9][0-9]{0,2})$'
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
        'Casual climbers. No pressure.',
        'Chasing the top of the leaderboard.',
        'Minigame fans.',
        'Trophy hunters.',
        'Friends and family.',
        'New players welcome. We help each other climb.'
    )
$$;

-- ---------------------------------------------------------------------------
-- 1 · Rewrite existing rows that are not preset-format
-- ---------------------------------------------------------------------------
update public.players
   set display_name = 'Climber'
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
            exit when not exists (
                select 1 from public.clans
                 where lower(name) = lower(candidate)
                    or lower(tag)  = lower(public.ra_clan_tag_for(candidate)));
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
