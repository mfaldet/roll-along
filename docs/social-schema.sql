-- =============================================================================
-- Roll Along — Social schema v1
-- =============================================================================
-- Idempotent: safe to re-run.  Paste the whole file into Supabase's SQL Editor
-- (Project → SQL Editor → New query → paste → Run).
--
-- This is net-new and lives alongside the analytics `events` table in the same
-- Supabase project.  Where analytics is anonymous + insert-only, social is
-- IDENTIFIED + read/write: it backs leaderboards, clans, friends, and the
-- send-a-life economy, all of which need stable, recoverable accounts.
--
-- IDENTITY: Sign in with Apple (via Supabase Auth).
--   When a player signs in with Apple, Supabase Auth creates a row in
--   `auth.users` and issues a JWT whose `sub` is that user's UUID.  Every
--   social row is keyed on that UUID, exposed in policies as `auth.uid()`.
--   We deliberately store NO Apple email / name / PII here — only a
--   player-chosen display name and game stats.  (Apple's private-relay email,
--   if needed for receipts, stays in auth.users, never copied into public.)
--
-- ROW-LEVEL SECURITY model:
--   • A player may write only their OWN profile (id = auth.uid()).
--   • Public profile + clan rosters are readable by any signed-in user so
--     leaderboards and clan browsing work.
--   • The `anon` role (used by analytics) gets NOTHING here — social requires
--     a logged-in `authenticated` JWT.
--
-- KNOWN V1 LIMITATION (documented, not yet solved):
--   climb_level / stars are written by the trusted client, so a determined
--   cheater could inflate their own row.  Acceptable for the social MVP (same
--   trust model as analytics).  Hardening path: move score writes behind a
--   SECURITY DEFINER RPC that validates deltas server-side.  Noted at each
--   mutable stat column.
-- =============================================================================

create extension if not exists "uuid-ossp";

-- -----------------------------------------------------------------------------
-- updated_at helper — bump a row's updated_at on every UPDATE.
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

-- =============================================================================
-- Table: public.players  — one profile per Sign-in-with-Apple account.
-- =============================================================================
create table if not exists public.players (
    id                   uuid        primary key
                         references auth.users (id) on delete cascade,  -- = auth.uid()
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    last_seen_at         timestamptz not null default now(),

    -- Public identity (no PII).  display_name is what shows on leaderboards,
    -- clan rosters, and friend lists — next to the headline climb level.
    display_name         text        not null,

    -- THE headline number shown next to the player's name everywhere.
    -- Single source of truth for the main-climb progression; the client syncs
    -- this when it advances a level.  (Client-trusted in V1 — see header.)
    climb_level          int         not null default 1,

    -- Secondary stats, also client-synced.
    highest_unlocked     int         not null default 1,
    total_stars          int         not null default 0,
    -- Lifetime coins picked up across levels (the "coins collected" stat the
    -- client shows in Replay Levels) — powers the leaderboard's Coins sort.
    coins_collected      int         not null default 0,
    -- Minigame leaderboards (client-synced):
    --   pinball_best  — best single Pinball score
    --   zen_seconds   — total seconds spent in Zen Garden
    --   goldrush_best — most coins caught in one Gold Rush match
    pinball_best         int         not null default 0,
    zen_seconds          int         not null default 0,
    goldrush_best        int         not null default 0,
    -- Competitive-mode leaderboards (client-synced).  Each mode persists a
    -- personal best (mode-specific units) plus a lifetime win tally; the boards
    -- rank by wins, then best as the tiebreaker.
    --   snake_*     — Comet Clash  (best = power; wins = rounds won)
    --   sumo_*      — Sumo Survival(best = points; wins = 1st-place finishes)
    --   paintball_* — Paint Ball   (best = coverage %; wins = rounds won)
    --   marblecup_* — Marble Cup   (best = goals; wins = matches won)
    --   koth_*      — King of the Hill (best = hold seconds; wins = rounds won)
    --   goldrush_*  — Coin Pit     (best already above; goldrush_wins added here)
    snake_best           int         not null default 0,
    sumo_best            int         not null default 0,
    paintball_best       int         not null default 0,
    marblecup_best       int         not null default 0,
    koth_best            int         not null default 0,
    snake_wins           int         not null default 0,
    sumo_wins            int         not null default 0,
    paintball_wins       int         not null default 0,
    marblecup_wins       int         not null default 0,
    koth_wins            int         not null default 0,
    goldrush_wins        int         not null default 0,

    -- Lives economy mirror (the canonical timer still lives on-device; this is
    -- the shareable count clans/friends can top up via life_gifts).
    lives                int         not null default 5,

    constraint players_display_name_len  check (char_length(display_name) between 1 and 24),
    constraint players_climb_level_pos    check (climb_level      >= 1),
    constraint players_highest_pos        check (highest_unlocked >= 1),
    constraint players_stars_nonneg       check (total_stars      >= 0),
    constraint players_coins_nonneg       check (coins_collected  >= 0),
    constraint players_pinball_nonneg     check (pinball_best     >= 0),
    constraint players_zen_nonneg         check (zen_seconds      >= 0),
    constraint players_goldrush_nonneg    check (goldrush_best    >= 0),
    constraint players_snake_best_nonneg     check (snake_best     >= 0),
    constraint players_sumo_best_nonneg      check (sumo_best      >= 0),
    constraint players_paintball_best_nonneg check (paintball_best >= 0),
    constraint players_marblecup_best_nonneg check (marblecup_best >= 0),
    constraint players_koth_best_nonneg      check (koth_best      >= 0),
    constraint players_snake_wins_nonneg     check (snake_wins     >= 0),
    constraint players_sumo_wins_nonneg      check (sumo_wins      >= 0),
    constraint players_paintball_wins_nonneg check (paintball_wins >= 0),
    constraint players_marblecup_wins_nonneg check (marblecup_wins >= 0),
    constraint players_koth_wins_nonneg      check (koth_wins      >= 0),
    constraint players_goldrush_wins_nonneg  check (goldrush_wins  >= 0),
    constraint players_lives_nonneg       check (lives            >= 0)
);

