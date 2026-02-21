#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage10-pull-request.sh — Stage 10: Pull Request Creation + Staging Sync
# ============================================================================
#
# Creates a GitHub PR on the product repo with a structured description
# assembled from all pipeline stage outputs, then runs staging sync.
#
# Usage:
#   scripts/stage10-pull-request.sh \
#       --run-dir runs/TIMESTAMP \
#       --builder-dir /path/to/target-product \
#       --engine-graph config/engine_graph.json \
#       --finding-id tv-001 \
#       --branch pipeline/improvement-tv-001 \
#       --output runs/TIMESTAMP
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage10_pull_request"

# Resolve base branch from project config
BASE_BRANCH="main"
PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
if [[ -f "$PROJECT_CONFIG" ]]; then
    BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('base_branch', 'main'))" 2>/dev/null || echo "main")
fi

# Read pipeline preferences (for PR formatting)
_PREFS_FILE="$SCRIPT_DIR/../config/pipeline_preferences.json"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

RUN_DIR=""
BUILDER_DIR=""
ENGINE_GRAPH=""
FINDING_ID=""
BRANCH=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir)
            RUN_DIR="$2"
            shift 2
            ;;
        --builder-dir)
            BUILDER_DIR="$2"
            shift 2
            ;;
        --engine-graph)
            ENGINE_GRAPH="$2"
            shift 2
            ;;
        --finding-id)
            FINDING_ID="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required args
for arg_name in RUN_DIR BUILDER_DIR FINDING_ID BRANCH OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -d "$BUILDER_DIR" ]]; then
    log "ERROR" "Builder directory not found: $BUILDER_DIR"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# Check gh CLI
if ! command -v gh &> /dev/null; then
    log "ERROR" "gh CLI not found in PATH"
    exit 1
fi

# Check gh authentication
if ! gh auth status > /dev/null 2>&1; then
    log "ERROR" "gh CLI not authenticated — run 'gh auth login' first"
    exit 1
fi

# Check branch exists
BRANCH_EXISTS=$(git -C "$BUILDER_DIR" branch --list "$BRANCH" 2>/dev/null | tr -d ' ')
if [[ -z "$BRANCH_EXISTS" ]]; then
    log "ERROR" "Branch not found: $BRANCH"
    exit 1
fi

log "INFO" "Stage 10 started — Pull Request Creation"
log "INFO" "Finding: $FINDING_ID, Branch: $BRANCH"

# ---------------------------------------------------------------------------
# Temp directory with cleanup
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Read affected engines from integration plan for labels
# ---------------------------------------------------------------------------

INTEGRATION_PLAN="$RUN_DIR/integration_plan_${FINDING_ID}.json"
ENGINE_NAMES=""
if [[ -f "$INTEGRATION_PLAN" ]]; then
    ENGINE_NAMES=$(python3 -c "import json; print(','.join(json.load(open('$INTEGRATION_PLAN')).get('affected_engines', [])))" 2>/dev/null || echo "")
fi

if [[ -z "$ENGINE_NAMES" && -n "${ENGINE_GRAPH:-}" && -f "$ENGINE_GRAPH" ]]; then
    # Fallback: try to extract from engine_graph
    ENGINE_NAMES="unknown"
fi

log "INFO" "Affected engines: ${ENGINE_NAMES:-none}"

# ---------------------------------------------------------------------------
# Compose PR description
# ---------------------------------------------------------------------------

PR_BODY_FILE="$TMP_DIR/pr_body.md"

python3 "$SCRIPT_DIR/compose_pr.py" \
    --run-dir "$RUN_DIR" \
    --finding-id "$FINDING_ID" \
    --engine-graph "${ENGINE_GRAPH:-}" \
    --output "$PR_BODY_FILE" 2>&1 || {
    log "ERROR" "Failed to compose PR description"
    exit 1
}

log "INFO" "PR description composed"

# ---------------------------------------------------------------------------
# Build PR title and labels
# ---------------------------------------------------------------------------

