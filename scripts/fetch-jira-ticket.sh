#!/usr/bin/env bash
set -euo pipefail
KEY="${1:?Usage: fetch-jira-ticket.sh <JIRA-KEY>}"
echo "=== Fetching $KEY from Jira ==="
echo ""
echo "--- Human-readable ---"
jira issue view "$KEY"
echo ""
echo "--- Structured JSON ---"
jira issue view "$KEY" --raw | jq '{
  key: .key,
  summary: .fields.summary,
  status: .fields.status.name,
  type: .fields.issuetype.name,
  priority: .fields.priority.name,
  assignee: (if .fields.assignee then .fields.assignee.displayName else "Unassigned" end),
  reporter: (if .fields.reporter then .fields.reporter.displayName else "Unknown" end),
  labels: .fields.labels,
  sprint: (if .fields.customfield_10016 then [.fields.customfield_10016[].name] else [] end),
  story_points: .fields.customfield_10021,
  qa_status: (if .fields.customfield_10400 then .fields.customfield_10400.value else null end),
  description_raw: .fields.description
}'
echo ""
echo "=== Done ==="
