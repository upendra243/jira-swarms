#!/usr/bin/env bash
set -euo pipefail
# Requires: JIRA_GIT_REPO_DIR, JIRA_WORKTREE_BASE. Optional: MULTI_JIRA_WORKTREE_PREFIX, MULTI_JIRA_COMPOSE_PROJECT
REPO_DIR="${JIRA_GIT_REPO_DIR:?Set JIRA_GIT_REPO_DIR}"
WORKTREE_BASE="${JIRA_WORKTREE_BASE:?Set JIRA_WORKTREE_BASE}"
PREFIX="${MULTI_JIRA_WORKTREE_PREFIX:-wt-}"
COMPOSE_PROJECT="${MULTI_JIRA_COMPOSE_PROJECT:-jira-swarms}"
COMPOSE_FILE="$REPO_DIR/docker-compose.multi-jira.yml"
ENV_FILE="$REPO_DIR/.env.multi-jira-workers"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true
cd "$REPO_DIR"

echo "=== jira-swarms Cleanup ==="

echo "--- Stopping worker containers ---"
if [ -f "$COMPOSE_FILE" ]; then
    docker-compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
fi
STALE=$(docker ps -a --filter "name=worker-" --format "{{.Names}}" 2>/dev/null || true)
for C in $STALE; do docker rm -f "$C" 2>/dev/null || true; done
echo "Worker containers stopped."

echo "--- Removing generated files ---"
[ -f "$COMPOSE_FILE" ] && rm -f "$COMPOSE_FILE" && echo "  Removed: docker-compose.multi-jira.yml"
[ -f "$ENV_FILE" ] && rm -f "$ENV_FILE" && echo "  Removed: .env.multi-jira-workers"

echo "--- Removing git worktrees ---"
for WT_DIR in "${WORKTREE_BASE}"/${PREFIX}*; do
    [ -d "$WT_DIR" ] || continue
    if [ "$FORCE" = false ] && cd "$WT_DIR" 2>/dev/null && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "  WARNING: $(basename $WT_DIR) has uncommitted changes! Skipping."
        cd "$REPO_DIR"; continue
    fi
    cd "$REPO_DIR"
    git worktree remove "$WT_DIR" --force 2>/dev/null || rm -rf "$WT_DIR"
    echo "  Removed: $(basename $WT_DIR)"
done

git worktree prune 2>/dev/null || true
echo "=== Cleanup Complete ==="
git worktree list
