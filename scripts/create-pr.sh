#!/usr/bin/env bash
set -euo pipefail

# Generic PR creator that dispatches to Bitbucket or GitHub.
# Prefers explicit PR_PROVIDER, then env hints, then git remote URL.
#
# Usage:
#   create-pr.sh "<title>" "<description>" "<source-branch>" "<dest-branch>"

TITLE="${1:?Usage: create-pr.sh <title> <description> <source-branch> <dest-branch>}"
DESCRIPTION="${2:?Missing PR description}"
SOURCE_BRANCH="${3:?Missing source branch name}"
DEST_BRANCH="${4:-master}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_provider() {
  local provider="${PR_PROVIDER:-}"

  if [[ -n "$provider" ]]; then
    # Normalise to lowercase without relying on Bash 4+.
    provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"
    echo "$provider"
    return 0
  fi

  # Heuristics from env vars.
  if [[ -n "${BB_REPO_SLUG:-}" || -n "${BB_USER:-}" || -n "${BB_API_TOKEN:-}" ]]; then
    echo "bitbucket"
    return 0
  fi
  if [[ -n "${GH_REPO_SLUG:-}" || -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    echo "github"
    return 0
  fi

  # Fallback: infer from git remote origin.
  local repo_dir="${JIRA_GIT_REPO_DIR:-.}"
  local remote_url
  remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "")"

  if [[ "$remote_url" == *"bitbucket.org"* ]]; then
    echo "bitbucket"
    return 0
  fi
  if [[ "$remote_url" == *"github.com"* ]]; then
    echo "github"
    return 0
  fi

  echo ""
  return 1
}

PROVIDER="$(detect_provider || true)"

if [[ -z "$PROVIDER" ]]; then
  cat >&2 <<EOF
ERROR: Could not determine PR provider.

Set PR_PROVIDER=bitbucket or PR_PROVIDER=github, or provide provider-specific
env vars (Bitbucket: BB_USER/BB_API_TOKEN/BB_REPO_SLUG; GitHub: GH_TOKEN or
GITHUB_TOKEN and GH_REPO_SLUG), or configure a git remote 'origin' that
points to bitbucket.org or github.com.
EOF
  exit 1
fi

case "$PROVIDER" in
  bitbucket)
    exec "${SCRIPT_DIR}/create-bb-pr.sh" "$TITLE" "$DESCRIPTION" "$SOURCE_BRANCH" "$DEST_BRANCH"
    ;;
  github)
    exec "${SCRIPT_DIR}/create-gh-pr.sh" "$TITLE" "$DESCRIPTION" "$SOURCE_BRANCH" "$DEST_BRANCH"
    ;;
  *)
    echo "ERROR: Unsupported PR provider '$PROVIDER' (expected 'bitbucket' or 'github')." >&2
    exit 1
    ;;
esac

