# Research: Internal code map — GitHub token storage & consumers

- **Query**: Where the GitHub access token is captured, stored, and consumed (for an Android token-refresh change).
- **Scope**: internal
- **Date**: 2026-06-16

## Capture (the broken-on-Android spot)

| File | Lines | Note |
|---|---|---|
| `lib/services/authentication.dart` | `logInWithGitHub()` (~45-82) | Web `signInWithPopup` → token; Android `signInWithProvider` → `credential is OAuthCredential ? .accessToken : null` ⇒ **null on Android**. |

## Storage (write path)

| File | Lines | Note |
|---|---|---|
| `lib/repositories/user_repo.dart` | 26, 65, 78 | `upsertUserFromAuth(... githubAccessToken)` writes `githubAccessToken` field (only when non-null). |
| `lib/models/app_user.dart` | 14-17, 42, 55, 70, 84 | `githubAccessToken` model field (`String?`); `toMap`/`fromMap`. Note: production wants encryption. |
| `lib/repositories/fake/fake_user_repo.dart` | 37-108 | fake mirror. |
| Firestore path | — | `apps/gitsync/users/{uid}.githubAccessToken`. |

## Consumers (backend — all read the same field)

| File | Lines | Behavior when token missing |
|---|---|---|
| `functions/src/handlers/getCommitGraph.ts` | 56-66 | `HttpsError('failed-precondition','No GitHub access token found...')`. |
| `functions/src/handlers/explainCommit.ts` | 57-58 | reads token; passes to flow. |
| `functions/src/handlers/addRepo.ts` | 44-54, 56-73 | missing → `failed-precondition`; `verifyRepoAccess` catch already special-cases `status===404` (add 401 here). |
| `functions/src/handlers/removeRepo.ts` | 59 | reads token. |
| `functions/src/handlers/importCollaborators.ts` | 44 | reads caller token. |
| `functions/src/tools/repoDocs.ts` | 191 | reads `createdBy` user token. |
| `functions/src/triggers/onTaskCreated.ts` | 58 | createIssue token. |
| `functions/src/triggers/onTaskDeleted.ts` | 50 | reads token. |
| `functions/src/triggers/onPullRequestOpened.ts` | (test 85) | token. |

## Cloud Functions conventions to reuse for a new exchange function

| File | Lines | Pattern |
|---|---|---|
| `functions/src/config.ts` | 9-13 | `defineSecret('OPENAI_API_KEY')`, `defineSecret('DISCORD_INGEST_SECRET')` ⇒ add `defineSecret('GITHUB_OAUTH_CLIENT_SECRET')`. |
| `functions/src/admin.ts` | 15 | `REGION = 'asia-east1'`, `db`. |
| `functions/src/handlers/discordChat.ts` | 9-13 | `onCall({ region: REGION, secrets: [openaiKey], timeoutSeconds }, ...)` + `request.auth` guard ⇒ template for `exchangeGitHubCode`. |
| `functions/src/handlers/addRepo.ts` | 22-28 | `onCall({region}, async (request)=>{ if(!request.auth)... uid=request.auth.uid })`. |
| `functions/src/index.ts` | 6-49 | every handler is `export`ed here → add `export { exchangeGitHubCode } from './handlers/exchangeGitHubCode'`. |
| `functions/package.json` | deps | `@octokit/rest@^21`, `firebase-admin`, `firebase-functions@^6`, `zod` available; plain `fetch` (Node 18+) usable for token exchange. |

## Flutter packages present (pubspec.yaml)

- `firebase_auth: ^4.4.0`, `cloud_functions: ^4.7.5`, `cloud_firestore: ^4.15.7`, `firebase_core: ^2.26.0`.
- `url_launcher: ^6.3.0` (can launch device-flow verification URL, but does NOT capture an OAuth redirect).
- **Missing / would add:** `flutter_web_auth_2` (for the redirect-capture web OAuth flow).

## Native

- `android/app/src/main/AndroidManifest.xml`: has intent-filters for the main launcher + text/plain share, but **no custom-URL-scheme intent-filter** for an OAuth callback yet → must add (or rely on the one `flutter_web_auth_2` provides) if going the Q2 web-auth route. The device-flow route (Q3) needs no manifest change.