comment on table public.players is
    'Roll Along social profile, one per Sign-in-with-Apple account (id = auth.uid()). No PII.';
comment on column public.players.climb_level is
    'Headline main-climb level shown next to the player name. Single source of truth, client-synced.';

drop trigger if exists players_set_updated_at on public.players;
create trigger players_set_updated_at
    before update on public.players
    for each row execute function public.set_updated_at();

-- Leaderboard scans: highest climbers first.
create index if not exists players_climb_level_idx
    on public.players (climb_level desc);

-- Leaderboard "Coins" sort.
create index if not exists players_coins_idx
    on public.players (coins_collected desc);

-- Minigame leaderboard sorts.
create index if not exists players_pinball_idx  on public.players (pinball_best  desc);
create index if not exists players_zen_idx      on public.players (zen_seconds   desc);
create index if not exists players_goldrush_idx on public.players (goldrush_best desc);

-- Competitive-mode boards rank by wins, then best as the tiebreaker.
create index if not exists players_snake_idx        on public.players (snake_wins     desc, snake_best     desc);
create index if not exists players_sumo_idx         on public.players (sumo_wins      desc, sumo_best      desc);
create index if not exists players_paintball_idx    on public.players (paintball_wins desc, paintball_best desc);
create index if not exists players_marblecup_idx    on public.players (marblecup_wins desc, marblecup_best desc);
create index if not exists players_koth_idx         on public.players (koth_wins      desc, koth_best      desc);
create index if not exists players_goldrush_wins_idx on public.players (goldrush_wins  desc, goldrush_best  desc);

-- ── Migration for existing deployments ───────────────────────────────────
-- Run once on databases created before these columns existed. Safe + additive
-- (each defaults to 0). MUST be applied before shipping the client build that
-- writes/reads them.
alter table public.players
    add column if not exists coins_collected int not null default 0,
    add column if not exists pinball_best     int not null default 0,
    add column if not exists zen_seconds      int not null default 0,
    add column if not exists goldrush_best    int not null default 0,
    -- Competitive-mode best + win columns (migration: add_competitive_leaderboard_stats).
    add column if not exists snake_best       int not null default 0,
    add column if not exists sumo_best        int not null default 0,
    add column if not exists paintball_best   int not null default 0,
    add column if not exists marblecup_best   int not null default 0,
    add column if not exists koth_best        int not null default 0,
    add column if not exists snake_wins       int not null default 0,
    add column if not exists sumo_wins        int not null default 0,
    add column if not exists paintball_wins   int not null default 0,
    add column if not exists marblecup_wins   int not null default 0,
    add column if not exists koth_wins        int not null default 0,
    add column if not exists goldrush_wins    int not null default 0;

