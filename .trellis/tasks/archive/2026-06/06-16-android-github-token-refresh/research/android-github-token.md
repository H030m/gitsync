# Research: Obtaining & refreshing the GitHub OAuth access token on Android

- **Query**: How to get & refresh a GitHub OAuth access token on Android in this Flutter + Firebase app (signInWithProvider returns null accessToken on Android).
- **Scope**: mixed (internal code + external library/API behavior)
- **Date**: 2026-06-16

> Companion files in this folder:
> - `android-github-token-internal-map.md` — exact code locations / contracts touched.
> - `android-github-token-recommendation.md` — ranked recommendation + concrete piece list.

---

## Confirmed starting point (given, not re-investigated)

- Live sign-in: `lib/services/authentication.dart` `_LiveAuthenticationService.logInWithGitHub()`.
  - Web: `FirebaseAuth.signInWithPopup(GithubAuthProvider)` → `UserCredential.credential` **is** an `OAuthCredential` → `.accessToken` present.
  - Android: `FirebaseAuth.signInWithProvider(GithubAuthProvider)` → `UserCredential.credential` is a **base `AuthCredential`** (the code already guards with `credential is OAuthCredential ? ... : null`), so `accessToken` is **null** on Android.
- Token persisted to `users/{uid}.githubAccessToken` (`lib/repositories/user_repo.dart`).
- Backend consumers read that field: `getCommitGraph`, `explainCommit`, `addRepo`/`removeRepo`, `onTaskCreated` (createIssue), `importCollaborators`, etc. (see internal map file). All throw `HttpsError('failed-precondition', 'No GitHub access token found...')` when missing.
- Required scopes: `repo` + `read:user`.
- Hard constraint (project memory `final-demo-flutter-firebase-only.md`): **Flutter + Firebase only, no self-built external server** (Python/Go/Node host). **Firebase Cloud Functions ARE allowed** (they are Firebase). The project already runs a large TS Cloud Functions codebase (`functions/`).

---

## Q1 — Can `firebase_auth` ever surface the GitHub OAuth access token on Android?

**Short answer: No, not reliably — this is a Firebase platform behavior, not just a Flutter-plugin bug, and it cannot be fixed app-side.**

### What happens on each platform

| Path | Method | `UserCredential.credential` type | `.accessToken` |
|---|---|---|---|
| Web | `signInWithPopup` / `signInWithRedirect` + `getRedirectResult` | `OAuthCredential` (GithubAuthProvider.credentialFromResult) | **present** |
| Android / iOS | `signInWithProvider` (and `getRedirectResult` on mobile) | base `AuthCredential` | **null** |

### Why (root cause)

- On **web**, the Firebase JS SDK performs the OAuth dance itself and exposes the provider's raw OAuth access token via `GithubAuthProvider.credentialFromResult(userCredential)` → `OAuthCredential.accessToken`.
- On **Android**, `signInWithProvider` is backed by the native Firebase Android SDK's `startActivityForSignInWithProvider` / `OAuthProvider` generic-IDP flow. The native `AuthResult.getCredential()` returns an `OAuthCredential` **only for a known subset** of providers and SDK versions; for the GitHub generic OAuth IDP the federated credential's provider access token is frequently **not** populated back into the `AuthCredential` handed to the app. The Flutter `firebase_auth` plugin can only forward whatever the native layer gives it — so when the native credential lacks the token, the Dart side sees a base `AuthCredential` with no `accessToken`.
- This is a **long-standing, documented gap** in the Firebase mobile generic-OAuth/IDP flow (tracked across `firebase/flutterfire` and `firebase/firebase-android-sdk` issues about `OAuthCredential.accessToken` being null on Android for GitHub/Microsoft/generic providers). It is **not** something a scope change, plugin upgrade, or cast fix resolves — the data simply isn't returned by the platform.

### Practical implication

