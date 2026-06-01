# GitSync Discord Forwarder Bot

Captures messages from configured Discord channels and forwards them to the
`discordMessageIngest` Cloud Function, which writes them to Firestore
(`apps/gitsync/repos/{repoId}/discordMessages/{messageId}`). Later AI flows
(handoff / daily report) RAG-search these messages.

This bot runs **separately** from the Firebase Functions repo because Cloud
Functions are stateless and can't hold a persistent Discord gateway connection
(ARCHITECTURE.md §7.2).

## How it works

```
Discord channel → [bot] messageCreate
  → channel mapped to a repoId?         (else ignore)
  → shouldKeepMessage() first-pass filter (else drop — saves a function call)
  → POST {payload} with x-ingest-secret → discordMessageIngest Cloud Function
        → second-pass filter + messageId dedup → Firestore
```

Noise is filtered twice (here + server-side) and deduped by `messageId`, so junk
and resends don't flood the database.

## Setup

1. **Create the Discord bot**
   - [Discord Developer Portal](https://discord.com/developers/applications) → New Application → Bot.
   - Enable **Message Content Intent** (Bot → Privileged Gateway Intents).
   - Copy the bot token. Invite the bot to your server with the `bot` scope and
     "Read Messages/View Channels" + "Read Message History" permissions.

2. **Install + configure**
   ```powershell
   cd discord-bot
   npm install
   Copy-Item .env.example .env
   # edit .env: DISCORD_BOT_TOKEN, DISCORD_INGEST_SECRET, INGEST_URL, CHANNEL_REPO_MAP
   ```
   - `DISCORD_INGEST_SECRET` must match what the Cloud Function uses
     (`functions/.secret.local` for the emulator, Secret Manager in prod).
   - `INGEST_URL`: emulator vs prod URL — see `.env.example`.
   - `CHANNEL_REPO_MAP`: `channelId:repoId` pairs (right-click a channel → Copy Channel ID;
     enable Developer Mode in Discord settings first).

3. **Run**
   ```powershell
   npm run dev       # tsx watch (development)
   # or
   npm run build && npm start
   ```

## Local end-to-end test (with the Firebase emulator)

```powershell
# Terminal 1 — from repo root
Copy-Item functions/.secret.local.example functions/.secret.local   # set DISCORD_INGEST_SECRET
firebase emulators:start --only functions,firestore

# Terminal 2 — discord-bot/ with .env pointing INGEST_URL at the emulator
npm run dev
```

- Post a normal message in a mapped channel → a doc appears in the Firestore
  emulator UI (http://127.0.0.1:4000) under `apps/gitsync/repos/{repoId}/discordMessages`.
- Post junk (`ok`, `+1`, a lone emoji, `haha`) → nothing is written.
- Resend the same message → the function returns `{ dup: true }`, no duplicate.

## Keep in sync

`src/filter.ts` deliberately mirrors `functions/src/tools/discordFilter.ts`. If you
change the noise rules in one, change both.
