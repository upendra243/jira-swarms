# jira-swarms

Run multiple Jira tickets in parallel from [Cursor](https://cursor.com): fetch, triage, worktrees, then either **Docker** workers or **local app servers** per ticket, implementation, optional browser tests and PRs.

**Supported stacks:** Python apps — **Django** (default), **Flask**, **FastAPI**. The skill works **with Docker** (containers per ticket) or **without Docker** (native/local process per worktree). On first use (or when run mode isn’t set), you’re asked: *Docker or Without Docker?*

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

That’s enough for fetch, triage, questions, and worktrees. You’ll be prompted once for run mode (Docker or without Docker) and app start command if needed. The rest is optional.

## Architecture

```text
User: "run jira-swarms on PROJ-101, PROJ-102"
  │
  ▼
ORCHESTRATOR (Cursor Agent)
  1. Fetch all tickets (parallel)
  2. Triage: impact + conflict detection + two-layer questions
  3. Human checkpoint (one interaction)
  4. Setup: worktrees + (Docker image + containers, or local app servers)
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
  - `~/.jira-swarms/config/<project-id>.env` — overrides for one app repo (Jira URL/user/token, `JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, **`JIRA_USE_DOCKER`**, **`JIRA_LOCAL_RUN_CMD`** / **`JIRA_APP_RUN_CMD`**, etc.).
  - `~/.jira-swarms/worktrees/<project-id>/...` — default parent for git worktrees for that project.
- **Repo detection:** when run inside Cursor, the skill treats the **current workspace git root** as the default `JIRA_GIT_REPO_DIR`. You only need to override it if you deliberately want a different repo.

## Optional (only when you use that part)

- **PRs** — choose your provider:
  - **Bitbucket**: set `BB_USER`, `BB_API_TOKEN`, `BB_REPO_SLUG` so the workflow can create Bitbucket PRs.
  - **GitHub**: set `GH_TOKEN` **or** `GITHUB_TOKEN` and `GH_REPO_SLUG` so the workflow can create GitHub PRs.
  - Optional: set `PR_PROVIDER` to `bitbucket` or `github` to override auto-detection (from env vars or git remote).
- **Browser tests + Jira screenshots** — set `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`, and `JIRA_API_TOKEN` + `JIRA_USER` + `JIRA_BASE_URL`. The bundled login script is an **example** for one app’s flow; for your app, follow the guided process in [docs/custom-login-flow.md](docs/custom-login-flow.md) to implement your own script (or use the template and set `JIRA_BROWSER_LOGIN_SCRIPT`).
- **Telegram** — set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` for a batch summary.

Env vars are documented in `SKILL.md` and in the comments in your per-project config files under `~/.jira-swarms/config/`. You only need to set the ones you actually use.

## Your repo

- If your app has **gitignored local config files** (e.g. `.env`, `.env.local`, `local_settings.py`), set `JIRA_WORKTREE_COPY_PATHS` (comma-separated paths from repo root) so the workflow copies them into each worktree. For older setups you can still use the legacy `JIRA_LOCAL_CONFIG_PATH` (single path); it is treated as a one-item `JIRA_WORKTREE_COPY_PATHS`.
- **Run mode:** Set `JIRA_USE_DOCKER=true` (default) for Docker containers per ticket, or `JIRA_USE_DOCKER=false` to run the app locally in each worktree. When `JIRA_USE_DOCKER=false`, set `JIRA_LOCAL_RUN_CMD` with `{{PORT}}` for the assigned port (e.g. `python manage.py runserver 0.0.0.0:{{PORT}}`, `flask run --host=0.0.0.0 --port {{PORT}}`). When using Docker, set `JIRA_APP_RUN_CMD` for the container command if the default (Django runserver on 8000) doesn’t fit.
- **Docker (when `JIRA_USE_DOCKER=true`):** Workers use the same network as your main app; set `JIRA_DOCKER_NETWORK` if needed. Defaults are in the scripts.

## License

MIT. See [LICENSE](LICENSE). Issues and PRs welcome — [CONTRIBUTING](CONTRIBUTING.md).
