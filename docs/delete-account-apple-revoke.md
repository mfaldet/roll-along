# Revoking the Sign in with Apple token on account deletion

Apple's account-deletion guidance says apps that use Sign in with Apple
"should use the Sign in with Apple REST API to revoke user tokens" when an
account is deleted. This note is the server half of that. The app half is
already in the code.

**Status: the complete function is now in the repo at
`supabase/functions/delete-account/index.ts` — written, not deployed, not
tested.** It replaces the deployed function: it verifies the caller, revokes
the Apple token (best effort) and deletes the auth user. The database cascades
and the `players_hand_over` trigger (social-schema-v5) do the rest, so the old
function's manual clan hand-off is no longer needed. Deploy it with
`supabase functions deploy delete-account` (or paste it into the dashboard's
function editor) and set the four Apple secrets below. The snippets further
down are kept for reference.

## How it works

1. In the app, **Delete Account** asks the player to confirm with Apple once
   more. Apple returns a one-time *authorization code* (valid for about five
   minutes, usable once).
2. The app sends the code to the `delete-account` function in the request
   body as `{"apple_authorization_code": "..."}`.
3. The function trades the code for an Apple refresh token
   (`https://appleid.apple.com/auth/token`) and immediately revokes it
   (`https://appleid.apple.com/auth/revoke`).
4. The function then deletes the account exactly as it does today.

Revocation is best-effort: if the code is missing, the secrets are not set, or
Apple returns an error, **the account is still deleted**. The function reports
`apple_revoked: true/false` in its logs.

If the function is not updated, nothing breaks: the deployed function ignores
the extra field and deletes the account as before.

## What the function needs

Four secrets (Supabase dashboard → Edge Functions → Secrets). None of them
belongs in the repository.

| Secret | What it is |
|---|---|
| `APPLE_TEAM_ID` | Your 10-character Apple developer Team ID |
| `APPLE_CLIENT_ID` | The app's bundle identifier: `com.macfaldet.RollAlong` |
| `APPLE_KEY_ID` | The 10-character ID of a key with "Sign in with Apple" enabled (Apple developer site → Certificates, Identifiers & Profiles → Keys) |
| `APPLE_PRIVATE_KEY` | The full text of that key's `.p8` file, including the `BEGIN`/`END` lines |

The `.p8` file can be downloaded only once, when the key is created. Keep it
somewhere safe and never commit it.

## Code to add to the function

Add the import and the helper at the top of the function file, and the call
just **before** the existing `auth.admin.deleteUser(...)` line.

```ts
import { SignJWT, importPKCS8 } from "npm:jose@5";

/**
 * Trade a one-time Sign in with Apple authorization code for a refresh token
 * and revoke it. Returns true when Apple confirmed the revocation.
 * Never throws: account deletion must go ahead whatever happens here.
 */
async function revokeAppleToken(authorizationCode: string | undefined): Promise<boolean> {
  try {
    const teamId = Deno.env.get("APPLE_TEAM_ID");
    const clientId = Deno.env.get("APPLE_CLIENT_ID");
    const keyId = Deno.env.get("APPLE_KEY_ID");
    const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
    if (!authorizationCode || !teamId || !clientId || !keyId || !privateKey) return false;

    // The "client secret" Apple expects: a short-lived ES256 JWT signed with the .p8 key.
    const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
    const now = Math.floor(Date.now() / 1000);
    const clientSecret = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyId })
      .setIssuer(teamId)
      .setSubject(clientId)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(key);

    const form = (fields: Record<string, string>) => ({
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(fields).toString(),
    });

    // 1. authorization code -> refresh token
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", form({
      client_id: clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }));
    if (!tokenRes.ok) {
      console.error("apple token exchange failed", tokenRes.status);
      return false;
    }
    const refreshToken = (await tokenRes.json())?.refresh_token;
    if (!refreshToken) return false;

    // 2. revoke it (Apple answers 200 with an empty body on success)
    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", form({
      client_id: clientId,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }));
    if (!revokeRes.ok) console.error("apple revoke failed", revokeRes.status);
    return revokeRes.ok;
  } catch (err) {
    console.error("apple revoke error", String(err));
    return false;
  }
}
```

Inside the request handler, before the user is deleted:

```ts
// Body is optional: older app builds send none.
let appleCode: string | undefined;
try {
  appleCode = (await req.json())?.apple_authorization_code;
} catch (_) { /* no body */ }
const appleRevoked = await revokeAppleToken(appleCode);
console.log("delete-account apple_revoked:", appleRevoked);
```

If the existing handler already reads the request body, reuse that value
instead of calling `req.json()` a second time (a body can be read only once).

## How to test

1. On a test Apple ID, sign in to Roll Along.
2. On the phone: Settings → your name → Sign-In & Security → Sign in with
   Apple. Roll Along is listed.
3. In the app: Settings → Delete Account → confirm, and confirm with Apple.
4. Check the function's Logs tab for `delete-account apple_revoked: true`.
5. Look at the Sign in with Apple list again. Roll Along should be gone.

## Sources

- Revoke endpoint and parameters: Apple, "Revoke tokens"
  (developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens),
  read 2026-11-13.
- "If you don't have the user's refresh token, access token, or authorization
  code, you must still fulfill the user's account deletion request": Apple
  TN3194.
- The token-exchange request (`/auth/token`) and the client-secret format are
  written from memory of Apple's "Generate and validate tokens" page and were
  not re-read for this note.
