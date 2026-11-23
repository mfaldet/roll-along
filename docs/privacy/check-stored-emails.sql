-- Read-only. Changes nothing.
--
-- Does Sign in with Apple leave an email address on accounts?
--
-- The game asks Apple for no email (requestedScopes is empty in
-- RollAlong/AppleAuthManager.swift), and no table of ours has an email column.
-- The one place an email could be is Supabase's own accounts table,
-- auth.users, which stores an email if Apple's sign-in token carries one.
--
-- Run this in the Supabase SQL editor and read the three numbers.

select
  count(*)                                             as accounts,
  count(*) filter (where email is not null and email <> '')              as accounts_with_an_email,
  count(*) filter (where email like '%@privaterelay.appleid.com')        as of_those_apple_relay_addresses
from auth.users;

-- If accounts_with_an_email is 0: no email is requested or stored. Remove
-- "Email Address" from the App Privacy answers and from
-- RollAlong/PrivacyInfo.xcprivacy, and finish the sentence marked in the
-- privacy policy draft.
--
-- If it is above 0: emails are being stored for existing accounts even though
-- the game does not ask for them. Tell Claude the three numbers. Clearing them
-- is a database change, so it will come as its own SQL file for you to apply.
