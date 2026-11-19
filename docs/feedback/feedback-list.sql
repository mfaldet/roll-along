-- Roll Along — new feedback, newest first. Read-only.
-- Run in Supabase → SQL Editor. Change the interval to look further back.
-- kind is bug, idea, question or compliment (database step 17).
-- To see one type only, uncomment the "and kind = ..." line.

select
    created_at at time zone 'America/New_York' as sent_eastern,
    kind,
    message,
    source,
    app_version,
    os_version,
    device_model,
    player_id,                     -- empty when the player was not signed in
    left(install_hash, 8)          as phone   -- same 8 characters = same phone
from public.feedback
where created_at > now() - interval '7 days'
--  and kind = 'bug'
order by created_at desc
limit 200;
