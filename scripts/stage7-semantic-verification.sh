#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage7-semantic-verification.sh — Stage 7: Independent Semantic Verification
# ============================================================================
#
# Runs an independent Claude Code CLI session to verify that the implementation
# (Stage 5) matches the PRD specification. Intentionally separate from the
# implementation session to prevent self-confirming bias.
#
# Usage:
#   scripts/stage7-semantic-verification.sh \
#       --run-dir runs/TIMESTAMP \
#       --builder-dir ../ai-architect-prd-builder \
#       --engine-graph config/engine_graph.json \
#       --config config/thresholds.json \
#       --patterns config/prohibited_patterns.txt \
#       --finding-id tv-001 \
#       --branch pipeline/improvement-tv-001 \
#       --output runs/TIMESTAMP \
#       [--timeout 900]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage7_semantic_verification"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# POSIX-compatible timeout (works on macOS and Linux without coreutils)
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

RUN_DIR=""
BUILDER_DIR=""
ENGINE_GRAPH=""
CONFIG_PATH=""
PATTERNS_FILE=""
FINDING_ID=""
BRANCH=""
OUTPUT_DIR=""
TIMEOUT=900

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
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --patterns)
            PATTERNS_FILE="$2"
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
for arg_name in RUN_DIR BUILDER_DIR ENGINE_GRAPH FINDING_ID BRANCH OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -d "$RUN_DIR" ]]; then
    log "ERROR" "Run directory not found: $RUN_DIR"
    exit 1
fi

if [[ ! -d "$BUILDER_DIR" ]]; then
    log "ERROR" "Builder directory not found: $BUILDER_DIR"
    exit 1
fi

if ! command -v claude &> /dev/null; then
    log "ERROR" "claude CLI not found in PATH"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Temp directory with cleanup
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
ORIGINAL_BRANCH=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "main")

cleanup() {
    # Return to original branch if needed
    local current_branch
    current_branch=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "")
    if [[ -n "$current_branch" && "$current_branch" != "$ORIGINAL_BRANCH" ]]; then
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log "INFO" "Stage 7 started — Semantic Verification"
log "INFO" "Finding: $FINDING_ID, Branch: $BRANCH"

# ---------------------------------------------------------------------------
# Generate git diff against main on the feature branch
# ---------------------------------------------------------------------------

GIT_DIFF=$(git -C "$BUILDER_DIR" diff "main..${BRANCH}" -- packages/ library/ 2>/dev/null || echo "")

if [[ -z "$GIT_DIFF" ]]; then
    log "WARN" "No diff found between main and $BRANCH"
    GIT_DIFF="(no changes detected)"
fi

log "INFO" "Git diff generated ($(echo "$GIT_DIFF" | wc -l | tr -d ' ') lines)"

# ---------------------------------------------------------------------------
# Read PRD from Stage 4 output
# ---------------------------------------------------------------------------

PRD_PATH="$RUN_DIR/prd_output_${FINDING_ID}/prd.md"
if [[ ! -f "$PRD_PATH" ]]; then
    log "ERROR" "PRD not found: $PRD_PATH"
    exit 1
fi
PRD_CONTENT=$(cat "$PRD_PATH")

# ---------------------------------------------------------------------------
# Read integration plan
# ---------------------------------------------------------------------------

INTEGRATION_PLAN_PATH="$RUN_DIR/integration_plan_${FINDING_ID}.json"
INTEGRATION_PLAN=""
CROSS_ENGINE_TOUCHPOINTS=""

