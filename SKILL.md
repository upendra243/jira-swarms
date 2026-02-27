---
name: jira-swarms
description: Parallel development workflow for multiple Jira tickets. Fetches tickets, batch triage with codebase-aware clarifying questions (Product + Technical), conflict detection, isolated git worktrees, Docker containers per ticket, parallel implementation via Task subagents, headless browser testing, Jira screenshot uploads, Bitbucket/GitHub PRs, and batch Telegram notification. Use when the user says "run jira-swarms on PROJ-101, PROJ-102" or asks to work on multiple Jira tickets at once.
---

# jira-swarms — Parallel Jira Dev Workflow

Orchestrates parallel development of multiple Jira tickets. Each ticket gets its own **git worktree** and **Docker container** (separate port). All paths and project-specific settings are driven by environment variables so you can use this with any repo.

## Prerequisites

- **Git (required)**:
  - A working Git CLI (`git` 2.5+ with worktree support) must be installed **before** running the installer (the installer itself uses `git clone` and cannot install Git for you).
- **Jira CLI (required for Jira operations)**:
  - A `jira` CLI must be available and configured for your Jira server (e.g. the open-source [`go-jira` CLI](https://github.com/go-jira/jira)).
  - The `install.sh` script will detect the absence of a `jira` CLI and, on macOS with Homebrew, can optionally install `go-jira` for you; on other platforms it prints installation instructions.
- **Per-project config (recommended for freelancers / multiple clients)**:
  - Config lives under `~/.jira-swarms/config/`. You can have multiple `*.env` files there (e.g. `frontend.env`, `backend.env`). The workflow **chooses the one for this project**: `~/.jira-swarms/config/<PROJECT_ID>.env` (e.g. `frontend.env` for a frontend repo, `backend.env` for a backend repo).
  - That file is the **primary source of truth** for:
    - Jira: `JIRA_API_TOKEN`, `JIRA_USER`, `JIRA_BASE_URL`
    - PR provider: `PR_PROVIDER` (`bitbucket` or `github`)
    - Bitbucket: `BB_USER`, `BB_API_TOKEN`, `BB_REPO_SLUG` (e.g. `owner/repo`)
    - GitHub: `GH_TOKEN` **or** `GITHUB_TOKEN`, and `GH_REPO_SLUG` (e.g. `owner/repo`)
    - Worktree paths to copy: `JIRA_WORKTREE_COPY_PATHS` (comma-separated, repo-relative)
    - Optional path overrides: `JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`
    - Main branch name: `JIRA_MAIN_BRANCH` (default `master`; use `main` for newer repos)
- **Env vars (optional overrides, e.g. CI or debugging)**:
  - If set in the shell, `JIRA_API_TOKEN`, `JIRA_USER`, `JIRA_BASE_URL`, `PR_PROVIDER`, `BB_*`, `GH_*`,
    `JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`, `JIRA_WORKTREE_COPY_PATHS`, and `JIRA_MAIN_BRANCH`
    override values loaded from the per-project config.
- **Browser tests**: `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`.
- **Other tools**:
  - **Docker** and **docker-compose** installed.
  - Optional: **Playwright** (for bundled browser-login example), **Telegram** env vars for notifications.
- **Jira CLI** configured for your Jira server.
- **Docker** and **docker-compose** installed.
- **Git 2.5+** with worktree support.
- Optional: **Playwright** (for bundled browser-login example), **Telegram** env vars for notifications.

## Workflow Checklist

```
- [ ] Step 1: Parse input & batch fetch tickets
- [ ] Step 2: Triage — impact analysis, conflict detection, complexity classification
- [ ] Step 2d: Clarifying questions (CRITICAL — Product + Technical, two layers per ticket)
- [ ] Step 3: Human checkpoint (hard gate — ALL questions answered, execution plan confirmed)
- [ ] Step 4: Infrastructure setup — worktrees, Docker image, containers, Jira transitions
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
  - `PROJECT_ID` — a stable, filesystem-safe identifier for this repo. **Default convention:** use the **repo folder name** (i.e. `basename(JIRA_GIT_REPO_DIR)`, e.g. `backend`, `frontend`). Allow an explicit `PROJECT_ID` env var to override when the user prefers a custom slug.
  - `PROJECT_CONFIG_PATH` — `~/.jira-swarms/config/${PROJECT_ID}.env`. The workflow checks for this file; you can have other `*.env` files in `~/.jira-swarms/config/` (e.g. `frontend.env`, `backend.env`) and the one used is the one matching this project.
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
    - Optionally ask for path overrides: `JIRA_WORKTREE_BASE`, `JIRA_GIT_REPO_DIR` (rare; default is usually fine).
    - Write all collected values into `PROJECT_CONFIG_PATH` (shell-style `KEY=VALUE`), with a comment indicating it was generated for this repo.
- **Load per-project config and apply overrides:**
  - If `PROJECT_CONFIG_PATH` exists, load it (shell-style `key=value`). Values in this file override the derived defaults.
  - Finally, allow explicit environment variables (`JIRA_GIT_REPO_DIR`, `JIRA_WORKTREE_BASE`, `MULTI_JIRA_SKILL_DIR`,
    `JIRA_WORKTREE_COPY_PATHS`, Jira and PR vars) to override both defaults and per-project config. This is mainly for CI or advanced users.

For diagnostics, print which values are in effect:

```bash
for VAR in JIRA_API_TOKEN JIRA_USER JIRA_BASE_URL \
           BB_USER BB_API_TOKEN BB_REPO_SLUG \
           GH_TOKEN GITHUB_TOKEN GH_REPO_SLUG \
           PR_PROVIDER \
           BROWSER_TEST_USER BROWSER_TEST_PASSWORD \
           JIRA_GIT_REPO_DIR JIRA_WORKTREE_BASE MULTI_JIRA_SKILL_DIR \
           JIRA_WORKTREE_COPY_PATHS JIRA_LOCAL_CONFIG_PATH JIRA_MAIN_BRANCH; do
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
| Standard | 3-5 files, typical CRUD or feature scope | 75-85% |
| Complex | 6+ files, payment/checkout, new integrations | 40-60% |

### 2d. Clarifying Questions (CRITICAL — MOST IMPORTANT STEP)

For each ticket, generate **TWO separate layers** of questions:

**Layer 1: Product Questions** — ensure building the right thing  
**Layer 2: Technical Questions** — ensure building the right way

Rules:
1. At least 1 question per layer per ticket, OR explicit "N/A" with reasoning
2. Questions MUST be codebase-informed (cite files, line numbers)
3. Look for **cross-ticket dependencies**
4. NEVER assume
5. **ALWAYS include a browser-testing applicability question in the Technical layer.** Default is **YES (browser testing required)** unless the user explicitly answers that browser testing is not needed. Example technical question per ticket:
   - `Browser Testing: Should we run browser/Playwright tests for this ticket? (default YES). If NO, please confirm: "Browser Testing: Not needed because <reason>".`

---

## Step 3: Human Checkpoint (Hard Gate)

Present full triage report with two-layer questions per ticket, conflict analysis, and execution plan. **Do NOT proceed until ALL questions for ALL tickets are answered.**

---

## Step 4: Infrastructure Setup

### 4a. Update Main Branch
**NEVER `git stash`.** Ignore expected local changes (e.g. `settings.py`, `docker-compose.override.yml`).

```bash
cd "$JIRA_GIT_REPO_DIR"
git checkout "${JIRA_MAIN_BRANCH:-master}"
git pull --ff-only
```

### 4b. Build / Reuse Docker Image
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/build-image.sh"
```
Uses `JIRA_GIT_REPO_DIR`, `JIRA_WORKER_IMAGE`, optional `JIRA_BASE_IMAGE_CANDIDATES` or `JIRA_DOCKERFILE`.

### 4c. Create Git Worktrees + Copy Local Config
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/create-worktree.sh" \
    "<KEY>" "<KEY>-<short-description>" "${JIRA_MAIN_BRANCH:-master}"
```
Worktrees are created under `$JIRA_WORKTREE_BASE/$MULTI_JIRA_WORKTREE_PREFIX<KEY>` (e.g. `wt-PROJ-101`).

**CRITICAL: Copy your project local config files into each worktree.** They are usually gitignored, so worktrees won't have them by default.

- `JIRA_WORKTREE_COPY_PATHS` is read from the project config (`PROJECT_CONFIG_PATH`) or from the environment. Use it (comma-separated, paths relative to repo root) to declare which files should be copied.
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

### 4f. Generate & Start Docker Containers
Use `JIRA_DOCKER_NETWORK` (same network as your main app), `JIRA_WORKER_IMAGE`, `JIRA_COMPOSE_PROJECT` (e.g. `jira-swarms`). Inline environment vars from your main app service into each worker; do not rely on `env_file:` alone. Create any log/cache dirs your app needs in the container `command`. Example template:

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
    command: <your app start command, e.g. python manage.py runserver 0.0.0.0:8000>
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

**Troubleshooting (common examples; adapt for your stack):**
- `AttributeError: 'module' has no attribute 'X'` (Python) → Re-copy local config from main repo into worktree
- `OperationalError: Can't connect to MySQL` / `connection refused` (DB) → Check env vars match main app service
- `No such file or directory: '/path/to/log/...'` → Add `mkdir -p` for those paths in container `command`
- `ConnectionError: X:6379` (Redis) / similar for other services → Verify host/port in compose matches main app network

---

## Step 5: Dispatch Workers (Parallel Implementation)

### 5a. Launch Task Subagents
For each ticket, launch a Task subagent with `subagent_type: "generalPurpose"`. Provide ticket details, worktree path, port, affected files, implementation and circuit-breaker rules, and commit/push/PR instructions. Workers create PRs using the generic script (e.g. `"${MULTI_JIRA_SKILL_DIR}/scripts/create-pr.sh"`), which dispatches to Bitbucket or GitHub based on `PR_PROVIDER`, env vars, or the git remote.

**Legacy codebases (Python 2, no encoding declaration):** NEVER use non-ASCII characters (em dash, smart quotes, Unicode) in code or comments — causes `SyntaxError: Non-ASCII character`. Use only plain ASCII.

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

**NEVER run DROP migrations** (DROP COLUMN, DROP TABLE) in a shared dev DB — document them for manual execution. **ADD migrations** (new columns, new tables) are fine.

**CRITICAL (MANDATORY STEP)**: Before running browser tests, you MUST:

1. **Check Jira comments** for any Release Notes containing migration SQL (e.g. `ALTER TABLE`, `CREATE TABLE`).
2. Either:
   - Run **only ADD migrations** (ALTER TABLE ADD COLUMN, CREATE TABLE) inside the app container, then add a Jira comment: `Release Notes: Applied ADD-only SQL in dev as per ticket notes.`
   - Or, if there are **no Release Notes / no schema changes in code**, still add both Jira comments:
     - `Release Notes: No specific Release Instruction.`
     - `Migration: No migration needed (no schema changes in code for this ticket).`

Do NOT run any DROP statements from Release Notes in shared dev DB — document them for manual execution only.

### 1. Read existing Jira Release Notes comments

For each SUCCESS ticket:
```bash
jira issue view <KEY> --comments 2>&1
```
Look for comments containing "Release Notes" with SQL statements.

### 2. Run migrations inside the app container

Use your app's migration tool (ORM, SQL, etc.) inside the app container — avoid raw DB CLI if it may not be installed. Run ONLY ADD migrations. If no Release Notes exist, proceed to browser testing.

---

## Step 5d: Browser Testing & Screenshots

**Goal**: Validate each SUCCESS ticket with headless browser testing where meaningful, and explicitly document when browser testing is not applicable. Capture best-case screenshots as evidence. Max 3 test cases per ticket.

This step is performed by the **main orchestrator** (NOT subagents) — browser is a single shared session; sequential testing across ports is fast enough.

### 5d-0. Validate Test URLs

Before testing, verify that any specific record IDs in `test_urls` exist in the dev database. Tickets often reference production IDs (e.g. `/admin/product/123/`) that may not exist in dev.

If a record ID doesn't exist in dev, either:
- Find a valid ID from the dev DB: `SELECT id FROM <table> ORDER BY id DESC LIMIT 5`
- Use the list page URL instead of the change form URL
- Skip that specific URL

**Never upload a "DoesNotExist" error screenshot to Jira.**

### 5d-1. Prepare Artifacts Directory

```bash
cd "$JIRA_GIT_REPO_DIR"
for KEY in <SUCCESS_TICKET_KEYS>; do
    mkdir -p artifacts/$KEY/
done
```

### 5d-2. Ticket Categories and Expectations

- **UI / order-tracking / customer-visible behavior** → Browser testing is **MANDATORY**. Validate that new/changed elements are visible where expected.
- **Pure backend / cron / reporting (no suitable URL-based test surface)** → Browser testing is **OPTIONAL**, but you MUST add a Jira comment:
  - `Browser Testing: Not applicable (no UI/API surface suitable for URL-based validation).`
  - `Browser Testing: Validated via non-UI flow (e.g. cron run / direct DB checks); no browser flow available.`

### 5d-3. Test Each SUCCESS Ticket (sequential, per-port)

For each ticket with `status: "success"` and non-empty `test_urls`:

```bash
python3 "${JIRA_BROWSER_LOGIN_SCRIPT:-${MULTI_JIRA_SKILL_DIR}/scripts/browser-login-example.py}" \
    --base-url "http://127.0.0.1:<PORT>" \
    --artifacts-dir "artifacts/<KEY>" \
    --urls '/path/|Description 1' '/path2/|Description 2'
```

Login flow is **app-specific** — use `browser-login-template.py` or adapt the example; see [docs/custom-login-flow.md](docs/custom-login-flow.md).

#### Jira Screenshot Rules (CRITICAL)

Only **feature confirmation screenshots** go to Jira:

| Upload to Jira? | Screenshot Type | Example |
|:---:|---|---|
| **YES** | Feature working correctly — confirms ticket scope | Admin page with new field visible |
| **NO** | Login success — intermediate step | `login-success.png` |
| **NO** | Error/traceback pages | `OperationalError` page |
| **NO** | Internal debug screenshots | `error-login-no-password.png` |

**Jira comment rules:**
- Do NOT include internal infrastructure details (port numbers, container names, Docker info)
- Do NOT reference error states unless the feature cannot work at all
- Focus on: what was tested, what passed, PR link
- If browser testing was **not run or not applicable**, you MUST still add a short Jira note:
  - `Browser Testing: Not applicable (backend-only change).`
  - `Browser Testing: Blocked by environment (container/login issues) – manual verification required.`

### 5d-4. Build Test Summary

After testing all tickets, build a per-ticket test summary:

```
PROJ-101:
  - Admin home: PASS (admin-home.png)
  - Product list: PASS (product-list.png)

PROJ-102:
  - Order export page: PASS (order-export-page.png)
```

Store this summary for Step 6 (Jira comment).

### 5d-5. Handle Failures

- **Individual test FAIL**: Note in summary, do NOT block workflow. PR can still be created — mention failure in PR description.
- **All tests FAIL for a ticket**: Downgrade ticket status from SUCCESS to PARTIAL. Add note: "Implementation complete but browser validation failed."
- **Container down / unreachable**: Skip testing for that ticket. Note "container unreachable" in summary.

### 5d-6. Circuit Breaker

- Max 2 login attempts per port — if both fail, skip that ticket's browser tests
- Max 3 screenshot failures in a row (across all tickets) — stop browser testing, proceed to Step 6 with whatever screenshots were captured
- Per-URL timeout: 30s, then skip that URL

---

## Step 6: Post-Processing & Cleanup

### 6a. Jira Updates
- **FAILED**: Move back to "Pending Dev Start" + comment with error.
- **PARTIAL**: Stay in "Dev Started" + comment.
- **SUCCESS**: Release notes (if any), dev comment with screenshots, transition to "Code Review Done".

### 6b. Upload Screenshots & Post Dev Comment (SUCCESS)

**Rules for Jira comments:** NO internal infra details (ports, container names); NO error state descriptions unless feature is broken; only PASS test cases and their descriptions; keep it stakeholder/QA friendly.

Generate comment file:
```bash
cat > /tmp/jira_dev_comment_<KEY>.txt << 'COMMENT_EOF'
Browser Test Results

Changes:
- <change 1 from worker result>
- <change 2>

Verified:
- <Test description 1> - PASS
- <Test description 2> - PASS

Screenshots attached.

PR: <Bitbucket/GitHub PR URL>
COMMENT_EOF
```

Upload screenshots + post comment:
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/upload-jira-screenshots.sh" \
    "<KEY>" "artifacts/<KEY>" "/tmp/jira_dev_comment_<KEY>.txt"
```

**Release Notes (if applicable):** If the worker generated Release Notes and none exist in Jira yet. (Note: The `jq` below assumes Jira Cloud comment structure; Jira Server might use different fields — adapt if needed.)
```bash
EXISTING_RELEASE_NOTES=$(jira issue view <KEY> --raw | jq -r \
  '[.fields.comment.comments[].body | .. | .text? // empty] | join(" ")' 2>/dev/null \
  | grep -c "Release Notes" || true)

if [ "$EXISTING_RELEASE_NOTES" -eq 0 ]; then
    jira issue comment add <KEY> --no-input -T /tmp/jira_release_notes_<KEY>.txt
fi
```

### 6c. Transition (SUCCESS)

Before transitioning, discover valid target states (project workflows differ):
```bash
jira issue view <KEY> --raw | jq '.transitions'
```

Then choose the appropriate state (e.g. "Code Review", "Code Review Done"):
```bash
jira issue move <KEY> "Code Review Done"
```

Jira lifecycle (adjust state names per project):
- **Pending Dev Start** → **Dev Started** (Step 4d)
- **Dev Started** → **Code Review** / **Code Review Done** (SUCCESS)
- **Dev Started** → stays **Dev Started** (PARTIAL)
- **Dev Started** → **Pending Dev Start** (FAILED — moved back)

### 6d. Cleanup
```bash
bash "${MULTI_JIRA_SKILL_DIR}/scripts/cleanup.sh" --force
```

### 6e. Report to User
Summary per ticket (SUCCESS/PARTIAL/FAILED), PR links, browser test results, screenshot counts, any manual steps.

**Telegram (optional, once per batch):** After building the summary, if the user has Telegram configured (`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in project config or env), send a batch notification. Write a results JSON file (see `scripts/sample-results.json` for format: `{"tickets":[{"key","summary","status","pr_url"?, "error"?, "reason"?}]}`), then run:
```bash
# Source project config so TELEGRAM_* are set if configured
set -a; [ -f "${PROJECT_CONFIG_PATH}" ] && . "${PROJECT_CONFIG_PATH}"; set +a
bash "${MULTI_JIRA_SKILL_DIR}/scripts/batch-notify-telegram.sh" /path/to/results.json
```
The script exits 0 if Telegram is not configured (no-op); otherwise it sends one message with the batch summary.

---

## Epic workflow (single branch, multiple tasks)

When the batch is one epic — one branch, multiple sub-tasks — commit one task at a time, run tests, ask user to review, then continue with the next task on the same branch. Worktrees are for **parallel** branches; one worktree is enough for sequential tasks on one branch.

**Benefits:** Smaller review surface, earlier feedback, no big-bang at the end, parallel flow (review + dev), clear rollback at task granularity.

---

## Error Handling & Circuit Breakers

- **Orchestrator (STOP and ask user):** Git dirty on main, Docker build fail, missing env vars, all tickets failed.
- **Orchestrator (retry up to 3, then skip):** Container fail, worktree creation fail; ask user on git push fail; Jira API error → skip Jira, report results.
- **Worker:** Lint loop → suppress after 3; test failures → partial after 3; server crash → skip testing after 3; stuck → failed after 3.
- **Browser:** Max 2 login attempts per port; max 3 consecutive screenshot failures across tickets then stop browser testing; per-URL timeout 30s. Browser testing is **non-blocking** — failures do NOT change ticket status from SUCCESS to FAILED; tests are recorded as SKIP and noted in Jira comment.

---

## Additional Resources

- [reference.md](reference.md) — architecture, lessons learned, Docker and browser testing details.
- [WORKFLOW_DIAGRAM.md](WORKFLOW_DIAGRAM.md) — Mermaid flowchart of the full workflow.
- Single-ticket workflow: use the same scripts (fetch, create-pr, browser-login) for one ticket; trigger and steps are documented in README.
