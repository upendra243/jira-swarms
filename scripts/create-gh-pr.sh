#!/usr/bin/env bash
set -euo pipefail

# Create a GitHub pull request.
# Requires:
#   - GH_TOKEN or GITHUB_TOKEN
#   - GH_REPO_SLUG (owner/repo), or detectable from git remote "origin"
#
# Usage:
#   create-gh-pr.sh "<title>" "<description>" "<source-branch>" "<dest-branch>"

TITLE="${1:?Usage: create-gh-pr.sh <title> <description> <source-branch> <dest-branch>}"
DESCRIPTION="${2:?Missing PR description}"
SOURCE_BRANCH="${3:?Missing source branch name}"
DEST_BRANCH="${4:-master}"

REPO_SLUG="${GH_REPO_SLUG:-}"

if [[ -z "$REPO_SLUG" ]]; then
  REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
  if [[ "$REMOTE_URL" =~ github\.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
    REPO_SLUG="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    echo "ERROR: GH_REPO_SLUG must be set (owner/repo) or detectable from git remote 'origin'."
    exit 1
  fi
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: GH_TOKEN or GITHUB_TOKEN must be set."
  exit 1
fi

API_URL="https://api.github.com/repos/${REPO_SLUG}/pulls"

DESCRIPTION_ESCAPED="$(echo "$DESCRIPTION" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
TITLE_ESCAPED="$(echo "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"

PAYLOAD=$(cat <<EOF
{
  "title": $TITLE_ESCAPED,
  "body": $DESCRIPTION_ESCAPED,
  "head": "$SOURCE_BRANCH",
  "base": "$DEST_BRANCH"
}
EOF
)

echo "=== Creating GitHub PR ==="
echo "Repo:        $REPO_SLUG"
echo "Title:       $TITLE"
echo "Source:      $SOURCE_BRANCH"
echo "Destination: $DEST_BRANCH"

RESPONSE="$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -X POST "$API_URL" \
  -d "$PAYLOAD")"

HTTP_CODE="$(echo "$RESPONSE" | tail -1)"
BODY="$(echo "$RESPONSE" | sed '$d')"

if [[ "$HTTP_CODE" == "201" ]]; then
  PR_URL="$(echo "$BODY" | jq -r '.html_url')"
  PR_NUMBER="$(echo "$BODY" | jq -r '.number')"
  echo "PR created successfully!"
  echo "PR #$PR_NUMBER: $PR_URL"
else
  echo "ERROR: Failed to create GitHub PR (HTTP $HTTP_CODE)"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  exit 1
fi

