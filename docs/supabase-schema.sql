-- =============================================================================
-- Roll Along — Analytics schema v1
-- =============================================================================
-- Idempotent: safe to re-run.  Paste the whole file into Supabase's SQL Editor
-- (Project → SQL Editor → New query → paste → Run).
--
-- Single-table design: every analytics event becomes one row in `events`.
-- Sessions, user behaviours, retention curves, conversion funnels, etc. are
-- all derived via SQL queries at read time.  Simpler than maintaining
-- pre-aggregated rollup tables, and Postgres can absolutely handle this
-- for the scale Roll Along will be at in V1.
--
-- Anonymous: the iOS client identifies a device with a UUID stored locally
-- (no Apple ID, no email, no PII).  Sessions are a separate UUID per app
-- launch.
--
-- Row-Level Security: anon role can ONLY insert.  Reading requires the
-- service_role key (admin-only) so a malicious client can't enumerate the
-- analytics or de-anonymise other users.
-- =============================================================================

-- Make sure uuid_generate_v4() is available (already enabled in default
-- Supabase projects but this line keeps the script standalone).
create extension if not exists "uuid-ossp";

-- -----------------------------------------------------------------------------
-- Table: public.events
-- -----------------------------------------------------------------------------
create table if not exists public.events (
    id              uuid        primary key default uuid_generate_v4(),
    created_at      timestamptz not null     default now(),

    -- Identification
    user_id         uuid        not null,        -- anonymous device-install UUID
    session_id      uuid        not null,        -- regenerated each app launch

    -- Event payload
    event_name      text        not null,
    properties      jsonb       not null default '{}'::jsonb,

    -- Context columns hoisted out of properties for fast filtering.
    -- `level` is nullable because plenty of events (app_launch, shop_opened,
    -- etc.) aren't tied to a specific level.
    level           int,
    app_version     text,
    ios_version     text,
    device_model    text,

    -- Sanity constraints
    constraint events_event_name_len check (char_length(event_name) <= 64),
    constraint events_app_version_len check (char_length(app_version) <= 32),
    constraint events_ios_version_len check (char_length(ios_version) <= 32),
    constraint events_device_model_len check (char_length(device_model) <= 64)
);

comment on table public.events is
    'Roll Along analytics events.  One row per event from the iOS client.  See AnalyticsClient.swift.';
comment on column public.events.user_id is
    'Anonymous device-install UUID.  Persisted in the app via UserDefaults.';
comment on column public.events.session_id is
    'New UUID for each app launch.  Lets us aggregate per-session metrics.';

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
-- Time-ordered scans are by far the most common pattern.
create index if not exists events_created_at_idx
    on public.events (created_at desc);

-- Per-user, per-session timeline queries (sessionisation, retention).
create index if not exists events_user_session_idx
    on public.events (user_id, session_id, created_at);

-- "How many app_launch events in the last 7 days?" — by event name.
create index if not exists events_name_idx
    on public.events (event_name, created_at);

-- Drop-off and difficulty queries — by level.
create index if not exists events_level_idx
    on public.events (level) where level is not null;

-- Arbitrary JSON property queries (e.g. {"theme": "aurora"}).  GIN index lets
-- queries like `properties @> '{"theme": "aurora"}'` use an index.
create index if not exists events_properties_gin_idx
    on public.events using gin (properties);

-- -----------------------------------------------------------------------------
-- Row-Level Security
-- -----------------------------------------------------------------------------
alter table public.events enable row level security;

-- Drop-and-recreate is idempotent.  Drop ignores missing.
drop policy if exists "anon can insert events" on public.events;

create policy "anon can insert events"
    on public.events
    for insert
    to anon
    with check (true);

-- No SELECT/UPDATE/DELETE policy for the anon role → anonymous clients
-- cannot read or modify any events.  Only the service_role key (which
-- bypasses RLS) can query for analysis.

-- -----------------------------------------------------------------------------
-- Permission grants
-- -----------------------------------------------------------------------------
-- The Data API role chain: anon (jwt with role=anon) → public schema → table.
-- We grant only INSERT, deliberately omitting SELECT/UPDATE/DELETE.
grant insert on public.events to anon;
-- authenticated would inherit from anon's grants; we explicitly keep it the
-- same so future "logged-in" features don't accidentally get more access.
grant insert on public.events to authenticated;

-- =============================================================================
-- Useful queries for later analysis (run via Supabase SQL Editor logged in
-- with service_role).
-- =============================================================================

-- Daily active users (DAU) for the last 14 days:
-- select date_trunc('day', created_at) as day, count(distinct user_id) as dau
-- from events
-- where created_at > now() - interval '14 days'
-- group by 1 order by 1 desc;

-- Level completion funnel for World 1:
-- select level, count(*) filter (where event_name = 'level_complete') as completes,
--        count(*) filter (where event_name = 'level_fail') as fails
-- from events
-- where level between 1 and 50
-- group by level order by level;

-- Coin economy — average coins earned per level clear:
-- select level, avg((properties->>'coin_reward')::int) as avg_reward
-- from events
-- where event_name = 'level_complete' and properties ? 'coin_reward'
-- group by level order by level;

-- Most popular equipped themes:
-- select properties->>'item' as theme, count(*) as equips
-- from events
-- where event_name = 'cosmetic_equipped' and properties->>'category' = 'background'
-- group by 1 order by 2 desc;