if [[ -f "$INTEGRATION_PLAN_PATH" ]]; then
    INTEGRATION_PLAN=$(cat "$INTEGRATION_PLAN_PATH")

    # Format cross-engine touchpoints as a checklist
    CROSS_ENGINE_TOUCHPOINTS=$(python3 - "$INTEGRATION_PLAN_PATH" <<'PYEOF'
import json, sys
try:
    plan = json.load(open(sys.argv[1]))
    touchpoints = plan.get("cross_engine_touchpoints", [])
    lines = []
    for tp in touchpoints:
        fr = tp.get("from", "?")
        to = tp.get("to", "?")
        via = tp.get("via", tp.get("port", "?"))
        desc = tp.get("description", "")
        line = f"- [ ] {fr} -> {to} via {via}"
        if desc:
            line += f": {desc}"
        lines.append(line)
    if not lines:
        print("(no cross-engine touchpoints defined)")
    else:
        print("\n".join(lines))
except Exception:
    print("(could not parse cross-engine touchpoints)")
PYEOF
    )
else
    log "WARN" "Integration plan not found: $INTEGRATION_PLAN_PATH"
    INTEGRATION_PLAN="{}"
    CROSS_ENGINE_TOUCHPOINTS="(no integration plan available)"
fi

# ---------------------------------------------------------------------------
# Read prohibited patterns
# ---------------------------------------------------------------------------

ANTI_PATTERNS=""
if [[ -n "${PATTERNS_FILE:-}" && -f "$PATTERNS_FILE" ]]; then
    ANTI_PATTERNS=$(grep -v '^#' "$PATTERNS_FILE" | grep -v '^$' || echo "")
else
    ANTI_PATTERNS="(no prohibited patterns file available)"
fi

# ---------------------------------------------------------------------------
# Assemble prompt from template
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE="$SCRIPT_DIR/../prompts/semantic_verification.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

# Write context files for Python substitution
echo "$GIT_DIFF" > "$TMP_DIR/git_diff.txt"
echo "$PRD_CONTENT" > "$TMP_DIR/prd_content.txt"
echo "$INTEGRATION_PLAN" > "$TMP_DIR/integration_plan.txt"
echo "$CROSS_ENGINE_TOUCHPOINTS" > "$TMP_DIR/touchpoints.txt"
echo "$ANTI_PATTERNS" > "$TMP_DIR/anti_patterns.txt"

python3 - "$PROMPT_TEMPLATE" "$TMP_DIR/prd_content.txt" \
    "$TMP_DIR/git_diff.txt" "$TMP_DIR/integration_plan.txt" \
    "$TMP_DIR/touchpoints.txt" "$TMP_DIR/anti_patterns.txt" \
    "$FINDING_ID" "$TMP_DIR/prompt.md" <<'PYEOF'
import sys

(template_path, prd_path, diff_path, plan_path,
 touchpoints_path, patterns_path, finding_id, output_path) = sys.argv[1:9]

with open(template_path) as f:
    template = f.read()

def read_file(p):
    with open(p) as f:
        return f.read()

result = template
result = result.replace("{{UPGRADE_PRD}}", read_file(prd_path))
result = result.replace("{{GIT_DIFF}}", read_file(diff_path))
result = result.replace("{{INTEGRATION_PLAN}}", read_file(plan_path))
result = result.replace("{{CROSS_ENGINE_TOUCHPOINTS}}", read_file(touchpoints_path))
result = result.replace("{{ANTI_PATTERNS}}", read_file(patterns_path))
result = result.replace("{{FINDING_ID}}", finding_id)

with open(output_path, "w") as f:
    f.write(result)
PYEOF

log "INFO" "Prompt assembled ($(wc -l < "$TMP_DIR/prompt.md" | tr -d ' ') lines)"

# ---------------------------------------------------------------------------
# Invoke Claude Code CLI (independent session)
# ---------------------------------------------------------------------------

RAW_OUTPUT="$TMP_DIR/raw_verification.txt"
CLAUDE_EXIT=0

cd "$BUILDER_DIR"
ai_invoke "$TMP_DIR/prompt.md" "$RAW_OUTPUT" "stage7" "$FINDING_ID" \
    --max-turns 15 \
    || CLAUDE_EXIT=$?

