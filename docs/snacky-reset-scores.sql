-- ===========================================================================
-- OPTIONAL — clear the old Comet Clash scores so the Snacky boards start empty.
--
-- Snacky replaced Comet Clash (2026-11-18) and kept its game id "snake", so
-- every stored Comet Clash result shows on the Snacky boards:
--   • public.minigame_scores rows with game = 'snake' (Easy / Normal / Hard);
--   • public.players.snake_wins / snake_best (the old all-difficulty columns).
-- Comet Clash "best" was power; Snacky "best" is orbs eaten, so old bests are
-- not comparable.  Wins mean the same thing (last one left), and the two
-- "snake_wins" trophies already earned stay earned either way (trophies live
-- on the phone, not here).
--
-- What this does: clears the old BESTS only.  Wins are kept, because a win
-- still means the same thing (last one left).  The app also clears the same
-- bests on each phone once (key ra_snackyBestsReset_v1), so phones do not
-- send the old values back.  Without this file, each player's old best on
-- the server is replaced the next time their phone syncs a Snacky result.
--
-- NOT RUN.  Optional; run it once in the Supabase SQL editor to clear the
-- boards straight away.  It cannot be undone.
-- ===========================================================================

begin;

update public.minigame_scores
   set best = 0
 where game = 'snake' and difficulty <> 'solo' and best <> 0;

update public.players
   set snake_best = 0
 where snake_best <> 0;

commit;
