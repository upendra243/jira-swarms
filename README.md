# jira-swarms

Run multiple Jira tickets in parallel from [Cursor](https://cursor.com): fetch, triage, worktrees, Docker workers, implementation, optional browser tests and PRs.

## Prerequisites

- **Git**: a working Git CLI (`git` 2.5+ with worktree support) installed and available on your `PATH`.
- **Jira CLI**: a `jira` command configured for your Jira server (for example, [`go-jira`](https://github.com/go-jira/jira)).
  - You can verify it is working with a known ticket key:
    ```bash
    jira issue view <TASK-ID>
    ```
    This should print the issue JSON or a formatted view without errors.

## Install

**One-click** (default code location: `~/.cursor/skills/jira-swarms`; prompts only if the directory exists or when run interactively):

```bash
curl -fsSL https://raw.githubusercontent.com/upendra243/jira-swarms/main/scripts/install.sh | bash
```

**Manual (same layout as one-click):**

```bash
mkdir -p ~/.cursor/skills
git clone https://github.com/upendra243/jira-swarms.git ~/.cursor/skills/jira-swarms
```

In Cursor, with your app repo open (a git repo):

```
run jira-swarms on PROJ-101, PROJ-102
```

That’s enough for fetch, triage, questions, worktrees, and Docker. The rest is optional.

## Architecture

```text
User: "run jira-swarms on PROJ-101, PROJ-102"
  │
  ▼
ORCHESTRATOR (Cursor Agent)
  1. Fetch all tickets (parallel)
  2. Triage: impact + conflict detection + two-layer questions
  3. Human checkpoint (one interaction)
  4. Setup: worktrees + Docker image + copy local config + containers
  5. Dispatch: Task subagents (up to 3 parallel)
  6. Post-process: Jira + PRs + cleanup
       │             │
       ▼             ▼
  Subagent 1    Subagent 2
  worktree-101  worktree-102
  port 8101     port 8102
       │             │
       └─────┬───────┘
             ▼
     Shared services (DB, Redis, etc.)
```

### Defaults and per-project config

- **Skill code location (default):** `~/.cursor/skills/jira-swarms` (where `install.sh` installs).
- **Per-project config + worktrees:** `~/.jira-swarms/`
  - `~/.jira-swarms/config/` can hold multiple `*.env` files (e.g. `frontend.env`, `backend.env`). The workflow **uses the one for this project**: `~/.jira-swarms/config/<project-id>.env` — e.g. `frontend.env` for a frontend repo, `backend.env` for a backend repo. Use the **repo folder name** as `<project-id>`.
  - `~/.jira-swarms/worktrees/<project-id>/...` — default parent for git worktrees for that project (same `<project-id>` as above).
- **Repo detection:** when run inside Cursor, the skill treats the **current workspace git root** as the default `JIRA_GIT_REPO_DIR`. You only need to override it if you deliberately want a different repo.

### Configuring per-project

On a **new machine** (or when you want to set things up without the first-run wizard), create the per-project config file and set `JIRA_WORKTREE_COPY_PATHS` there. You can have multiple `*.env` files in `~/.jira-swarms/config/` (e.g. `frontend.env`, `backend.env`); the workflow uses the one that matches this project (`<project-id>.env`).

1. **Choose your project id** — use the repo folder name (e.g. `backend`, `frontend`).
2. **Create the config file** for this project:
   ```bash
   mkdir -p ~/.jira-swarms/config
   touch ~/.jira-swarms/config/<project-id>.env
   ```
   Examples: `~/.jira-swarms/config/frontend.env` for a frontend repo, `~/.jira-swarms/config/backend.env` for a backend repo.
3. **Edit the file** and set at least Jira credentials and **files to copy into each worktree**:
   - **`JIRA_WORKTREE_COPY_PATHS`** — comma-separated paths **relative to the repo root** of the files to copy from your main clone into each worktree (e.g. gitignored `.env`, `.env.local`, `local_settings.py`). These are copied after creation so the worktree can run.
   - Example:
     ```bash
     # ~/.jira-swarms/config/backend.env
     JIRA_BASE_URL=https://your-domain.atlassian.net
     JIRA_USER=you@example.com
     JIRA_API_TOKEN=your-token
     JIRA_WORKTREE_COPY_PATHS=.env,.env.local
     ```
   Add `PR_PROVIDER`, `BB_*` or `GH_*` etc. if you use PRs (see SKILL.md).

If you already have this file on another machine, you can copy `~/.jira-swarms/config/<project-id>.env` to the new machine (same path) and adjust paths if needed; `JIRA_WORKTREE_COPY_PATHS` is the same list of repo-relative paths.

## Optional (only when you use that part)

- **PRs** — choose your provider:
  - **Bitbucket**: set `BB_USER`, `BB_API_TOKEN`, `BB_REPO_SLUG` so the workflow can create Bitbucket PRs.
  - **GitHub**: set `GH_TOKEN` **or** `GITHUB_TOKEN` and `GH_REPO_SLUG` so the workflow can create GitHub PRs.
  - Optional: set `PR_PROVIDER` to `bitbucket` or `github` to override auto-detection (from env vars or git remote).
- **Browser tests + Jira screenshots** — set `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`, and `JIRA_API_TOKEN` + `JIRA_USER` + `JIRA_BASE_URL`. The bundled login script is an **example** for one app’s flow; for your app, follow the guided process in [docs/custom-login-flow.md](docs/custom-login-flow.md) to implement your own script (or use the template and set `JIRA_BROWSER_LOGIN_SCRIPT`).
- **Telegram** — for batch-complete notifications. See [Telegram setup](#telegram-setup) below.

### Telegram setup

1. **Create a bot and get the token**
   - In Telegram, open [@BotFather](https://t.me/BotFather), send `/newbot`, follow the prompts, and copy the token (e.g. `8406255847:AAEfBl-...`).

2. **Get your chat ID** (numeric; the bot username is not valid).
   - Send a message to your bot (e.g. `/start` or any text), then run:
     ```bash
     curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
     ```
     In the JSON, find `"chat":{"id":5613219694,...}` — the `id` value (e.g. `5613219694`) is your chat ID. For groups, `id` is often negative.

3. **Set the env vars**
   - One-off in the current shell:
     ```bash
     export TELEGRAM_BOT_TOKEN="your-bot-token"
     export TELEGRAM_CHAT_ID="5613219694"
     ```
   - Or add the same two lines to `~/.jira-swarms/config/<project-id>.env` so the workflow can send notifications after each batch run.

4. **Test**
   ```bash
   ./scripts/batch-notify-telegram.sh "Hello from jira-swarms — Telegram test OK"
   ```
   You should see `Sent.` and receive the message in Telegram. See [docs/telegram-testing.md](docs/telegram-testing.md) for more options and troubleshooting.

Env vars are documented in `SKILL.md` and in the comments in your per-project config files under `~/.jira-swarms/config/`. You only need to set the ones you actually use.

## Your repo

- If your app has **gitignored local config files** (e.g. `.env`, `.env.local`, `local_settings.py`), set `JIRA_WORKTREE_COPY_PATHS` (comma-separated paths from repo root) so the workflow copies them into each worktree. For older setups you can still use the legacy `JIRA_LOCAL_CONFIG_PATH` (single path); it is treated as a one-item `JIRA_WORKTREE_COPY_PATHS`.
- **Docker:** workers use the same network as your main app; set `JIRA_DOCKER_NETWORK` if needed. Defaults are in the scripts.

## License

MIT. See [LICENSE](LICENSE). Issues and PRs welcome — [CONTRIBUTING](CONTRIBUTING.md).