-- =============================================================================
-- Table: public.clans  — collaborative groups.
-- =============================================================================
create table if not exists public.clans (
    id           uuid        primary key default uuid_generate_v4(),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),

    name         text        not null,
    tag          text        not null,                 -- short [TAG] shown by names
    description  text        not null default '',
    owner_id     uuid        not null references public.players (id) on delete cascade,

    constraint clans_name_len check (char_length(name) between 2 and 32),
    constraint clans_tag_len  check (char_length(tag)  between 2 and 5),
    constraint clans_desc_len check (char_length(description) <= 200)
);

-- Case-insensitive uniqueness for name + tag so "Storm" and "storm" can't both exist.
create unique index if not exists clans_name_unique_idx on public.clans (lower(name));
create unique index if not exists clans_tag_unique_idx  on public.clans (lower(tag));

drop trigger if exists clans_set_updated_at on public.clans;
create trigger clans_set_updated_at
    before update on public.clans
    for each row execute function public.set_updated_at();

-- =============================================================================
-- Table: public.clan_members  — membership + role (one clan per player).
-- =============================================================================
create table if not exists public.clan_members (
    clan_id     uuid        not null references public.clans (id)   on delete cascade,
    player_id   uuid        not null references public.players (id) on delete cascade,
    role        text        not null default 'member',   -- 'owner' | 'officer' | 'member'
    joined_at   timestamptz not null default now(),

    primary key (clan_id, player_id),
    constraint clan_members_role_valid check (role in ('owner', 'officer', 'member'))
);

-- A player belongs to at most ONE clan at a time.
create unique index if not exists clan_members_one_per_player_idx
    on public.clan_members (player_id);

-- Roster lookups by clan.
create index if not exists clan_members_clan_idx on public.clan_members (clan_id);

-- =============================================================================
-- Table: public.friendships  — friend graph (independent of clans).
-- =============================================================================
create table if not exists public.friendships (
    id            uuid        primary key default uuid_generate_v4(),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),

    requester_id  uuid        not null references public.players (id) on delete cascade,
    addressee_id  uuid        not null references public.players (id) on delete cascade,
    status        text        not null default 'pending',  -- 'pending' | 'accepted' | 'blocked'

    constraint friendships_status_valid check (status in ('pending', 'accepted', 'blocked')),
    constraint friendships_no_self      check (requester_id <> addressee_id),
    -- One edge per ordered pair (request direction matters for pending/blocked).
    constraint friendships_unique_pair  unique (requester_id, addressee_id)
);

drop trigger if exists friendships_set_updated_at on public.friendships;
create trigger friendships_set_updated_at
    before update on public.friendships
    for each row execute function public.set_updated_at();

create index if not exists friendships_addressee_idx on public.friendships (addressee_id, status);
create index if not exists friendships_requester_idx on public.friendships (requester_id, status);

-- =============================================================================
-- Table: public.life_gifts  — "send a life" economy.
-- =============================================================================
-- A sender gives 1–5 lives to a recipient; the recipient claims them later
-- (claimed_at set, lives credited on-device).  Small amounts + sender<>recipient
-- enforced at the RLS layer so the client can't forge large self-grants.
create table if not exists public.life_gifts (
    id            uuid        primary key default uuid_generate_v4(),
    created_at    timestamptz not null default now(),

    sender_id     uuid        not null references public.players (id) on delete cascade,
    recipient_id  uuid        not null references public.players (id) on delete cascade,
    amount        int         not null default 1,
    claimed_at    timestamptz,                          -- null = unclaimed

    constraint life_gifts_amount_range check (amount between 1 and 5),
    constraint life_gifts_no_self      check (sender_id <> recipient_id)
);

-- Recipient's "what can I claim?" query — unclaimed first.
create index if not exists life_gifts_recipient_idx
    on public.life_gifts (recipient_id, claimed_at);

-- =============================================================================
-- Row-Level Security
-- =============================================================================
-- Everything below targets the `authenticated` role only.  The `anon` role
-- (analytics) is never granted access to social tables.

alter table public.players       enable row level security;
alter table public.clans         enable row level security;
alter table public.clan_members  enable row level security;
alter table public.friendships   enable row level security;
alter table public.life_gifts    enable row level security;

-- ---- players ----------------------------------------------------------------
drop policy if exists "players readable by authenticated" on public.players;
create policy "players readable by authenticated"
    on public.players for select to authenticated using (true);

drop policy if exists "players insert own" on public.players;
create policy "players insert own"
    on public.players for insert to authenticated with check (id = auth.uid());

drop policy if exists "players update own" on public.players;
create policy "players update own"
    on public.players for update to authenticated
    using (id = auth.uid()) with check (id = auth.uid());

-- ---- clans ------------------------------------------------------------------
drop policy if exists "clans readable by authenticated" on public.clans;
create policy "clans readable by authenticated"
    on public.clans for select to authenticated using (true);

