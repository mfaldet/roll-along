-- =============================================================================
-- Roll Along — Social schema v2  (clans-as-a-lives-community)
-- =============================================================================
-- Idempotent + additive: safe to re-run, and safe to run on the live v1 DB.
-- Paste the whole file into Supabase's SQL Editor (Project → SQL Editor → New
-- query → paste → Run).  MUST be applied before shipping the client build that
-- reads/writes `needs_lives_at` or `clan_events`.
--
-- Adds two things the Clans-as-a-lives-community experience needs:
--   1. players.needs_lives_at — a timestamp a player sets when they "Ask for a
--      life".  Clan-mates (who already read profiles) see it and send a life;
--      it clears when they claim a gift or cancel.  No new policy needed — the
--      v1 "players readable by authenticated" + "players update own" already
--      cover reading any column and writing your own row.
--   2. public.clan_events — a lightweight activity log (joined / left / sent a
--      life / asked for a life / said thanks) powering the clan activity feed.
--      The "Thanks 🙏" reaction is just an event of kind 'thanked'.
-- =============================================================================

-- 1) "Ask for a life" flag --------------------------------------------------
alter table public.players
    add column if not exists needs_lives_at timestamptz;   -- null = not asking

-- 2) Clan activity feed ------------------------------------------------------
create table if not exists public.clan_events (
    id          uuid        primary key default uuid_generate_v4(),
    created_at  timestamptz not null default now(),
    clan_id     uuid        not null references public.clans (id)   on delete cascade,
    actor_id    uuid        not null references public.players (id) on delete cascade,
    -- the other player, when the event is about a pair (sent_life / thanked)
    target_id   uuid        references public.players (id) on delete set null,
    kind        text        not null,
    constraint clan_events_kind_valid
        check (kind in ('created','joined','left','sent_life','requested_life','thanked'))
);

-- Newest-first feed per clan.
create index if not exists clan_events_clan_idx
    on public.clan_events (clan_id, created_at desc);

alter table public.clan_events enable row level security;

-- Read the feed only for a clan you belong to.
drop policy if exists "clan_events readable by clan members" on public.clan_events;
create policy "clan_events readable by clan members"
    on public.clan_events for select to authenticated
    using (exists (
        select 1 from public.clan_members m
        where m.clan_id = clan_events.clan_id and m.player_id = auth.uid()
    ));

-- Post events only as yourself, and only into a clan you belong to.
drop policy if exists "clan_events insert as member" on public.clan_events;
create policy "clan_events insert as member"
    on public.clan_events for insert to authenticated
    with check (
        actor_id = auth.uid()
        and exists (
            select 1 from public.clan_members m
            where m.clan_id = clan_events.clan_id and m.player_id = auth.uid()
        )
    );

grant select, insert on public.clan_events to authenticated;

-- =============================================================================
-- Notes
-- =============================================================================
-- • Clan stats (members, combined climb levels, lives shared recently) are
--   DERIVED on the client from clan_members + clan_events — no new table.
-- • Clan invite links (rollalong://clan/<id>) are pure client — they resolve to
--   the clan's detail screen, which uses the existing join flow.
-- • Open-join stays the v1 model (clan_members "join self" policy); the client
--   frames it as "Join".  A gated ask-to-join can later move behind an RPC.
