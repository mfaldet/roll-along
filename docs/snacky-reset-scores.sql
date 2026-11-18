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
-- Recommendation: keep the scores (do NOT run this) unless the boards look
-- wrong after launch.  Few players have Comet Clash rows yet, and wiping wins
-- would take away progress people can see.
--
-- NOT RUN.  If you decide to reset, run it once in the Supabase SQL editor.
-- It cannot be undone.
-- ===========================================================================

begin;

delete from public.minigame_scores where game = 'snake';

update public.players
   set snake_best = 0,
       snake_wins = 0
 where snake_best <> 0 or snake_wins <> 0;

commit;
