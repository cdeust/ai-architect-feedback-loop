#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage6-prd-review.sh — Stage 6: PRD Review (Semantic Quality Gate)
# ============================================================================
#
# Reviews the PRD from Stage 5 for completeness, consistency, and
# actionability against the integration plan. Separate from Stage 5's
# structural validation (validate_prd_output.py) — this is a deeper
# semantic review using AI.
#
# Usage:
#   scripts/stage6-prd-review.sh \
#       --run-dir runs/TIMESTAMP \
#       --builder-dir /path/to/target-product \
#       --config config/thresholds.json \
#       --finding-id tv-001 \
#       --output runs/TIMESTAMP \
#       [--timeout 600]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage6_prd_review"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# POSIX-compatible timeout
# ---------------------------------------------------------------------------

run_with_timeout() {
    local secs="$1"; local outfile="$2"; shift 2
    "$@" > "$outfile" 2>/dev/null &
    local cmd_pid=$!
    ( sleep "$secs" && kill "$cmd_pid" 2>/dev/null ) &
    local watcher_pid=$!
    wait "$cmd_pid" 2>/dev/null
    local exit_code=$?
    kill "$watcher_pid" 2>/dev/null
    wait "$watcher_pid" 2>/dev/null
    return $exit_code
}

# Source shared AI invocation helper
source "$SCRIPT_DIR/ai_invoke.sh"

# Source artifact path helpers
source "$SCRIPT_DIR/artifact_paths.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

RUN_DIR=""
BUILDER_DIR=""
CONFIG_PATH=""
FINDING_ID=""
OUTPUT_DIR=""
TIMEOUT=600

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
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --finding-id)
            FINDING_ID="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required args
for arg_name in RUN_DIR BUILDER_DIR FINDING_ID OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -d "$RUN_DIR" ]]; then
    log "ERROR" "Run directory not found: $RUN_DIR"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Temp directory with cleanup
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log "INFO" "Stage 6 started — PRD Review"
log "INFO" "Finding: $FINDING_ID"

# ---------------------------------------------------------------------------
# Read PRD from Stage 5 output
# ---------------------------------------------------------------------------

PRD_DIR=$(artifact_prd_dir "$RUN_DIR" "$FINDING_ID")
PRD_PATH="$PRD_DIR/prd.md"

if [[ ! -f "$PRD_PATH" ]]; then
    log "ERROR" "PRD not found: $PRD_PATH"
    exit 1
fi

PRD_CONTENT=$(cat "$PRD_PATH")

# ---------------------------------------------------------------------------
# Read integration plan from Stage 3
# ---------------------------------------------------------------------------

INTEGRATION_PLAN_PATH=$(artifact_integration "$RUN_DIR" "$FINDING_ID")

if [[ ! -f "$INTEGRATION_PLAN_PATH" ]]; then
    log "ERROR" "Integration plan not found: $INTEGRATION_PLAN_PATH"
    exit 1
fi

INTEGRATION_PLAN=$(cat "$INTEGRATION_PLAN_PATH")

# ---------------------------------------------------------------------------
# Assemble review prompt
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE="$SCRIPT_DIR/../prompts/prd_review.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

echo "$PRD_CONTENT" > "$TMP_DIR/prd_content.txt"
echo "$INTEGRATION_PLAN" > "$TMP_DIR/integration_plan.txt"

python3 - "$PROMPT_TEMPLATE" "$TMP_DIR/prd_content.txt" \
    "$TMP_DIR/integration_plan.txt" "$FINDING_ID" \
    "$TMP_DIR/prompt.md" <<'PYEOF'
import sys

template_path, prd_path, plan_path, finding_id, output_path = sys.argv[1:6]

with open(template_path) as f:
    template = f.read()
with open(prd_path) as f:
    prd = f.read()
with open(plan_path) as f:
    plan = f.read()

result = template
result = result.replace("{{UPGRADE_PRD}}", prd)
result = result.replace("{{INTEGRATION_PLAN}}", plan)
result = result.replace("{{FINDING_ID}}", finding_id)

with open(output_path, "w") as f:
    f.write(result)
PYEOF

log "INFO" "Review prompt assembled"

# ---------------------------------------------------------------------------
# Invoke Claude Code CLI
# ---------------------------------------------------------------------------

RAW_OUTPUT="$TMP_DIR/raw_review.txt"
CLAUDE_EXIT=0

cd "$BUILDER_DIR"
ai_invoke "$TMP_DIR/prompt.md" "$RAW_OUTPUT" "stage6" "$FINDING_ID" \
    --max-turns 5 \
    || CLAUDE_EXIT=$?

if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
    log "INFO" "Session mode: prompt written, awaiting response"
    exit 42
elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    log "ERROR" "AI invocation failed (exit=$CLAUDE_EXIT)"
    REVIEW_OUTPUT=$(artifact_review6 "$OUTPUT_DIR" "$FINDING_ID")
    python3 -c "
import json
from datetime import datetime, timezone
result = {
    'stage': 'prd_review',
    'finding_id': '$FINDING_ID',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'result': 'FAIL',
    'reason': 'AI invocation failed (exit=$CLAUDE_EXIT)',
    'checks': []
}
with open('$REVIEW_OUTPUT', 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')
"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse review result
# ---------------------------------------------------------------------------

REVIEW_OUTPUT=$(artifact_review6 "$OUTPUT_DIR" "$FINDING_ID")

python3 - "$RAW_OUTPUT" "$REVIEW_OUTPUT" "$FINDING_ID" <<'PYEOF'
import json, re, sys
from datetime import datetime, timezone

raw_path, output_path, finding_id = sys.argv[1:4]

with open(raw_path) as f:
    text = f.read()

result = None

# Find JSON with "result" key
brace_depth = 0
start_idx = None
candidates = []
for i, ch in enumerate(text):
    if ch == '{':
        if brace_depth == 0:
            start_idx = i
        brace_depth += 1
    elif ch == '}':
        brace_depth -= 1
        if brace_depth == 0 and start_idx is not None:
            candidate = text[start_idx:i+1]
            if '"result"' in candidate:
                candidates.append(candidate)
            start_idx = None

for candidate in reversed(candidates):
    try:
        parsed = json.loads(candidate)
        if "result" in parsed:
            result = parsed
            break
    except json.JSONDecodeError:
        continue

if result is None:
    result = {
        "result": "FAIL",
        "reason": "Could not parse review output",
        "checks": [],
    }

output = {
    "stage": "prd_review",
    "finding_id": finding_id,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "result": result.get("result", "FAIL"),
    "reason": result.get("reason", ""),
    "checks": result.get("checks", []),
    "feedback": result.get("feedback", ""),
}

with open(output_path, 'w') as f:
    json.dump(output, f, indent=2)
    f.write('\n')
PYEOF

REVIEW_RESULT=$(python3 -c "import json; print(json.load(open('$REVIEW_OUTPUT'))['result'])")

log "INFO" "Stage 6 completed — result: $REVIEW_RESULT"
log "INFO" "Report written to $REVIEW_OUTPUT"

if [[ "$REVIEW_RESULT" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
