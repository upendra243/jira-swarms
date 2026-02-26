#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "SKIP: Telegram not configured."; exit 0
fi

if [ $# -eq 1 ] && [ ! -f "$1" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" -d "parse_mode=Markdown" \
        --data-urlencode "text=$1" | tail -1 | grep -q "200" \
        && echo "Sent." || echo "Failed."
    exit 0
fi

RESULTS_FILE="${1:?Usage: batch-notify-telegram.sh <results-json | message>}"
TOTAL=$(jq '.tickets | length' "$RESULTS_FILE")
SUCCESS=$(jq '[.tickets[] | select(.status == "success")] | length' "$RESULTS_FILE")
FAILED=$(jq '[.tickets[] | select(.status == "failed")] | length' "$RESULTS_FILE")

TICKET_LINES=$(jq -r '.tickets[] |
    if .status == "success" then "*\(.key)*: \(.summary) - PR: \(.pr_url // "N/A")"
    elif .status == "failed" then "*\(.key)*: \(.summary) - Error: \(.error // "Unknown")"
    else "*\(.key)*: \(.summary) - \(.reason // "Partial")"
    end' "$RESULTS_FILE")

MESSAGE="jira-swarms complete: ${SUCCESS}/${TOTAL} succeeded

${TICKET_LINES}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" -d "parse_mode=Markdown" \
    --data-urlencode "text=${MESSAGE}" | grep -q '"ok":true' \
    && echo "Batch notification sent." || echo "WARNING: Notification failed."
