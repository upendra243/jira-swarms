#!/usr/bin/env bash
set -euo pipefail
# Requires: JIRA_GIT_REPO_DIR, JIRA_WORKTREE_BASE. Optional: MULTI_JIRA_WORKTREE_PREFIX (default: wt-)
REPO_DIR="${JIRA_GIT_REPO_DIR:?Set JIRA_GIT_REPO_DIR (path to your git repo)}"
WORKTREE_BASE="${JIRA_WORKTREE_BASE:?Set JIRA_WORKTREE_BASE (parent dir for worktrees)}"
PREFIX="${MULTI_JIRA_WORKTREE_PREFIX:-wt-}"
KEY="${1:?Usage: create-worktree.sh <JIRA-KEY> <branch-name> [base-branch]}"
BRANCH="${2:?Missing branch name}"
BASE_BRANCH="${3:-master}"
WORKTREE_DIR="${WORKTREE_BASE}/${PREFIX}${KEY}"
cd "$REPO_DIR"

echo "=== Creating Worktree for $KEY ==="
if [ -d "$WORKTREE_DIR" ]; then
    echo "WARNING: Removing stale worktree..."
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR"
fi

CURRENT_BRANCH=$(git branch --show-current)
[ "$CURRENT_BRANCH" != "$BRANCH" ] && git branch -D "$BRANCH" 2>/dev/null || true

git fetch origin "$BASE_BRANCH" 2>/dev/null || true
git worktree add -b "$BRANCH" "$WORKTREE_DIR" "origin/$BASE_BRANCH" 2>/dev/null \
    || git worktree add -b "$BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH"

echo "Worktree: $WORKTREE_DIR | Branch: $BRANCH"
echo "$WORKTREE_DIR"
