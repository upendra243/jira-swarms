#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "SKIP: Telegram not configured."; exit 0
fi
# chat_id must be numeric (user: positive, group: often negative). Usernames like @bot are not valid.
if [[ ! "${TELEGRAM_CHAT_ID}" =~ ^-?[0-9]+$ ]]; then
    echo "ERROR: TELEGRAM_CHAT_ID must be a numeric chat ID (e.g. from @userinfobot or getUpdates), not a username. Got: ${TELEGRAM_CHAT_ID}"
    exit 1
fi

if [ $# -eq 1 ] && [ ! -f "$1" ]; then
    RESP=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" -d "parse_mode=Markdown" \
        --data-urlencode "text=$1")
    if echo "$RESP" | grep -q '"ok":true'; then
        echo "Sent."
    else
        echo "Failed."
        echo "Telegram API response: $RESP"
    fi
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

RESP=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" -d "parse_mode=Markdown" \
    --data-urlencode "text=${MESSAGE}")
if echo "$RESP" | grep -q '"ok":true'; then
    echo "Batch notification sent."
else
    echo "WARNING: Notification failed."
    echo "Telegram API response: $RESP"
fi