- You **cannot** get the GitHub OAuth access token out of the Firebase-managed sign-in on Android. The Firebase ID token / Firebase user is fine for *authentication*, but the *GitHub API token* must be obtained through a **separate, app-controlled OAuth flow**.
- ⚠️ Verify-before-build note: confirm against the currently pinned `firebase_auth: ^4.4.0` changelog and the live FlutterFire issue tracker that no recent version added Android token passthrough. As of knowledge cutoff (Jan 2026) it had not, but this is the one claim worth a 5-minute re-check before committing to a workaround.

**Conclusion: Q1 = not feasible. Proceed to a secondary, manual GitHub OAuth flow (Q2 / Q3).**

---

## Q2 — Manual GitHub OAuth (authorization-code) flow via `flutter_web_auth_2` + Cloud Function exchange

This is the standard "Firebase for identity, separate OAuth for the provider API token" pattern. The user is already Firebase-authed; this is a **secondary token grab** that runs after (or on demand from) the normal sign-in.

### How it works (end to end)

1. **App** generates a random `state` (CSRF) and opens the GitHub authorize URL in a system browser tab via `flutter_web_auth_2`:
   ```
   https://github.com/login/oauth/authorize
     ?client_id=<OAUTH_APP_CLIENT_ID>
     &redirect_uri=<callback>
     &scope=repo%20read:user
     &state=<random>
   ```
2. User approves on GitHub. GitHub redirects to the **callback URL**, which carries `?code=...&state=...`.
3. `flutter_web_auth_2.authenticate(url: authorizeUrl, callbackUrlScheme: 'gitsync')` captures the redirect, returns the full callback URL to Dart; app parses `code` + verifies `state`.
4. **App calls a Cloud Function** (callable `onCall`), e.g. `exchangeGitHubCode({ code })`. The Firebase ID token authenticates the call, so the function knows the `uid`.
5. **Cloud Function** does the secret-bearing exchange (server side only):
   ```
   POST https://github.com/login/oauth/access_token
   Accept: application/json
   body: client_id, client_secret, code, redirect_uri
   ```
   GitHub returns `access_token` (`gho_...`). Function writes it to `apps/gitsync/users/{uid}.githubAccessToken` (same field everything already reads) and returns success.
6. Backend consumers (`getCommitGraph`, etc.) keep working unchanged — they just read the field that is now populated on Android too.

### Redirect/callback URL options (pick one)

- **Custom URL scheme (simplest, recommended for a demo app):**
  - GitHub OAuth App "Authorization callback URL" = e.g. `gitsync://oauth/github` (GitHub allows custom schemes for the callback).
  - `flutter_web_auth_2` `callbackUrlScheme: 'gitsync'`.
  - Android: `flutter_web_auth_2` ships an `AndroidManifest` `<activity>` with an `<intent-filter>` for the scheme; you only need to set the scheme. (Current manifest at `android/app/src/main/AndroidManifest.xml` has **no** custom-scheme intent-filter yet — this is the only native change needed.)
- **HTTPS App Link / Cloud Function callback (more robust, more setup):**
  - Callback URL = an `onRequest` Cloud Function `https://<region>-<project>.cloudfunctions.net/githubOAuthCallback` that 302-redirects to `gitsync://...` (or completes the exchange directly and deep-links back). Heavier; only needed if you want verified HTTPS redirects. Not required for the demo.

### Where the `client_secret` lives

- **Only** in Firebase Functions config: `defineSecret('GITHUB_OAUTH_CLIENT_SECRET')` (matches existing pattern `functions/src/config.ts` → `openaiKey = defineSecret('OPENAI_API_KEY')`, attached via `onCall({ region: REGION, secrets: [githubOAuthClientSecret] }, ...)`). The `client_id` can live in the app (it is public). **The secret never ships in the APK.** ✅
- The app needs only `client_id` + the custom scheme — both non-sensitive.

### Cloud Function contract (proposed)

```ts
// exchangeGitHubCode (onCall)
// request.data: { code: string; redirectUri?: string }
// requires request.auth (Firebase ID token) → uid
// 1. POST github.com/login/oauth/access_token with client_id+client_secret+code
// 2. on success: db.doc(`apps/gitsync/users/${uid}`).set({ githubAccessToken }, {merge:true})
// 3. return { ok: true }  | throws HttpsError('failed-precondition'|'permission-denied')
```

