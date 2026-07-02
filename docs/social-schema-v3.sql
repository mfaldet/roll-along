-- =============================================================================
-- Roll Along — Social schema v3  (clan chat + clan settings)
-- =============================================================================
-- Idempotent + additive: safe to re-run, and safe to run on the live v2 DB.
-- Paste the whole file into Supabase's SQL Editor (Project → SQL Editor → New
-- query → paste → Run).  MUST be applied before shipping the client build with
-- the clan chat / clan settings sheet — until then, posting the new event
-- kinds fails the check constraint (the client surfaces a retry banner; every
-- pre-v3 feature keeps working).
--
-- What changes: clan_events.kind accepts three new families of event —
--   1. requested_promotion — a member/officer asks the leadership for a
--      promotion from the clan settings sheet; it lands in the clan chat.
--      (Actually GRANTING a promotion is future work: clan_members has no
--      UPDATE policy yet, so roles are immutable server-side.)
--   2. renamed — the owner renamed the clan (clans already had an owner-scoped
--      UPDATE policy, so the rename itself needs no schema change); shows as a
--      system line in the chat.
--   3. chat_* — premade quick-chat messages ("Hi team! 👋", "Let's roll! 🚀",
--      …).  Only the KIND travels over the wire; the client maps each kind to
--      a fixed string, so no free text is ever stored and there is nothing to
--      moderate.  New premade messages are client-only additions — any
--      `chat_*` kind (6–32 chars) passes the constraint, no migration needed.
--
-- No new tables, columns, policies, or grants — the v2 clan_events RLS
-- (members read their clan's feed, members post only as themselves) already
-- covers everything the chat does.
-- =============================================================================

alter table public.clan_events drop constraint if exists clan_events_kind_valid;
alter table public.clan_events add constraint clan_events_kind_valid
    check (
        kind in ('created','joined','left','sent_life','requested_life','thanked',
                 'requested_promotion','renamed')
        or (kind like 'chat\_%' and char_length(kind) between 6 and 32)
    );

-- =============================================================================
-- Notes
-- =============================================================================
-- • Backwards compatible: the constraint is strictly wider, so v2 clients keep
--   posting their kinds unchanged, and old rows all satisfy the new check.
-- • `chat\_%` escapes the underscore (LIKE wildcard) so "chatter" can't slip
--   through; the length cap keeps junk kinds bounded.
-- • Rollback: re-run the v2 constraint block (docs/social-schema-v2.sql) —
--   but only after deleting rows with v3 kinds, or the check won't validate.
