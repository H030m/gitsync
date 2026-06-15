# Research: Recommendation — Android GitHub token capture & refresh

- **Query**: Which approach to capture/refresh the GitHub OAuth token on Android, ranked.
- **Scope**: synthesis
- **Date**: 2026-06-16

## Ranking (feasible options)

### #1 (recommended) — Manual web OAuth (auth-code) via `flutter_web_auth_2` + `exchangeGitHubCode` Cloud Function

- **Why:** Best UX (one browser tap, standard "Authorize" screen), produces the **same `gho_` token** as the existing web flow ⇒ **zero backend consumer changes**. Secret stays in Functions. Fully within "Flutter + Firebase only".
- **Pieces:**
  - Flutter: add `flutter_web_auth_2`; build authorize URL (`client_id`, `scope=repo read:user`, `state`, `redirect_uri=gitsync://oauth/github`); `authenticate(callbackUrlScheme:'gitsync')`; parse `code`; call `exchangeGitHubCode({code})`.
  - Functions: new `exchangeGitHubCode` `onCall` (`secrets:[GITHUB_OAUTH_CLIENT_SECRET]`, `region:REGION`); POST `github.com/login/oauth/access_token`; write `users/{uid}.githubAccessToken`.
  - GitHub OAuth App: set callback URL `gitsync://oauth/github`; keep `client_secret` only in Functions secret.
  - Native: one custom-scheme intent-filter (`flutter_web_auth_2` provides it).
- **Effort:** medium. **Risk:** low (deep-link callback wiring is the only fiddly bit).
- **Token longevity:** non-expiring `gho_` (until revoked) — matches current behavior.

### #2 (simplest native footprint / good fallback) — GitHub Device Flow

- **Why:** No redirect, **no custom URL scheme/manifest change, no `client_secret` anywhere** (enable Device Flow on the OAuth App). Fully Flutter+Firebase.
- **Pieces:** Flutter POSTs `login/device/code` → show `user_code` + open `github.com/login/device` via `url_launcher` → poll `login/oauth/access_token` (grant_type device_code) → send final token to a thin `storeGitHubToken` callable (or write via a validated callable). No secret to protect.
- **Effort:** medium (polling/back-off logic). **Risk:** low technically; **UX cost:** user types a code.
- **Token longevity:** same `gho_` characteristics as #1.

### #3 (most robust long-term, more work) — GitHub App OR OAuth App with token-expiration enabled (refresh tokens)

- **Why:** Yields a **refresh token** (`ghr_`, ~6 mo) so a Cloud Function silently refreshes the 8h access token — **no user re-prompt** for months. Best answer to recurring "Bad credentials".
- **Pieces:** #1's flow PLUS: store `ghr_` refresh token, a `refreshGitHubToken` Cloud Function, and consumers refresh-on-401. GitHub App changes the permission model (fine-grained/installation) vs classic scopes.
- **Effort:** high. **Risk:** medium (refresh rotation + GitHub App permission mapping).

## Suggested plan

1. Ship **#1** now (matches existing token type, minimal blast radius).
2. Add **Q5 stale-token handling** regardless of capture method: backend maps GitHub `401` → distinct `HttpsError` code (e.g. `GITHUB_TOKEN_INVALID`); app catches it → "Reconnect GitHub" → re-runs #1. (Add `status===401` branch alongside the existing `status===404` branch in `addRepo.ts verifyRepoAccess` catch, and in the shared `githubClient`.)
3. Consider **#3** only if non-expiring tokens prove too brittle in the demo.

## Open verifications before implementing

- Re-confirm Android `signInWithProvider` still returns no GitHub token at the pinned `firebase_auth ^4.4.0` (FlutterFire issue tracker).
- Pin `flutter_web_auth_2` version + its Android manifest requirements from pub.dev.
- Confirm exact GitHub token-expiry / device-flow-no-secret details in current GitHub OAuth docs.
- Decide: reuse existing GitHub OAuth App (the one behind the Firebase web token) or create a dedicated one for the mobile callback.
