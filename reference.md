# Reference: jira-swarms Technical Details

## Architecture

```
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
     Shared External Services (DB, Redis, etc.)
```

## Directory Layout (example)

```
$MULTI_JIRA_SKILL_DIR/           ← jira-swarms skill (this repo)
  SKILL.md
  reference.md
  scripts/

$JIRA_GIT_REPO_DIR/              ← Your main repo (stays on main branch)
$JIRA_WORKTREE_BASE/
  ${MULTI_JIRA_WORKTREE_PREFIX}PROJ-101/   ← Worktree (temporary)
  ${MULTI_JIRA_WORKTREE_PREFIX}PROJ-102/
```

## Critical Lessons Learned

### 1. NEVER git stash
Your project likely has a gitignored local config file (e.g. `settings.py`) with dev values. Stashing loses it.

### 2. Copy local config to worktrees
Worktrees are clean checkouts and won't have gitignored files. Copy the paths listed in `JIRA_WORKTREE_COPY_PATHS` (comma-separated, repo-relative) from the main repo into each worktree immediately after creation. For backwards compatibility, if `JIRA_WORKTREE_COPY_PATHS` is empty but legacy `JIRA_LOCAL_CONFIG_PATH` is set, treat it as a single path to copy.

### 3. Inline environment vars in compose
Using only `env_file:` can cause value mismatches. Prefer copying the exact key-value pairs from your main app service into each worker's `environment:` block.

### 4. Use the same Docker network as your main app
Workers must be on the same Docker network as your main app container to reach DB, Redis, etc. Set `JIRA_DOCKER_NETWORK` accordingly.

### 5. Create log/cache dirs in container command
If your app expects certain host paths (logs, uploads), ensure the container `command` runs `mkdir -p` for those paths before starting the app.

### 6. App startup can be slow
Wait at least 60–90s before health-checking. First HTTP request may be slow (cold start).

### 7. Jira transition names
Use your project's transition names (e.g. "Dev Started", "Code Review Done"). List them with `jira issue view <KEY> --raw | jq -r '.transitions[].name'`.

### 8. Jira Screenshot & Comment Rules
**Only feature confirmation screenshots** belong in Jira — they prove the ticket scope.

**NEVER upload to Jira:** login success, error/traceback pages, internal debug screenshots.

**NEVER include in Jira comments:** port numbers, container names, Docker details, error state descriptions (unless feature is broken).

**DO include:** what was tested, PASS results, PR link, screenshot count. DB migration details go in **Release Notes** (separate comment), not in Browser Test Results.

The script `upload-jira-screenshots.sh` skips filenames matching `login-*` or `error-*`.

### 9. Run migrations BEFORE browser testing
Check Jira Release Notes comments for migration SQL. Run ADD migrations (new columns, new tables) before hitting admin/app pages; never run DROP in a shared dev DB — document for manual execution.

### 10. Validate test record IDs in dev DB
Tickets may reference production IDs that don't exist in dev. Before testing a detail URL, verify the ID exists in dev or use a list URL instead.

### 11. ASCII-only in legacy codebases
If your app is Python 2 or has no encoding declaration, avoid non-ASCII in code/comments (em dash, smart quotes) to prevent `SyntaxError: Non-ASCII character`.

### 12. Jira comment updates
`upload-jira-screenshots.sh` edits an existing "Browser Test Results" comment in-place when present (Jira doesn't allow delete). If edit fails, it posts a new comment.

## Docker Strategy

- **Image:** Set `JIRA_WORKER_IMAGE` (default `multi-jira-worker:latest`). Use `JIRA_BASE_IMAGE_CANDIDATES` to tag an existing image, or `JIRA_DOCKERFILE` to build.
- **Ports:** 8101, 8102, 8103, ... (one per ticket). Your main dev server is unaffected.

## Browser Testing

- **Sequential:** Browser is a single session; run one ticket (one port) at a time.
- **Login script:** The workflow runs a headless script to log in and take screenshots. The bundled `scripts/browser-login-example.py` is an **app-specific example** (two-step modal login). To use browser testing with your app, follow the guided process in [docs/custom-login-flow.md](docs/custom-login-flow.md): implement your login using `scripts/browser-login-template.py` or adapt the example, then set `JIRA_BROWSER_LOGIN_SCRIPT` to your script path (default is the example script). Credentials: `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`.
- **Output:** JSON with `login` and `results` (per-URL status). Only PASS screenshots are saved; upload script filters login/error filenames for Jira.

## Conflict Detection

Tickets that touch overlapping files must run in different waves. No overlap → parallel. Max 3 workers per wave.

## Troubleshooting

```bash
# Full cleanup (worktrees + containers + generated files)
bash "${MULTI_JIRA_SKILL_DIR}/scripts/cleanup.sh" --force

# Container logs
docker logs worker-<key> 2>&1 | tail -20

# Force rebuild image
docker rmi multi-jira-worker:latest
bash "${MULTI_JIRA_SKILL_DIR}/scripts/build-image.sh"
```
