#!/usr/bin/env bash
set -euo pipefail
# Stop local app servers started by start-local-servers.sh.
# Requires: JIRA_GIT_REPO_DIR (or pass PID file via JIRA_LOCAL_PIDS_FILE).
# Reads PIDs from .jira-swarms-pids and kills them.

REPO_DIR="${JIRA_GIT_REPO_DIR:-}"
if [ -n "${JIRA_LOCAL_PIDS_FILE:-}" ]; then
    PID_FILE="$JIRA_LOCAL_PIDS_FILE"
else
    REPO_DIR="${JIRA_GIT_REPO_DIR:?Set JIRA_GIT_REPO_DIR (or JIRA_LOCAL_PIDS_FILE)}"
    PID_FILE="$REPO_DIR/.jira-swarms-pids"
fi

echo "=== jira-swarms Stop Local Servers ==="
if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found: $PID_FILE"
    echo "=== Done ==="
    exit 0
fi

while IFS= read -r pid || [ -n "$pid" ]; do
    [ -z "$pid" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        echo "  Stopped PID: $pid"
    fi
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "Removed: $PID_FILE"
echo "=== Done ==="
