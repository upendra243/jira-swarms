# Testing Telegram integration

## What you need

1. **`TELEGRAM_BOT_TOKEN`** — From [@BotFather](https://t.me/BotFather) on Telegram:
   - Start a chat with @BotFather → `/newbot` → follow prompts → copy the token (e.g. `123456789:ABCdefGHI...`).

2. **`TELEGRAM_CHAT_ID`** — The **numeric** chat ID where messages are sent (not the bot username).
   - Send a message to your bot (direct message or in a group), then call:
     ```bash
     curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates" | jq .
     ```
     In the JSON, find `"chat\":{\"id\": 5613219694,...}` — that `id` value is your chat ID (for groups it is often negative).

## Quick test (plain message)

From the project root (or anywhere, with the script path correct):

```bash
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"
./scripts/batch-notify-telegram.sh "Hello from jira-swarms — Telegram test OK"
```

You should see `Sent.` and get the message in Telegram. If you see `SKIP: Telegram not configured.` or `Failed.`, check that both env vars are set and the token/chat ID are correct.

## Test batch format (results JSON)

The script can also send a formatted summary from a results JSON file:

```bash
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"
./scripts/batch-notify-telegram.sh scripts/sample-results.json
```

Use the included `scripts/sample-results.json` for a quick test (see its structure for the expected format).

## Where to set env vars for the workflow

- **One-off:** `export TELEGRAM_BOT_TOKEN=...` and `export TELEGRAM_CHAT_ID=...` in your shell before running the script or the workflow.
- **Persistent (per project):** Add the same variables to `~/.jira-swarms/config/<project-id>.env` so the batch workflow can call `batch-notify-telegram.sh` with the results file after a run.

## Troubleshooting

| Symptom | Check |
|--------|--------|
| `SKIP: Telegram not configured.` | Both `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` must be set and non-empty. |
| `ERROR: TELEGRAM_CHAT_ID must be a numeric chat ID` | You set the bot username (e.g. `upendra_jerry_bot`). Use a **number** from @userinfobot or `getUpdates` instead. |
| `Failed.` or no message | Token or chat ID wrong; bot not started in chat (send `/start` to the bot in that chat); chat ID for groups is negative. |
| Batch run: `jq` errors | Install `jq`; ensure the passed file exists and has a `.tickets` array. |