### Pros / Cons

- **Pros:** Works on Android (and iOS). Token is a real `gho_` user token with `repo`+`read:user`, identical to today's web token, so **zero backend changes** beyond the new function. Secret stays server-side. Fits "Flutter + Firebase only" (browser tab + Cloud Function, no external host). Reuses existing `defineSecret`/`onCall` conventions.
- **Cons:** Requires a **separate GitHub OAuth App** (or reuse the existing one) with a callback URL + custom-scheme manifest entry. Two sign-in steps for the user on Android (Firebase GitHub login, then "Connect GitHub" for API scopes) — though you can collapse UX by chaining them. `flutter_web_auth_2` adds a dependency + a tiny native manifest change.

### Packages / pieces

- Flutter: `flutter_web_auth_2` (system-browser OAuth, custom-scheme callback), `crypto`/`dart:math` for `state`, existing `cloud_functions` to call the exchange. (`url_launcher: ^6.3.0` already present but does **not** capture the redirect — `flutter_web_auth_2` is what closes the loop.)
- Functions: new `exchangeGitHubCode` handler, `defineSecret('GITHUB_OAUTH_CLIENT_SECRET')`, GitHub token-exchange POST (use `fetch`/`@octokit` — `@octokit/rest` already a dep, or plain `fetch`).
- Native: one `<intent-filter>` (provided by `flutter_web_auth_2`) for scheme `gitsync` in `android/app/src/main/AndroidManifest.xml`.

---

## Q3 — GitHub Device Flow (no redirect, no secret on device)

### How it works

