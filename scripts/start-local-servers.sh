#!/usr/bin/env bash
set -euo pipefail
# Start local app servers for each worktree (when JIRA_USE_DOCKER=false).
# Requires: JIRA_GIT_REPO_DIR, JIRA_LOCAL_RUN_CMD or JIRA_LOCAL_START_SCRIPT.
# Reads: .jira-swarms-local-servers.list (one line per server: WORKTREE_DIR PORT).
# Writes: .jira-swarms-pids (one PID per line, same order as list) in JIRA_GIT_REPO_DIR.

REPO_DIR="${JIRA_GIT_REPO_DIR:?Set JIRA_GIT_REPO_DIR}"
REPO_DIR="$(cd "$REPO_DIR" && pwd)"
LIST_FILE="${JIRA_LOCAL_SERVERS_LIST:-$REPO_DIR/.jira-swarms-local-servers.list}"
PID_FILE="${JIRA_LOCAL_PIDS_FILE:-$REPO_DIR/.jira-swarms-pids}"

if [ ! -f "$LIST_FILE" ]; then
    echo "ERROR: Servers list not found: $LIST_FILE" >&2
    echo "Create it with one line per ticket: WORKTREE_DIR PORT" >&2
    exit 1
fi

if [ -n "${JIRA_LOCAL_START_SCRIPT:-}" ]; then
    RUN_CMD=""
elif [ -n "${JIRA_LOCAL_RUN_CMD:-}" ]; then
    RUN_CMD="$JIRA_LOCAL_RUN_CMD"
else
    echo "ERROR: Set JIRA_LOCAL_RUN_CMD or JIRA_LOCAL_START_SCRIPT" >&2
    exit 1
fi

# Clear previous PIDs
: > "$PID_FILE"

echo "=== jira-swarms Start Local Servers ==="
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    read -r wt_dir port <<< "$line"
    [ -d "$wt_dir" ] || { echo "WARNING: Not a directory: $wt_dir" >&2; continue; }

    if [ -n "${JIRA_LOCAL_START_SCRIPT:-}" ]; then
        export JIRA_WORKTREE_DIR="$wt_dir"
        export JIRA_PORT="$port"
        (
            cd "$wt_dir"
            bash "$JIRA_LOCAL_START_SCRIPT" &
            echo $! >> "$PID_FILE"
        )
    else
        cmd="${RUN_CMD//\{\{PORT\}\}/$port}"
        (
            cd "$wt_dir"
            eval "$cmd" &
            echo $! >> "$PID_FILE"
        )
    fi
    echo "  Started: $wt_dir on port $port"
done < "$LIST_FILE"

echo "PIDs written to: $PID_FILE"
echo "=== Done ==="
