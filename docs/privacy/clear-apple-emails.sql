-- Clears email addresses stored for accounts made with Sign in with Apple.
--
-- WHY: the game asks Apple for no email, and no table of ours holds one. But
-- Supabase's own account tables keep an email when Apple's sign-in token
-- carries one. The check on 2026-11-23 found 6 accounts, 1 with an Apple
-- relay address.
--
-- WHAT IT TOUCHES: only Supabase's account tables, and only accounts whose
-- every sign-in method is Apple.
--   auth.users       email, and the email keys inside raw_user_meta_data
--   auth.identities  the email keys inside identity_data (the table's own
--                    email column is worked out from identity_data, so it
--                    empties by itself)
-- Nothing in the public tables changes. Sign-in is not affected: Supabase
-- matches an Apple sign-in on Apple's account identifier, not on the email.
--
-- HOW TO RUN: paste the whole file into the Supabase SQL editor and run it
-- once. It is safe to run again. It prints a count before and after.
--
-- NOTE: this was written against Supabase's published table layout and tested
-- on a local copy of that layout, not on the live project. If any statement
-- errors, nothing is changed (it all runs in one transaction); send the error.
--
-- It does not stop a new email arriving at a later sign-in. That needs a
-- guard, which is a separate decision.

begin;

-- Before: how many Apple-only accounts hold an email anywhere.
select 'before' as moment, count(*) as apple_accounts_with_an_email
from auth.users u
where exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider <> 'apple')
  and (   coalesce(u.email, '') <> ''
       or u.raw_user_meta_data ? 'email'
       or exists (select 1 from auth.identities i
                  where i.user_id = u.id and i.identity_data ? 'email'));

-- 1. The identities: drop the email keys Apple's token supplied.
update auth.identities i
set identity_data = i.identity_data - 'email' - 'email_verified' - 'is_private_email',
    updated_at    = now()
where i.provider = 'apple'
  and i.identity_data ?| array['email', 'email_verified', 'is_private_email']
  and not exists (select 1 from auth.identities o
                  where o.user_id = i.user_id and o.provider <> 'apple');

-- 2. The accounts: clear the email and the copies kept in the metadata.
update auth.users u
set email              = null,
    raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
                           - 'email' - 'email_verified' - 'is_private_email',
    updated_at         = now()
where exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider <> 'apple')
  and (   coalesce(u.email, '') <> ''
       or u.raw_user_meta_data ?| array['email', 'email_verified', 'is_private_email']);

-- After: this must read 0.
select 'after' as moment, count(*) as apple_accounts_with_an_email
from auth.users u
where exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider <> 'apple')
  and (   coalesce(u.email, '') <> ''
       or u.raw_user_meta_data ? 'email'
       or exists (select 1 from auth.identities i
                  where i.user_id = u.id and i.identity_data ? 'email'));

commit;

-- Then run docs/privacy/check-stored-emails.sql again. accounts_with_an_email
-- should be 0.
