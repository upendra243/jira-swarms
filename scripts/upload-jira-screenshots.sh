#!/usr/bin/env bash
set -euo pipefail
# Requires: JIRA_API_TOKEN, JIRA_USER, JIRA_BASE_URL (set in env or .env). See README.
#
# Upload screenshots from an artifacts directory to a Jira issue and post a dev comment.
# Usage: upload-jira-screenshots.sh <JIRA-KEY> <ARTIFACTS-DIR> <COMMENT-FILE>

KEY="${1:?Usage: upload-jira-screenshots.sh <JIRA-KEY> <ARTIFACTS-DIR> <COMMENT-FILE>}"
ARTIFACTS_DIR="${2:?Missing artifacts directory}"
COMMENT_FILE="${3:?Missing comment file path}"

if [[ -z "${JIRA_API_TOKEN:-}" ]]; then
    echo "ERROR: JIRA_API_TOKEN must be set."
    exit 1
fi
if [[ -z "${JIRA_USER:-}" ]]; then
    echo "ERROR: JIRA_USER must be set (e.g. your Jira email)."
    exit 1
fi
if [[ -z "${JIRA_BASE_URL:-}" ]]; then
    echo "ERROR: JIRA_BASE_URL must be set (e.g. https://your-domain.atlassian.net)."
    exit 1
fi

echo "=== Uploading Screenshots for $KEY ==="

UPLOADED=0
SKIPPED=0
FAILED=0
if [ -d "$ARTIFACTS_DIR" ]; then
    for screenshot in "$ARTIFACTS_DIR"/*.png; do
        [ -f "$screenshot" ] || continue
        FILENAME=$(basename "$screenshot")
        if echo "$FILENAME" | grep -qiE "^(login-|error-)"; then
            echo "  Skipping (not a test case): $FILENAME"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        echo "  Uploading: $FILENAME"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$JIRA_USER:$JIRA_API_TOKEN" \
            -X POST \
            -H "X-Atlassian-Token: no-check" \
            -F "file=@$screenshot" \
            "$JIRA_BASE_URL/rest/api/2/issue/$KEY/attachments")
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo "    OK Uploaded ($HTTP_CODE)"
            UPLOADED=$((UPLOADED + 1))
        else
            echo "    Failed ($HTTP_CODE)"
            FAILED=$((FAILED + 1))
        fi
    done
else
    echo "  No artifacts directory found at: $ARTIFACTS_DIR"
fi

echo "  Screenshots: $UPLOADED uploaded, $SKIPPED skipped, $FAILED failed"

if [ -f "$COMMENT_FILE" ]; then
    OLD_COMMENT_ID=$(jira issue view "$KEY" --raw 2>/dev/null | jq -r \
        '[.fields.comment.comments[] | select(.body | .. | .text? // empty | contains("Browser Test Results")) | .id] | first // empty' 2>/dev/null || true)
    if [ -n "$OLD_COMMENT_ID" ] && [ "$OLD_COMMENT_ID" != "null" ]; then
        echo "  Updating existing Browser Test Results comment (ID: $OLD_COMMENT_ID)..."
        COMMENT_BODY=$(cat "$COMMENT_FILE")
        COMMENT_JSON=$(python3 -c "
import json, sys
text = sys.stdin.read()
paragraphs = []
for line in text.split('\n'):
    if line.strip():
        paragraphs.append({'type': 'paragraph', 'content': [{'type': 'text', 'text': line}]})
    else:
        paragraphs.append({'type': 'paragraph', 'content': []})
print(json.dumps({'body': {'type': 'doc', 'version': 1, 'content': paragraphs}}))
" <<< "$COMMENT_BODY")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$JIRA_USER:$JIRA_API_TOKEN" \
            -X PUT \
            -H "Content-Type: application/json" \
            -d "$COMMENT_JSON" \
            "$JIRA_BASE_URL/rest/api/3/issue/$KEY/comment/$OLD_COMMENT_ID")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  Comment updated"
        else
            echo "  Update failed ($HTTP_CODE), posting as new comment..."
            jira issue comment add "$KEY" --no-input -T "$COMMENT_FILE"
        fi
    else
        echo "  Posting development comment..."
        jira issue comment add "$KEY" --no-input -T "$COMMENT_FILE"
    fi
else
    echo "  No comment file found at: $COMMENT_FILE"
fi

echo "=== Done: $KEY ==="
