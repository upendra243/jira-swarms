---
name: jira-swarms
description: Parallel development workflow for multiple Jira tickets. Fetches tickets, batch triage with codebase-aware clarifying questions (Product + Technical), conflict detection, isolated git worktrees, optional Docker containers or local servers per ticket, parallel implementation via Task subagents, headless browser testing, Jira screenshot uploads, Bitbucket/GitHub PRs, and batch Telegram notification. Supports Django, Flask, FastAPI; run with Docker or without. Use when the user says "run jira-swarms on PROJ-101, PROJ-102" or asks to work on multiple Jira tickets at once.
---

# jira-swarms — Parallel Jira Dev Workflow

Orchestrates parallel development of multiple Jira tickets. Each ticket gets its own **git worktree** and either a **Docker container** or a **local app process** (separate port). All paths and project-specific settings are driven by environment variables so you can use this with any repo. Supports **Django** (default), **Flask**, and **FastAPI**; can run **with Docker** or **without Docker** (native/local).

## Prerequisites

- **Git (required)**:
  - A working Git CLI (`git` 2.5+ with worktree support) must be installed **before** running the installer (the installer itself uses `git clone` and cannot install Git for you).
- **Jira CLI (required for Jira operations)**:
  - A `jira` CLI must be available and configured for your Jira server (e.g. the open-source [`go-jira` CLI](https://github.com/go-jira/jira)).
  - The `install.sh` script will detect the absence of a `jira` CLI and, on macOS with Homebrew, can optionally install `go-jira` for you; on other platforms it prints installation instructions.
- **Per-project config (recommended for freelancers / multiple clients)**:
  - For each app repo, jira-swarms uses a per-project config file: `~/.jira-swarms/config/<project-id>.env`.
  - This file is the **primary source of truth** for:
    - Jira: `JIRA_API_TOKEN`, `JIRA_USER`, `JIRA_BASE_URL`
    - PR provider: `PR_PROVIDER` (`bitbucket` or `github`)
    - Bitbucket: `BB_USER`, `BB_API_TOKEN`, `BB_REPO_SLUG` (e.g. `owner/repo`)
    - GitHub: `GH_TOKEN` **or** `GITHUB_TOKEN`, `GH_REPO_SLUG` (e.g. `owner/repo`)
    - Worktree paths to copy: `JIRA_WORKTREE_COPY_PATHS` (comma-separated, repo-relative)
    - **Run mode:** `JIRA_USE_DOCKER` — `true` (Docker containers per ticket) or `false` (local app process per worktree). If unset, the skill asks on first use and saves to config.
    - **App run command (Docker mode):** `JIRA_APP_RUN_CMD` — command run inside the container (e.g. `python manage.py runserver 0.0.0.0:8000`). Default when `manage.py` exists: Django runserver. For Flask/FastAPI set as needed.
    - **App run command (without Docker):** `JIRA_LOCAL_RUN_CMD` — template for starting the app in the worktree; use `{{PORT}}` for the assigned port (e.g. `python manage.py runserver 0.0.0.0:{{PORT}}`, `flask run --host=0.0.0.0 --port {{PORT}}`, `uvicorn myapp:app --host 0.0.0.0 --port {{PORT}}`). Required when `JIRA_USE_DOCKER=false`.
    - Optional: `JIRA_LOCAL_START_SCRIPT` — path to a script that receives `JIRA_WORKTREE_DIR` and `JIRA_PORT` (env) and starts the app; alternative to `JIRA_LOCAL_RUN_CMD`.
    - Optional path overrides: `JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`
- **Env vars (optional overrides, e.g. CI or debugging)**:
  - If set in the shell, `JIRA_API_TOKEN`, `JIRA_USER`, `JIRA_BASE_URL`, `PR_PROVIDER`, `BB_*`, `GH_*`,
    `JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`, `JIRA_WORKTREE_COPY_PATHS`, `JIRA_USE_DOCKER`, `JIRA_LOCAL_RUN_CMD`, `JIRA_APP_RUN_CMD`
    override values loaded from the per-project config.
- **Browser tests**: `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`.
- **Docker (only when `JIRA_USE_DOCKER=true`):**
  - **Docker** and **docker-compose** must be installed. When `JIRA_USE_DOCKER=false`, Docker is not required.
- **Other tools**:
  - **Git 2.5+** with worktree support.
  - Optional: **Playwright** (for bundled browser-login example), **Telegram** env vars for notifications.

## Workflow Checklist

```
- [ ] Step 1: Parse input & batch fetch tickets
- [ ] Step 2: Triage — impact analysis, conflict detection, complexity classification
- [ ] Step 2d: Clarifying questions (CRITICAL — Product + Technical, two layers per ticket)
- [ ] Step 3: Human checkpoint (hard gate — ALL questions answered, execution plan confirmed)
- [ ] Step 4: Infrastructure setup — worktrees; then Docker image + containers (if JIRA_USE_DOCKER=true) or start local servers (if false); Jira transitions
- [ ] Step 5: Dispatch workers — parallel implementation via Task subagents
- [ ] Step 5c-post: Read Release Notes & run DB migrations (BEFORE browser testing)
- [ ] Step 5d: Browser testing & screenshots (sequential, per SUCCESS ticket)
- [ ] Step 6: Post-processing & cleanup — Jira updates, screenshots, PRs, notifications
```

---

## Step 1: Parse Input & Batch Fetch Tickets

### 1a. Parse Ticket Keys
Extract from user's message. Accept comma/space/newline separated.

### 1b. Validate Environment and derive defaults

- Assume the agent is running inside Cursor with an open git repo.
- Derive defaults:
  - `MULTI_JIRA_SKILL_DIR` — directory containing this `SKILL.md` (typically `~/.cursor/skills/jira-swarms` when installed via `install.sh`).
  - `JIRA_GIT_REPO_DIR` — git root of the current workspace (`git rev-parse --show-toplevel`).
  - `PROJECT_ID` — a stable, filesystem-safe identifier derived from `JIRA_GIT_REPO_DIR` (e.g. hash or sanitized path).
  - `PROJECT_CONFIG_PATH` — `~/.jira-swarms/config/${PROJECT_ID}.env`.
  - `JIRA_WORKTREE_BASE` — default to `~/.jira-swarms/worktrees/${PROJECT_ID}` **unless** overridden by env.
- **First run for this repo (no config yet):**
  - If `PROJECT_CONFIG_PATH` does not exist, run a **one-time, per-project setup wizard**:
    - Ask the user for Jira details: `JIRA_BASE_URL`, `JIRA_USER`, `JIRA_API_TOKEN`.
    - Ask for PR provider and credentials:
      - `PR_PROVIDER` (`bitbucket` or `github`).
      - If Bitbucket: `BB_USER`, `BB_API_TOKEN`, `BB_REPO_SLUG`.
      - If GitHub: `GH_TOKEN` **or** `GITHUB_TOKEN`, `GH_REPO_SLUG`.
    - Ask for **files to copy into each worktree**:
      - Prompt: “Which local config files should be copied into each worktree (e.g. `.env`, `.env.local`, `local_settings.py`)? Comma-separated, or leave blank for none.”
      - Save answer as `JIRA_WORKTREE_COPY_PATHS` (comma-separated, repo-relative).
    - **Run mode:** Ask: "Run with Docker (containers per ticket) or without Docker (native/local)? [Docker / Without Docker]". Save as `JIRA_USE_DOCKER=true` or `JIRA_USE_DOCKER=false`.
    - **App start command:**
      - If **Docker:** Ask: "What command starts your app inside the container? Use port 8000 (mapped to host)." If repo has `manage.py`, suggest default: `python manage.py runserver 0.0.0.0:8000`. For Flask: `flask run --host=0.0.0.0 --port 8000`. For FastAPI: `uvicorn myapp:app --host 0.0.0.0 --port 8000`. Save as `JIRA_APP_RUN_CMD`.
      - If **Without Docker:** Ask: "What command starts your app? Use {{PORT}} where the port goes." Suggest: Django `python manage.py runserver 0.0.0.0:{{PORT}}`, Flask `flask run --host=0.0.0.0 --port {{PORT}}`, FastAPI `uvicorn myapp:app --host 0.0.0.0 --port {{PORT}}`. Save as `JIRA_LOCAL_RUN_CMD`.
    - Optionally ask for path overrides: `JIRA_WORKTREE_BASE`, `JIRA_GIT_REPO_DIR` (rare; default is usually fine).
    - Write all collected values into `PROJECT_CONFIG_PATH` (shell-style `KEY=VALUE`), with a comment indicating it was generated for this repo.
- **Existing config but `JIRA_USE_DOCKER` not set:**
  - If `PROJECT_CONFIG_PATH` exists but `JIRA_USE_DOCKER` is not set (or empty), ask once: "This project doesn't have a run mode set. Use Docker (containers per ticket) or without Docker (native/local)? [Docker / Without Docker]". Append `JIRA_USE_DOCKER=...` to the config (and if Without Docker, prompt for `JIRA_LOCAL_RUN_CMD` if not set; if Docker, prompt for `JIRA_APP_RUN_CMD` if not set).
- **Load per-project config and apply overrides:**
  - If `PROJECT_CONFIG_PATH` exists, load it (shell-style `key=value`). Values in this file override the derived defaults.
  - Finally, allow explicit environment variables (`JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`,
    `JIRA_WORKTREE_COPY_PATHS`, `JIRA_USE_DOCKER`, `JIRA_LOCAL_RUN_CMD`, `JIRA_APP_RUN_CMD`, Jira and PR vars) to override both defaults and per-project config. This is mainly for CI or advanced users.

For diagnostics, print which values are in effect:

```bash
for VAR in JIRA_API_TOKEN JIRA_USER JIRA_BASE_URL \
           BB_USER BB_API_TOKEN BB_REPO_SLUG \
           GH_TOKEN GITHUB_TOKEN GH_REPO_SLUG \
           PR_PROVIDER \
           BROWSER_TEST_USER BROWSER_TEST_PASSWORD \
           JIRA_GIT_REPO_DIR JIRA_WORKTREE_BASE MULTI_JIRA_SKILL_DIR \
           JIRA_WORKTREE_COPY_PATHS JIRA_LOCAL_CONFIG_PATH \
           JIRA_USE_DOCKER JIRA_LOCAL_RUN_CMD JIRA_APP_RUN_CMD; do
    echo "$VAR: ${!VAR:+SET}"
done
echo "PROJECT_ID: ${PROJECT_ID:-unknown}"
echo "PROJECT_CONFIG: ${PROJECT_CONFIG_PATH:-~/.jira-swarms/config/<project-id>.env}"
```

**NEVER use `git stash`** if your repo has a gitignored local config file (e.g. `settings.py`) that must always be present.

### 1c. Fetch All Tickets (parallel)
Launch parallel Task subagents (one per ticket, up to 4) to fetch ticket details. Use the bundled script or your own:
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/fetch-jira-ticket.sh" <KEY>
```
If set, `MULTI_JIRA_FETCH_JIRA_SCRIPT` overrides the script path.

---

## Step 2: Triage — Impact Analysis & Conflict Detection

### 2a. Codebase Impact Analysis (parallel)
For each ticket, use Grep, SemanticSearch, and Glob. Focus on the paths that matter for your repo — set `MULTI_JIRA_IMPACT_PATHS` (space-separated dirs) or document in README (e.g. `src/`, `app/`, `lib/`).

### 2b. Conflict Detection
Build file overlap matrix. Group into execution waves:
- **Wave 1**: Tickets with NO file overlaps (parallel)
- **Wave 2+**: Tickets that conflict with previous waves
- Max **3 tickets** per wave (resource limit)

### 2c. Complexity Classification
| Complexity | Criteria | Confidence |
|-----------|----------|-----------|
| Trivial | 1-2 files, simple fix | 90-95% |
| Standard | 3-5 files, model+admin+template | 75-85% |
| Complex | 6+ files, payment/checkout, new integrations | 40-60% |

### 2d. Clarifying Questions (CRITICAL)
For each ticket, generate **TWO separate layers**: **Product Questions** (build the right thing) and **Technical Questions** (build the right way). At least 1 per layer per ticket or explicit "N/A" with reasoning. Questions MUST be codebase-informed; look for cross-ticket dependencies; NEVER assume.

---

## Step 3: Human Checkpoint (Hard Gate)

Present full triage report with two-layer questions per ticket, conflict analysis, and execution plan. **Do NOT proceed until ALL questions for ALL tickets are answered.**

---

## Step 4: Infrastructure Setup

Branch by `JIRA_USE_DOCKER`: when `true`, use Docker (4b + 4f); when `false`, skip 4b and use 4f-alt (local servers).

### 4a. Update Main Branch
**NEVER `git stash`.** Ignore expected local changes (e.g. `settings.py`, `docker-compose.override.yml`).

```bash
cd "$JIRA_GIT_REPO_DIR"
git checkout master
git pull --ff-only
```

### 4b. Build / Reuse Docker Image (only when JIRA_USE_DOCKER=true)
When `JIRA_USE_DOCKER` is not `true`, skip this step.

```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/build-image.sh"
```
Uses `JIRA_GIT_REPO_DIR`, `JIRA_WORKER_IMAGE`, optional `JIRA_BASE_IMAGE_CANDIDATES` or `JIRA_DOCKERFILE`. Container command should use `JIRA_APP_RUN_CMD` (Django/Flask/FastAPI examples in Prerequisites).

### 4c. Create Git Worktrees + Copy Local Config
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/create-worktree.sh" \
    "<KEY>" "<KEY>-<short-description>" "master"
```
Worktrees are created under `$JIRA_WORKTREE_BASE/$MULTI_JIRA_WORKTREE_PREFIX<KEY>` (e.g. `wt-PROJ-101`).

**CRITICAL: Copy your project local config files into each worktree.** They are usually gitignored, so worktrees won't have them by default.

- Use `JIRA_WORKTREE_COPY_PATHS` (comma-separated, paths relative to repo root) to declare which files should be copied.
- For backwards compatibility, if `JIRA_WORKTREE_COPY_PATHS` is empty but legacy `JIRA_LOCAL_CONFIG_PATH` is set, treat it as a single entry.

Example shell logic:

```bash
# Backwards-compat: prefer JIRA_WORKTREE_COPY_PATHS; fall back to JIRA_LOCAL_CONFIG_PATH if set
if [[ -z "${JIRA_WORKTREE_COPY_PATHS:-}" && -n "${JIRA_LOCAL_CONFIG_PATH:-}" ]]; then
  JIRA_WORKTREE_COPY_PATHS="$JIRA_LOCAL_CONFIG_PATH"
fi

IFS=',' read -r -a _multi_jira_copy_paths <<< "${JIRA_WORKTREE_COPY_PATHS:-}"

for WT_DIR in "${JIRA_WORKTREE_BASE}"/${MULTI_JIRA_WORKTREE_PREFIX}*; do
    [ -d "$WT_DIR" ] || continue
    for rel in "${_multi_jira_copy_paths[@]}"; do
        # Trim whitespace
        rel="${rel#"${rel%%[![:space:]]*}"}"
        rel="${rel%"${rel##*[![:space:]]}"}"
        [[ -z "$rel" ]] && continue

        src="$JIRA_GIT_REPO_DIR/$rel"
        dst="$WT_DIR/$rel"
        [ -e "$src" ] || continue
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    done
done
```

**NEVER modify** the copied files from the workflow.

### 4d. Transition Tickets to "Dev Started"
```bash
for KEY in <ALL_TICKET_KEYS>; do
    CURRENT_STATUS=$(jira issue view $KEY --raw | jq -r '.fields.status.name')
    if [ "$CURRENT_STATUS" = "Pending Dev Start" ]; then
        jira issue move $KEY "Dev Started"
    fi
done
```
Use your Jira transition names if different.

### 4e. Assign Ports
Sequential from **8101**: ticket 1 → 8101, ticket 2 → 8102, etc.

### 4f. Generate & Start Docker Containers (only when JIRA_USE_DOCKER=true)
When `JIRA_USE_DOCKER` is not `true`, skip this step and use **4f-alt** instead.

Use `JIRA_DOCKER_NETWORK` (same network as your main app), `JIRA_WORKER_IMAGE`, `JIRA_COMPOSE_PROJECT` (e.g. `jira-swarms`). Set container `command` from `JIRA_APP_RUN_CMD` (e.g. Django `python manage.py runserver 0.0.0.0:8000`, Flask `flask run --host=0.0.0.0 --port 8000`, FastAPI `uvicorn myapp:app --host 0.0.0.0 --port 8000`). Inline environment vars from your main app service into each worker; do not rely on `env_file:` alone. Create any log/cache dirs your app needs in the container `command`. Example template:

```yaml
# docker-compose.multi-jira.yml (generate per run)
version: '3.7'
networks:
  your_app_network:
    external: true
services:
  worker-<key>:
    image: multi-jira-worker:latest
    container_name: worker-<key>
    command: <from JIRA_APP_RUN_CMD, e.g. python manage.py runserver 0.0.0.0:8000>
    ports:
      - '<PORT>:8000'
    volumes:
      - <WORKTREE_PATH>:/code
    environment:
      # Copy from your main app service
    networks:
      - your_app_network
    restart: 'no'
```

Start:
```bash
docker-compose -p "${MULTI_JIRA_COMPOSE_PROJECT:-jira-swarms}" -f docker-compose.multi-jira.yml up -d
```
Health check after ~90s (app startup may be slow). View logs with the same `-p` and `-f`.

### 4f-alt. Start Local App Servers (only when JIRA_USE_DOCKER=false)
When `JIRA_USE_DOCKER` is `false`, skip 4b and 4f. After creating worktrees and assigning ports, start the app in each worktree on its assigned port from the **host** (not in a container).

1. Write a **servers list file** (e.g. `$JIRA_GIT_REPO_DIR/.jira-swarms-local-servers.list`) with one line per ticket: `WORKTREE_DIR PORT` (space-separated). Example:
   ```
   /path/to/worktrees/wt-PROJ-101 8101
   /path/to/worktrees/wt-PROJ-102 8102
   ```
2. Run the start script:
   ```bash
   bash "${MULTI_JIRA_SKILL_DIR}/scripts/start-local-servers.sh"
   ```
   The script reads `JIRA_LOCAL_RUN_CMD` (or `JIRA_LOCAL_START_SCRIPT`), substitutes `{{PORT}}` with the assigned port, runs the command from each worktree directory in the background, and writes PIDs to a known file (e.g. `.jira-swarms-pids` in the repo dir) for cleanup.
3. Wait for servers to listen (e.g. curl or similar on `http://127.0.0.1:<PORT>` with timeout ~60–90s).

Without Docker, worktrees typically share the same DB/Redis (e.g. localhost); ensure your app run command or env uses the correct config.

**Optional — JIRA_LOCAL_START_SCRIPT contract:** If using a custom script instead of `JIRA_LOCAL_RUN_CMD`, the script receives env vars `JIRA_WORKTREE_DIR` and `JIRA_PORT`. It may start the app in foreground (caller will background it and record PID) or in background; exit 0 on success so the orchestrator can retry or report on failure.

---

## Step 5: Dispatch Workers (Parallel Implementation)

### 5a. Launch Task Subagents
For each ticket, launch a Task subagent with `subagent_type: "generalPurpose"`. Provide ticket details, worktree path, port, affected files, implementation and circuit-breaker rules, and commit/push/PR instructions. Workers create PRs using the generic script (e.g. `"${MULTI_JIRA_SKILL_DIR}/scripts/create-pr.sh"`), which dispatches to Bitbucket or GitHub based on `PR_PROVIDER`, env vars, or the git remote.

**Worker return JSON MUST include `test_urls`** — list of 1–3 key URLs to validate. Example:
```json
{
  "status": "success",
  "key": "PROJ-101",
  "branch": "PROJ-101-feature-name",
  "pr_url": "https://bitbucket.org/.../pull-requests/...",
  "files_changed": ["src/app.py"],
  "test_urls": [
    {"url": "/admin/", "description": "Admin home", "needs_login": true}
  ]
}
```
Max 3 URLs per ticket; use descriptive `description`; if no testable URL, return `"test_urls": []`.

### 5b. Circuit Breaker Rules (in worker prompt)
- Max 3 attempts per lint error → suppress; max 3 test failures → bail as "partial"; max 3 server crashes → skip testing, commit as "partial"; stuck 3+ reads → bail as "failed".

### 5c. Collect Results
Each ticket ends as SUCCESS, PARTIAL, or FAILED. Never abort the batch.

---

## Step 5c-post: Read Release Notes & Run Migrations (BEFORE browser testing)

**NEVER run DROP migrations** (DROP COLUMN, DROP TABLE) in a shared dev DB — document them for manual execution. **ADD migrations** (new columns, new tables) are fine. Before browser tests, run any ADD migrations from Jira Release Notes comments (e.g. via Python/ORM or SQL inside the app container). Without this, admin or app pages may crash with missing column errors.

---

## Step 5d: Browser Testing & Screenshots

Run **sequentially** (one port at a time). Use the bundled example script or your own (set `JIRA_BROWSER_LOGIN_SCRIPT` if different):

```bash
python3 "${MULTI_JIRA_SKILL_DIR}/scripts/browser-login-example.py" \
    --base-url "http://127.0.0.1:<PORT>" \
    --artifacts-dir "artifacts/<KEY>" \
    --urls '/path/|Description 1' '/path2/|Description 2'
```
Login flow is **app-specific** — the bundled script is an example for a two-step modal login; adapt or replace for your app. Validate test record IDs exist in dev DB before using detail URLs.

**Jira screenshot rules:** Upload only **feature confirmation** screenshots to Jira (not login success, not errors). See [reference.md](reference.md).

---

## Step 6: Post-Processing & Cleanup

### 6a. Jira Updates
- **FAILED**: Move back to "Pending Dev Start" + comment with error.
- **PARTIAL**: Stay in "Dev Started" + comment.
- **SUCCESS**: Release notes (if any), dev comment with screenshots, transition to "Code Review Done".

### 6b. Upload Screenshots & Post Dev Comment (SUCCESS)
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/upload-jira-screenshots.sh" \
    "<KEY>" "artifacts/<KEY>" "/tmp/jira_dev_comment_<KEY>.txt"
```
Requires `JIRA_API_TOKEN`, `JIRA_USER`, `JIRA_BASE_URL`.

### 6c. Transition (SUCCESS)
```bash
jira issue move <KEY> "Code Review Done"
```

### 6d. Cleanup
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/cleanup.sh" --force
```
When `JIRA_USE_DOCKER=true`, the script stops Docker containers and removes worktrees. When `JIRA_USE_DOCKER=false`, it runs `scripts/stop-local-servers.sh` (kills processes by PID file), then removes worktrees and generated files.

### 6e. Report to User
Summary per ticket (SUCCESS/PARTIAL/FAILED), PR links, browser test results, screenshot counts, any manual steps. Optional: `batch-notify-telegram.sh` with results JSON.

---

## Epic workflow (single branch, multiple tasks)

When the batch is one epic — one branch, multiple sub-tasks — commit one task at a time, run tests, ask user to review, then continue with the next task on the same branch. Worktrees are for **parallel** branches; one worktree is enough for sequential tasks on one branch.

---

## Error Handling & Circuit Breakers

- **Orchestrator:** Stop and ask user on git dirty main, Docker build fail (when `JIRA_USE_DOCKER=true`), missing env vars, or all tickets failed. Retry up to 3 then skip: container fail (Docker mode), worktree creation fail, **local server start fail** (when `JIRA_USE_DOCKER=false`, e.g. port in use, command not found); ask user on git push fail.
- **Worker:** Lint loop → suppress after 3; test failures → partial after 3; server crash → skip testing after 3; stuck → failed after 3.
- **Browser:** Max 2 login attempts per port; max 3 consecutive screenshot failures across tickets then stop browser testing; per-URL timeout 30s. Browser failures do not downgrade SUCCESS to FAILED.

---

## Additional Resources

- [reference.md](reference.md) — architecture, lessons learned, Docker and browser testing details.
- Single-ticket workflow: use the same scripts (fetch, create-pr, browser-login) for one ticket; trigger and steps are documented in README.
