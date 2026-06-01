// GitSync forwarder bot entry point.
//
// Captures messages from mapped Discord channels, runs a first-pass noise
// filter, and forwards the survivors to the discordMessageIngest Cloud Function.
// Stateless Cloud Functions can't hold a Discord gateway connection, so this
// runs separately (locally / on a VPS). See ARCHITECTURE.md §7.2.
import { Client, Events, GatewayIntentBits } from 'discord.js';

import { loadConfig } from './config';
import { shouldKeepMessage } from './filter';
import { sendWithRetry, type IngestPayload } from './ingest';

const cfg = loadConfig();

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
});

client.once(Events.ClientReady, (c) => {
  console.log(`[bot] logged in as ${c.user.tag}`);
  console.log(`[bot] forwarding ${cfg.channelRepoMap.size} channel(s) to ${cfg.ingestUrl}`);
});

client.on(Events.MessageCreate, (msg) => {
  // 1. Only forward channels we're configured to watch.
  const repoId = cfg.channelRepoMap.get(msg.channelId);
  if (!repoId) return;

  // 2. First-pass noise filter (same rules as the server-side second pass).
  if (
    !shouldKeepMessage({
      isBot: msg.author.bot,
      content: msg.content,
      attachmentCount: msg.attachments.size,
    })
  ) {
    return;
  }

  // 3. Build the payload and forward WITHOUT awaiting — a slow POST must not
  //    block discord.js from processing later messages (ARCHITECTURE §7.2).
  const payload: IngestPayload = {
    repoId,
    messageId: msg.id,
    channelId: msg.channelId,
    authorId: msg.author.id,
    authorName: msg.author.username,
    content: msg.content,
    mentionedUserIds: [...msg.mentions.users.keys()],
    timestamp: msg.createdAt.toISOString(),
  };

  void sendWithRetry(cfg, payload);
});

client.login(cfg.botToken).catch((e) => {
  console.error(`[bot] login failed: ${String(e)}`);
  process.exit(1);
});
