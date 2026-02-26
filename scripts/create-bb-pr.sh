#!/usr/bin/env bash
set -euo pipefail
# Bitbucket PR helper; usually called via create-pr.sh.
# Requires: BB_USER, BB_API_TOKEN, BB_REPO_SLUG (e.g. owner/repo).
TITLE="${1:?Usage: create-bb-pr.sh <title> <description> <source-branch> <dest-branch>}"
DESCRIPTION="${2:?Missing PR description}"
SOURCE_BRANCH="${3:?Missing source branch name}"
DEST_BRANCH="${4:-master}"
REPO_SLUG="${BB_REPO_SLUG:?Set BB_REPO_SLUG (e.g. owner/repo)}"
API_URL="https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests"

if [[ -z "${BB_USER:-}" || -z "${BB_API_TOKEN:-}" ]]; then
  echo "ERROR: BB_USER and BB_API_TOKEN must be set."
  exit 1
fi

DESCRIPTION_ESCAPED=$(echo "$DESCRIPTION" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
PAYLOAD=$(cat <<EOF
{
  "title": $(echo "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  "description": $DESCRIPTION_ESCAPED,
  "source": { "branch": { "name": "$SOURCE_BRANCH" } },
  "destination": { "branch": { "name": "$DEST_BRANCH" } },
  "close_source_branch": true
}
EOF
)

echo "=== Creating Bitbucket PR ==="
echo "Title:       $TITLE"
echo "Source:      $SOURCE_BRANCH"
echo "Destination: $DEST_BRANCH"

RESPONSE=$(curl -s -w "\n%{http_code}" -u "$BB_USER:$BB_API_TOKEN" -X POST -H "Content-Type: application/json" "$API_URL" -d "$PAYLOAD")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "201" ]]; then
  PR_URL=$(echo "$BODY" | jq -r '.links.html.href')
  PR_ID=$(echo "$BODY" | jq -r '.id')
  echo "PR created successfully!"
  echo "PR #$PR_ID: $PR_URL"
else
  echo "ERROR: Failed to create PR (HTTP $HTTP_CODE)"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  exit 1
fi