1. App `POST https://github.com/login/device/code` with `client_id` + `scope` → gets `device_code`, `user_code`, `verification_uri`, `interval`, `expires_in`.
2. App shows the `user_code` and tells the user to open `https://github.com/login/device` and enter it (can launch via `url_launcher`).
3. App (or a Cloud Function) polls `POST https://github.com/login/oauth/access_token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code` + `device_code` until it returns `access_token` (handling `authorization_pending`, `slow_down`).
4. Store token in `users/{uid}.githubAccessToken` (if a Cloud Function polls, it writes directly; if the app polls, it sends the final token to a function to store — though device flow's whole appeal is *no secret needed at all*).

### Secret situation

- Device flow **does not require a `client_secret`** when "Enable Device Flow" is turned on for the OAuth App. So polling can even happen **client-side** with only the public `client_id`. (A Cloud Function *can* poll instead, but it's optional here — there's no secret to protect.)

### Pros / Cons

- **Pros:** No redirect URI, **no custom URL scheme / manifest change**, no `client_secret` anywhere. Simplest native footprint. Works fully within "Flutter + Firebase only". Good fallback if `flutter_web_auth_2` deep-linking is fiddly.
- **Cons:** Clunkier UX (user manually types a code into a browser on github.com). Polling logic (interval, `slow_down`, expiry) must be implemented. Same token-expiry characteristics as Q2 (still an OAuth-App user token). For a demo, the typed-code UX is the main downside.

### Cloud-Function-polls variant

- Feasible but awkward: a callable that polls synchronously risks the function timeout (`onCall` default 60s; device codes can take longer). Better to poll from the app and only call a function to **persist** the final token (or skip the function and write via Firestore rules if a user may write their own token field — but writing tokens via client is a security smell; prefer a tiny `storeGitHubToken` callable that validates and writes). Net: device flow leans toward client-side polling + a thin store-function.

---

## Q4 — GitHub App vs OAuth App, and token expiry / revocation

### Token types

| Mechanism | Token | Default expiry | Refreshable? | Secret needed |
|---|---|---|---|---|
| **OAuth App** (classic) | `gho_...` user token | **Non-expiring by default** (until user/admin revokes, or app deletes auth) | No refresh token in classic mode | `client_secret` for code-exchange (not for device flow) |
| **OAuth App with "Token Expiration" opt-in** | `gho_...` (8h) + `ghr_...` refresh (6mo) | 8 hours | **Yes** (`ghr_` refresh token) | `client_secret` to refresh |
| **GitHub App (user-to-server)** | `ghu_...` | 8 hours (when expiration enabled, default for GitHub Apps) | **Yes** (`ghr_` refresh token, ~6 months) | `client_secret` (+ App private key for app-level) |

### Key facts

- **"Bad credentials" (401)** means the token is **revoked, expired, or scope-insufficient**. For a classic OAuth-App token that normally doesn't expire, "Bad credentials" most commonly means the user **revoked the app's authorization**, the org **enforced SSO** the token isn't authorized for, or GitHub auto-revoked due to **inactivity (1 year)** or a detected leak.
- **OAuth App default tokens do NOT auto-refresh** — there is no refresh token unless you opt into "User-to-server token expiration." Once dead, you must re-run the OAuth flow.
- **GitHub Apps** (and OAuth Apps with expiration enabled) give a **refresh token** (`ghr_`, ~6 months) so a Cloud Function can mint a fresh 8h `access_token` without re-prompting the user — this is the **most robust long-term** option, but it requires storing+rotating the refresh token server-side (extra Cloud Function logic) and GitHub Apps have a different permission model (fine-grained, installation-based) that may change how `repo`/`read:user` scopes map.

### Most robust long-term

1. **Best robustness:** GitHub **App** (or OAuth App with token-expiration enabled) → refresh token → a Cloud Function silently refreshes. No user re-prompt for ~6 months.
2. **Simplest & matches today's behavior:** classic OAuth App non-expiring `gho_` token (what web already produces). Robust *until revoked*; when it dies you must re-prompt (Q5).

For a course demo, the classic non-expiring `gho_` token (Q2) is the pragmatic match — it behaves exactly like the existing web token. Refreshable tokens (GitHub App) are the "production-grade" upgrade if time allows.

---

## Q5 — Detecting a stale token and re-prompting

### Detection (backend)

- Every consumer already reads `users/{uid}.githubAccessToken` and throws `HttpsError('failed-precondition', 'No GitHub access token found...')` when **absent**. They do **not** yet distinguish a present-but-**rejected** token (GitHub returns 401 "Bad credentials").
- Pattern to add: in the GitHub client / each handler, catch GitHub `401` and throw a **distinct, machine-readable** error so the app can react, e.g.:
  ```ts
  throw new HttpsError('unauthenticated', 'GITHUB_TOKEN_INVALID');
  // or: failed-precondition with a stable code field
  ```
  (The existing `verifyRepoAccess` catch in `addRepo.ts` already special-cases `status === 404`; add a `status === 401` branch.)

### Re-prompt (app)

- App catches the `cloud_functions` `FirebaseFunctionsException` with that code → shows a "Reconnect GitHub" prompt → re-runs the Q2/Q3 flow → the exchange function overwrites `users/{uid}.githubAccessToken`.
- Optional proactive check: a lightweight callable `validateGitHubToken` that does `GET /user` and reports valid/invalid, called on app start or before heavy operations.
- Optional cleanup: when a 401 is detected server-side, clear/flag the stored token so the UI can reflect "disconnected" state.

---

## Caveats / Not found

- **Verify-before-build (Q1):** Re-confirm against the live FlutterFire issue tracker + the pinned `firebase_auth: ^4.4.0` changelog that Android still doesn't pass the GitHub OAuth token through `signInWithProvider`. Established behavior as of Jan-2026 cutoff is "still null on Android," but this single claim drives the whole effort, so re-check it.
- External GitHub OAuth/token-expiry specifics (8h access / 6mo refresh, device-flow no-secret) are from GitHub's published OAuth docs as of the knowledge cutoff; treat exact durations as "confirm in current GitHub docs."
- `flutter_web_auth_2` exact version/API and its bundled Android intent-filter requirement should be pinned from pub.dev at implementation time.
- No internal spec under `.trellis/spec/` was found describing the OAuth flow; `docs/SETUP.md §B.4` is referenced by `authentication.dart` but was not read in this pass (referenced for the Firebase Console GitHub provider enablement).
