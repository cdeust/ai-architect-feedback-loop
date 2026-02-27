#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage7-reviewer.sh — Post-worker drift check (CLI mode)
# ============================================================================
#
# Reviews the combined diff from all workers against the full PRD to detect
# drift, missing requirements, or cross-module inconsistencies.
#
# Usage:
#   scripts/stage7-reviewer.sh \
#       --prd runs/TS/findings/FID/stage5-prd/prd.md \
#       --integration-plan runs/TS/findings/FID/stage3-integration.json \
#       --builder-dir /path/to/target-product \
#       --branch pipeline/improvement-tv-001 \
#       --base-branch main \
#       --output runs/TS/findings/FID/reviewer_result.json \
#       [--timeout 300]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage7_reviewer"

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

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

PRD_PATH=""
INTEGRATION_PLAN=""
BUILDER_DIR=""
BRANCH=""
BASE_BRANCH="main"
OUTPUT_FILE=""
TIMEOUT=300

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prd) PRD_PATH="$2"; shift 2;;
        --integration-plan) INTEGRATION_PLAN="$2"; shift 2;;
        --builder-dir) BUILDER_DIR="$2"; shift 2;;
        --branch) BRANCH="$2"; shift 2;;
        --base-branch) BASE_BRANCH="$2"; shift 2;;
        --output) OUTPUT_FILE="$2"; shift 2;;
        --timeout) TIMEOUT="$2"; shift 2;;
        *) log "ERROR" "Unknown argument: $1"; exit 1;;
    esac
done

for arg_name in PRD_PATH INTEGRATION_PLAN BUILDER_DIR BRANCH OUTPUT_FILE; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Generate diff and assemble prompt
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Get combined diff
GIT_DIFF=$(git -C "$BUILDER_DIR" diff "${BASE_BRANCH}..${BRANCH}" 2>/dev/null || echo "(no diff)")
echo "$GIT_DIFF" > "$TMP_DIR/diff.txt"

# Extract cross-engine touchpoints
TOUCHPOINTS=$(python3 -c "
import json
plan = json.load(open('$INTEGRATION_PLAN'))
tps = plan.get('cross_engine_touchpoints', [])
lines = []
for tp in tps:
    lines.append(f\"- {tp.get('from','?')} -> {tp.get('to','?')} via {tp.get('via','?')}: {tp.get('description','')}\")
print('\n'.join(lines) if lines else '(none)')
" 2>/dev/null || echo "(could not parse)")

FINDING_ID=$(python3 -c "import json; print(json.load(open('$INTEGRATION_PLAN')).get('finding_id', 'unknown'))" 2>/dev/null || echo "unknown")

# Assemble prompt
PROMPT_TEMPLATE="$SCRIPT_DIR/../prompts/reviewer.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
    log "ERROR" "Reviewer prompt template not found"
    exit 1
fi

python3 - "$PROMPT_TEMPLATE" "$PRD_PATH" "$TMP_DIR/diff.txt" \
    "$INTEGRATION_PLAN" "$TMP_DIR/prompt.md" <<PYEOF
import sys

template_path, prd_path, diff_path, plan_path, output_path = sys.argv[1:6]

with open(template_path) as f:
    template = f.read()
with open(prd_path) as f:
    prd = f.read()
with open(diff_path) as f:
    diff = f.read()
with open(plan_path) as f:
    plan = f.read()

result = template
result = result.replace("{{UPGRADE_PRD}}", prd)
result = result.replace("{{GIT_DIFF}}", diff[:50000])  # Limit diff size
result = result.replace("{{INTEGRATION_PLAN}}", plan)
result = result.replace("{{CROSS_ENGINE_TOUCHPOINTS}}", """$TOUCHPOINTS""")

with open(output_path, "w") as f:
    f.write(result)
PYEOF

log "INFO" "Reviewer prompt assembled for $FINDING_ID"

# ---------------------------------------------------------------------------
# Invoke Claude Code CLI (Opus for reviewing)
# ---------------------------------------------------------------------------

RAW_OUTPUT="$TMP_DIR/raw_review.txt"
CLAUDE_EXIT=0

cd "$BUILDER_DIR"
AI_TIMEOUT="$TIMEOUT" ai_invoke "$TMP_DIR/prompt.md" "$RAW_OUTPUT" "stage7" "$FINDING_ID" \
    --model opus --max-turns 15 \
    || CLAUDE_EXIT=$?

if [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    log "ERROR" "Reviewer failed (exit=$CLAUDE_EXIT)"
    python3 -c "
import json
result = {'overall_result': 'FAIL', 'confidence': 0, 'reason': 'Reviewer invocation failed'}
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse review result
# ---------------------------------------------------------------------------

python3 - "$RAW_OUTPUT" "$OUTPUT_FILE" <<'PYEOF'
import json, re, sys

raw_path, output_path = sys.argv[1:3]

with open(raw_path) as f:
    text = f.read()

result = None

# Find JSON with overall_result
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
            if '"overall_result"' in candidate:
                candidates.append(candidate)
            start_idx = None

for candidate in reversed(candidates):
    try:
        parsed = json.loads(candidate)
        if "overall_result" in parsed:
            result = parsed
            break
    except json.JSONDecodeError:
        continue

if result is None:
    result = {
        "overall_result": "FAIL",
        "confidence": 0,
        "reason": "Could not parse reviewer output",
    }

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')
PYEOF

REVIEW_RESULT=$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE'))['overall_result'])")
log "INFO" "Reviewer completed — result: $REVIEW_RESULT"

if [[ "$REVIEW_RESULT" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