if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
    log "INFO" "Session mode: prompt written, awaiting response"
    exit 42
elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    log "ERROR" "AI invocation failed (exit=$CLAUDE_EXIT)"
    # Write FAIL result
    python3 -c "
import json
from datetime import datetime, timezone
result = {
    'stage': 'semantic_verification',
    'finding_id': '$FINDING_ID',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'overall_result': 'FAIL',
    'confidence': 0,
    'prd_alignment_score': 0,
    'findings': [{'severity': 'CRITICAL', 'category': 'alignment', 'description': 'AI invocation failed', 'evidence': 'exit code $CLAUDE_EXIT'}],
    'cross_engine_verification': {'touchpoints_verified': 0, 'touchpoints_total': 0, 'result': 'FAIL'},
    'anti_patterns_detected': [],
    'requirements_traced': {'total': 0, 'matched': 0, 'missing': []}
}
with open('$OUTPUT_DIR/verification_stage7_${FINDING_ID}.json', 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')
"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse verification result JSON from Claude output
# ---------------------------------------------------------------------------

log "INFO" "Parsing verification result..."

python3 - "$RAW_OUTPUT" "$OUTPUT_DIR/verification_stage7_${FINDING_ID}.json" "$FINDING_ID" <<'PYEOF'
import re, json, sys
from datetime import datetime, timezone

raw_output_path, output_path, finding_id = sys.argv[1:4]

with open(raw_output_path) as f:
    text = f.read()

result = None

# Try to find JSON with overall_result key — search from end of output
# Strategy 1: Find complete JSON objects with nested structures
json_candidates = []
brace_depth = 0
start_idx = None
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
                json_candidates.append(candidate)
            start_idx = None

# Try parsing candidates from last to first (prefer the final one)
for candidate in reversed(json_candidates):
    try:
        parsed = json.loads(candidate)
        if "overall_result" in parsed:
            result = parsed
            break
    except json.JSONDecodeError:
        continue

# Fallback: simple regex for flat JSON
if result is None:
    matches = re.findall(r'\{[^{}]*"overall_result"[^{}]*\}', text, re.DOTALL)
    for match in reversed(matches):
        try:
            result = json.loads(match)
            break
        except json.JSONDecodeError:
            continue

# Final fallback: unparseable output
if result is None:
    result = {
        "overall_result": "FAIL",
        "confidence": 0,
        "prd_alignment_score": 0,
        "findings": [{"severity": "CRITICAL", "category": "alignment",
                       "description": "Could not parse verification output",
                       "evidence": text[-500:] if len(text) > 500 else text}],
        "cross_engine_verification": {"touchpoints_verified": 0, "touchpoints_total": 0, "result": "FAIL"},
        "anti_patterns_detected": [],
        "requirements_traced": {"total": 0, "matched": 0, "missing": []}
    }

# Wrap with stage metadata
output = {
    "stage": "semantic_verification",
    "finding_id": finding_id,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "overall_result": result.get("overall_result", "FAIL"),
    "confidence": result.get("confidence", 0),
    "prd_alignment_score": result.get("prd_alignment_score", 0),
    "findings": result.get("findings", []),
    "cross_engine_verification": result.get("cross_engine_verification", {}),
    "anti_patterns_detected": result.get("anti_patterns_detected", []),
    "requirements_traced": result.get("requirements_traced", {})
}

with open(output_path, 'w') as f:
    json.dump(output, f, indent=2)
    f.write('\n')
PYEOF

# ---------------------------------------------------------------------------
# Determine exit code from result
# ---------------------------------------------------------------------------

OVERALL_RESULT=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/verification_stage7_${FINDING_ID}.json'))['overall_result'])")

log "INFO" "Stage 7 completed — result: $OVERALL_RESULT"
log "INFO" "Report written to $OUTPUT_DIR/verification_stage7_${FINDING_ID}.json"

if [[ "$OVERALL_RESULT" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