drop policy if exists "clans insert as owner" on public.clans;
create policy "clans insert as owner"
    on public.clans for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists "clans update by owner" on public.clans;
create policy "clans update by owner"
    on public.clans for update to authenticated
    using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "clans delete by owner" on public.clans;
create policy "clans delete by owner"
    on public.clans for delete to authenticated using (owner_id = auth.uid());

-- ---- clan_members -----------------------------------------------------------
drop policy if exists "clan_members readable by authenticated" on public.clan_members;
create policy "clan_members readable by authenticated"
    on public.clan_members for select to authenticated using (true);

-- You add only yourself (open-join V1; gated invites can move behind an RPC).
drop policy if exists "clan_members join self" on public.clan_members;
create policy "clan_members join self"
    on public.clan_members for insert to authenticated with check (player_id = auth.uid());

-- You can leave yourself; a clan owner can remove any member.
drop policy if exists "clan_members leave or owner removes" on public.clan_members;
create policy "clan_members leave or owner removes"
    on public.clan_members for delete to authenticated
    using (
        player_id = auth.uid()
        or exists (
            select 1 from public.clans c
            where c.id = clan_members.clan_id and c.owner_id = auth.uid()
        )
    );

-- ---- friendships ------------------------------------------------------------
drop policy if exists "friendships visible to participants" on public.friendships;
create policy "friendships visible to participants"
    on public.friendships for select to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "friendships request as self" on public.friendships;
create policy "friendships request as self"
    on public.friendships for insert to authenticated
    with check (requester_id = auth.uid());

-- Either side can update (accept / block / unfriend-state).
drop policy if exists "friendships update by participant" on public.friendships;
create policy "friendships update by participant"
    on public.friendships for update to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid())
    with check (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "friendships delete by participant" on public.friendships;
create policy "friendships delete by participant"
    on public.friendships for delete to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid());

-- ---- life_gifts -------------------------------------------------------------
drop policy if exists "life_gifts visible to participants" on public.life_gifts;
create policy "life_gifts visible to participants"
    on public.life_gifts for select to authenticated
    using (recipient_id = auth.uid() or sender_id = auth.uid());

-- Send as yourself; amount + self-send caps are also enforced by table CHECKs.
drop policy if exists "life_gifts send as self" on public.life_gifts;
create policy "life_gifts send as self"
    on public.life_gifts for insert to authenticated
    with check (sender_id = auth.uid() and sender_id <> recipient_id);

-- Only the recipient may claim (flip claimed_at).
drop policy if exists "life_gifts claim by recipient" on public.life_gifts;
create policy "life_gifts claim by recipient"
    on public.life_gifts for update to authenticated
    using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

-- =============================================================================
-- Permission grants — authenticated only; RLS narrows to the right rows.
-- =============================================================================
grant select, insert, update          on public.players      to authenticated;
grant select, insert, update, delete   on public.clans        to authenticated;
grant select, insert, delete           on public.clan_members to authenticated;
grant select, insert, update, delete   on public.friendships  to authenticated;
grant select, insert, update           on public.life_gifts   to authenticated;

-- The delete-account Edge Function runs as `service_role` and must read +
-- reassign clan ownership during the account-deletion hand-off. The grants
-- above target `authenticated` only, so without these the function 500s with
-- "permission denied for table clans". (User deletion itself cascades at the
-- constraint level, so no INSERT/DELETE grant is needed here.)
grant select, update on public.clans        to service_role;
grant select, update on public.clan_members to service_role;

-- =============================================================================
-- Useful queries (run with service_role, or adapt for the client).
-- =============================================================================

-- Global leaderboard — top 100 climbers:
-- select display_name, climb_level, total_stars
-- from players order by climb_level desc, total_stars desc limit 100;

-- A player's clan roster, ranked by climb level:
-- select p.display_name, p.climb_level, m.role
-- from clan_members m join players p on p.id = m.player_id
-- where m.clan_id = '<clan-uuid>'
-- order by p.climb_level desc;

-- A player's accepted friends (either direction):
-- select p.display_name, p.climb_level
-- from friendships f
-- join players p
--   on p.id = case when f.requester_id = '<me>' then f.addressee_id else f.requester_id end
-- where f.status = 'accepted' and ('<me>' in (f.requester_id, f.addressee_id));

-- Unclaimed life gifts waiting for a player:
-- select id, sender_id, amount, created_at
-- from life_gifts
-- where recipient_id = '<me>' and claimed_at is null
-- order by created_at;