# Build PR title from preferences or defaults
ENGINE_DISPLAY=$(echo "$ENGINE_NAMES" | tr ',' ', ')
if [[ -f "$_PREFS_FILE" ]]; then
    TITLE=$(python3 -c "
import json
p = json.load(open('$_PREFS_FILE'))
t = p['pr']['title']
print(t.format(engines='${ENGINE_DISPLAY:-unknown}', finding_id='$FINDING_ID'))
" 2>/dev/null || echo "pipeline: improve ${ENGINE_DISPLAY:-unknown} — ${FINDING_ID}")
    LABELS=$(python3 -c "
import json
p = json.load(open('$_PREFS_FILE'))
labels = list(p['pr']['labels'])
if p['pr'].get('label_engines', True) and '$ENGINE_NAMES':
    labels.extend('$ENGINE_NAMES'.split(','))
print(','.join(labels))
" 2>/dev/null || echo "pipeline-generated,improvement")
else
    TITLE="pipeline: improve ${ENGINE_DISPLAY:-unknown} — ${FINDING_ID}"
    LABELS="pipeline-generated,improvement"
    if [[ -n "$ENGINE_NAMES" ]]; then
        LABELS="${LABELS},${ENGINE_NAMES}"
    fi
fi

log "INFO" "PR title: $TITLE"
log "INFO" "PR labels: $LABELS"

# ---------------------------------------------------------------------------
# Push branch to remote
# ---------------------------------------------------------------------------

GIT_REMOTE="origin"
if [[ -f "$_PREFS_FILE" ]]; then
    GIT_REMOTE=$(python3 -c "import json; print(json.load(open('$_PREFS_FILE'))['git'].get('remote', 'origin'))" 2>/dev/null || echo "origin")
fi

log "INFO" "Pushing branch $BRANCH to remote ($GIT_REMOTE)..."

PUSH_EXIT=0
git -C "$BUILDER_DIR" push -u "$GIT_REMOTE" "$BRANCH" 2>&1 || PUSH_EXIT=$?

if [[ "$PUSH_EXIT" -ne 0 ]]; then
    log "ERROR" "Failed to push branch $BRANCH"
    exit 1
fi

log "INFO" "Branch pushed to remote"

# ---------------------------------------------------------------------------
# Create PR
# ---------------------------------------------------------------------------

REPO_URL=$(git -C "$BUILDER_DIR" remote get-url origin 2>/dev/null | sed 's/\.git$//' || echo "")

if [[ -z "$REPO_URL" ]]; then
    log "ERROR" "Could not determine repo URL from remote"
    exit 1
fi

log "INFO" "Creating PR on $REPO_URL..."

PR_URL=""
PR_URL=$(gh pr create \
    --repo "$REPO_URL" \
    --base "$BASE_BRANCH" \
    --head "$BRANCH" \
    --title "$TITLE" \
    --body "$(cat "$PR_BODY_FILE")" \
    --label "$LABELS" 2>&1) || {
    log "ERROR" "gh pr create failed: $PR_URL"
    exit 1
}

log "INFO" "PR created: $PR_URL"

# ---------------------------------------------------------------------------
# Run staging sync (non-blocking — PR already created)
# ---------------------------------------------------------------------------

SYNC_RESULT="SKIPPED"

if make -C "$BUILDER_DIR" -n sync-staging > /dev/null 2>&1; then
    log "INFO" "Running make sync-staging..."
    if make -C "$BUILDER_DIR" sync-staging 2>&1; then
        SYNC_RESULT="PASS"
        log "INFO" "make sync-staging succeeded"
    else
        SYNC_RESULT="FAIL"
        log "WARN" "make sync-staging failed — PR already created, continuing"
    fi
else
    log "INFO" "No sync-staging target found, skipping"
fi

# ---------------------------------------------------------------------------
# Write stage10_summary.json
# ---------------------------------------------------------------------------

# Convert comma-separated labels to JSON array
LABELS_JSON=$(python3 -c "import json; print(json.dumps('$LABELS'.split(',')))")

python3 -c "
import json
from datetime import datetime, timezone

summary = {
    'stage': 'pull_request',
    'finding_id': '$FINDING_ID',
    'result': 'CREATED',
    'pr_url': '$PR_URL',
    'branch': '$BRANCH',
    'labels': $LABELS_JSON,
    'sync_staging_result': '$SYNC_RESULT',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
}

with open('$OUTPUT_DIR/stage10_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
"

log "INFO" "Stage 10 completed — PR: $PR_URL"
log "INFO" "Summary written to $OUTPUT_DIR/stage10_summary.json"

exit 0
