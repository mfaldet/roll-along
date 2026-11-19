// delete-account — Supabase Edge Function (Deno).
//
// Called by the app from Settings → Delete Account with the player's sign-in
// token (Authorization: Bearer <access token>) and, when Apple provided one,
// a fresh one-time Sign in with Apple authorization code in the JSON body:
//   { "apple_authorization_code": "..." }
//
// 1. Verifies the caller from their access token (never trusts a user id
//    from the body).
// 2. Revokes the player's Sign in with Apple token (best effort — App Review
//    5.1.1(v); Apple TN3194: the account is deleted even if this fails).
// 3. Deletes the auth user.  Everything else follows in the database:
//    players and every row keyed to them cascade (ON DELETE CASCADE), feedback
//    rows with this player_id cascade, and the `players_hand_over` trigger
//    (social-schema-v5) passes any clan this player owns to its
//    longest-standing member.
//
// Secrets (Supabase dashboard → Edge Functions → Secrets), by name only:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  — provided by Supabase
//   APPLE_TEAM_ID, APPLE_CLIENT_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY
//     — needed only for step 2; without them the account is still deleted.
// See docs/delete-account-apple-revoke.md.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

/** Trade a one-time authorization code for a refresh token and revoke it.
 *  Never throws: deletion goes ahead whatever happens here. */
async function revokeAppleToken(code: string | undefined): Promise<boolean> {
  try {
    const teamId = Deno.env.get("APPLE_TEAM_ID");
    const clientId = Deno.env.get("APPLE_CLIENT_ID");
    const keyId = Deno.env.get("APPLE_KEY_ID");
    const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
    if (!code || !teamId || !clientId || !keyId || !privateKey) return false;

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

    const tokenRes = await fetch("https://appleid.apple.com/auth/token", form({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }));
    if (!tokenRes.ok) {
      console.error("apple token exchange failed", tokenRes.status);
      return false;
    }
    const refreshToken = (await tokenRes.json())?.refresh_token;
    if (!refreshToken) return false;

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

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const auth = req.headers.get("authorization") ?? "";
  const token = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
  if (!token) return json(401, { error: "missing_token" });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json(500, { error: "server_not_configured" });
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Who is calling?  (A 401 here lets the app renew its sign-in and retry.)
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  if (whoErr || !who?.user) return json(401, { error: "invalid_token" });
  const userId = who.user.id;

  // Body is optional: a build without the Apple code sends none.
  let appleCode: string | undefined;
  try {
    const body = await req.json();
    if (typeof body?.apple_authorization_code === "string") {
      appleCode = body.apple_authorization_code;
    }
  } catch (_) { /* no body */ }

  const appleRevoked = await revokeAppleToken(appleCode);
  console.log("delete-account apple_revoked:", appleRevoked);

  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) {
    console.error("delete-account deleteUser failed", delErr.message);
    return json(500, { error: "delete_failed" });
  }
  return json(200, { deleted: true, apple_revoked: appleRevoked });
});
