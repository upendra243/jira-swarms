#!/usr/bin/env bash
set -euo pipefail
# Requires: JIRA_GIT_REPO_DIR. Optional: JIRA_WORKER_IMAGE (default: multi-jira-worker:latest), JIRA_BASE_IMAGE_CANDIDATES (comma-separated)
REPO_DIR="${JIRA_GIT_REPO_DIR:?Set JIRA_GIT_REPO_DIR}"
IMAGE_NAME="${JIRA_WORKER_IMAGE:-multi-jira-worker:latest}"
# If IMAGE_NAME has no tag, append :latest
[[ "$IMAGE_NAME" == *:* ]] || IMAGE_NAME="${IMAGE_NAME}:latest"
FULL_IMAGE="$IMAGE_NAME"
cd "$REPO_DIR"
echo "=== jira-swarms Worker Image Setup ==="

EXISTING=$(docker images -q "$FULL_IMAGE" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    echo "Image '$FULL_IMAGE' already exists. Reusing."
    echo "$FULL_IMAGE"; exit 0
fi

# Try user-provided candidates, then common names
CANDIDATES="${JIRA_BASE_IMAGE_CANDIDATES:-}"
[ -n "$CANDIDATES" ] || CANDIDATES="app:latest app_main:latest django:latest"
for CANDIDATE in $(echo "$CANDIDATES" | tr ',' ' '); do
    CANDIDATE=$(echo "$CANDIDATE" | xargs)
    [ -n "$CANDIDATE" ] || continue
    if docker images -q "$CANDIDATE" 2>/dev/null | grep -q .; then
        echo "Found '$CANDIDATE'. Tagging as '$FULL_IMAGE'."
        docker tag "$CANDIDATE" "$FULL_IMAGE"
        echo "$FULL_IMAGE"; exit 0
    fi
done

# Build from Dockerfile if present
DOCKERFILE="${JIRA_DOCKERFILE:-docker/Dockerfile.django}"
if [ -f "$REPO_DIR/$DOCKERFILE" ]; then
    echo "Building from $DOCKERFILE..."
    docker build -t "$FULL_IMAGE" -f "$DOCKERFILE" . 2>&1
else
    echo "ERROR: No base image found and no Dockerfile at $DOCKERFILE. Set JIRA_BASE_IMAGE_CANDIDATES or add a Dockerfile."
    exit 1
fi
echo "$FULL_IMAGE"
