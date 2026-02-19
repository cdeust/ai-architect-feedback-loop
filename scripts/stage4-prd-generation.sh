#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage4-prd-generation.sh — Stage 4: PRD Generation (Dogfood via SKILL.md)
# ============================================================================
#
# Processes accepted integration plans through the product's own PRD
# generation flow (SKILL.md via Claude Code CLI).
#
# Usage (called by Makefile pipeline-stage4):
#   scripts/stage4-prd-generation.sh \
#       --run-dir runs/TIMESTAMP \
#       --packages-dir /path/to/target-product/packages \
#       --builder-dir /path/to/target-product \
#       --engine-graph config/engine_graph.json \
#       --category-map config/category_engine_map.json \
#       --config config/thresholds.json \
#       --output runs/TIMESTAMP \
#       [--timeout 1200] [--max-prds 20]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage4_prd_generation"

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
PACKAGES_DIR=""
BUILDER_DIR=""
ENGINE_GRAPH=""
CATEGORY_MAP=""
CONFIG_PATH=""
OUTPUT_DIR=""
TIMEOUT=1200
MAX_PRDS=20
MAX_PRD_RETRIES=3

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir)
            RUN_DIR="$2"
            shift 2
            ;;
        --packages-dir)
            PACKAGES_DIR="$2"
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
        --category-map)
            CATEGORY_MAP="$2"
            shift 2
            ;;
        --config)
            CONFIG_PATH="$2"
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
        --max-prds)
            MAX_PRDS="$2"
            shift 2
            ;;
        --max-prd-retries)
            MAX_PRD_RETRIES="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required args
for arg_name in RUN_DIR PACKAGES_DIR BUILDER_DIR ENGINE_GRAPH CATEGORY_MAP CONFIG_PATH OUTPUT_DIR; do
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

if [[ ! -d "$PACKAGES_DIR" ]]; then
    log "ERROR" "Packages directory not found: $PACKAGES_DIR"
    exit 1
fi

# Check for claude CLI
if ! command -v claude &> /dev/null; then
    log "ERROR" "claude CLI not found in PATH"
    exit 1
fi

# Resolve paths to absolute (Stage 4 cd's to BUILDER_DIR)
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
BUILDER_DIR="$(cd "$BUILDER_DIR" && pwd)"
PACKAGES_DIR="$(cd "$PACKAGES_DIR" && pwd)"
ENGINE_GRAPH="$(cd "$(dirname "$ENGINE_GRAPH")" && pwd)/$(basename "$ENGINE_GRAPH")"
CATEGORY_MAP="$(cd "$(dirname "$CATEGORY_MAP")" && pwd)/$(basename "$CATEGORY_MAP")"
CONFIG_PATH="$(cd "$(dirname "$CONFIG_PATH")" && pwd)/$(basename "$CONFIG_PATH")"

mkdir -p "$OUTPUT_DIR"

# Read max retries from config if not overridden
if [[ "$MAX_PRD_RETRIES" -eq 3 && -f "$CONFIG_PATH" ]]; then
    MAX_PRD_RETRIES=$(python3 -c "import json; print(json.load(open('$CONFIG_PATH')).get('retry', {}).get('max_attempts', 3))" 2>/dev/null || echo 3)
fi

# ---------------------------------------------------------------------------
# Temp directory with cleanup
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# PRD summary schema for prompt injection
# ---------------------------------------------------------------------------

PRD_SUMMARY_SCHEMA='{
  "finding_id": "string",
  "prd_file": "prd.md",
  "verification_file": "prd-verification.md",
  "jira_file": "prd-jira.md",
  "tests_file": "prd-tests.md",
  "overall_score": 0.0,
  "section_count": 0,
  "fr_count": 0,
  "ac_count": 0,
  "total_sp": 0
}'

# ---------------------------------------------------------------------------
# Read prompt template
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE_PATH="$SCRIPT_DIR/../prompts/prd_generation.md"
if [[ ! -f "$PROMPT_TEMPLATE_PATH" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract contracts once
# ---------------------------------------------------------------------------

log "INFO" "Extracting engine contracts from $PACKAGES_DIR"

python3 "$SCRIPT_DIR/extract_contracts.py" \
    --packages-dir "$PACKAGES_DIR" --format markdown \
    --output "$TMP_DIR/contracts.md" > /dev/null 2>&1

log "INFO" "Contracts extracted"

# ---------------------------------------------------------------------------
# Find accepted integration plans
# ---------------------------------------------------------------------------

ACCEPTED_FINDINGS=()
for validation_file in "$RUN_DIR"/validation_stage3_*.json; do
    [[ ! -f "$validation_file" ]] && continue

    RESULT=$(python3 -c "import json; print(json.load(open('$validation_file')).get('result', ''))" 2>/dev/null || echo "")
    if [[ "$RESULT" == "ACCEPTED" ]]; then
        FINDING_ID=$(python3 -c "import json; print(json.load(open('$validation_file')).get('finding_id', ''))" 2>/dev/null || echo "")
        if [[ -n "$FINDING_ID" ]]; then
            ACCEPTED_FINDINGS+=("$FINDING_ID")
        fi
    fi
done

log "INFO" "Stage 4 started — PRD Generation (Dogfood)"
log "INFO" "Found ${#ACCEPTED_FINDINGS[@]} accepted integration plans"

if [[ ${#ACCEPTED_FINDINGS[@]} -eq 0 ]]; then
    log "INFO" "No accepted findings to process"
    python3 -c "
import json
from datetime import datetime, timezone
summary = {
    'stage': 'prd_generation',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'findings_processed': 0,
    'accepted': 0,
    'rejected': 0,
    'failed': 0,
    'reports': [],
}
with open('$OUTPUT_DIR/stage4_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
"
    exit 0
fi

# ---------------------------------------------------------------------------
# Summary tracking
# ---------------------------------------------------------------------------

SUMMARY_FILE="$TMP_DIR/summary_results.json"
echo '[]' > "$SUMMARY_FILE"

ACCEPTED_COUNT=0
REJECTED_COUNT=0
FAILED_COUNT=0
PROCESSED=0

add_summary_result() {
    local finding_id="$1" result="$2" reason="${3:-}"
    python3 - "$SUMMARY_FILE" "$finding_id" "$result" "$reason" <<'PYEOF'
import json, sys
summary_file, fid, result, reason = sys.argv[1:5]
with open(summary_file) as f:
    results = json.load(f)
entry = {"finding_id": fid, "result": result}
if reason:
    entry["reason"] = reason
results.append(entry)
with open(summary_file, 'w') as f:
    json.dump(results, f)
PYEOF
}

# ---------------------------------------------------------------------------
# Process each accepted finding
# ---------------------------------------------------------------------------

for FINDING_ID in "${ACCEPTED_FINDINGS[@]}"; do
    if [[ "$PROCESSED" -ge "$MAX_PRDS" ]]; then
        log "INFO" "Reached max PRDs limit ($MAX_PRDS), stopping"
        break
    fi

    log "INFO" "Processing finding: $FINDING_ID"
    PROCESSED=$((PROCESSED + 1))

    IMPACT_REPORT="$RUN_DIR/impact_report_${FINDING_ID}.json"
    INTEGRATION_PLAN="$RUN_DIR/integration_plan_${FINDING_ID}.json"
    MANIFEST="$RUN_DIR/manifest_${FINDING_ID}.json"

    if [[ ! -f "$IMPACT_REPORT" ]]; then
        log "WARN" "Impact report not found: $IMPACT_REPORT — skipping"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "Impact report not found"
        continue
    fi

    if [[ ! -f "$INTEGRATION_PLAN" ]]; then
        log "WARN" "Integration plan not found: $INTEGRATION_PLAN — skipping"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "Integration plan not found"
        continue
    fi

    # Get affected engines
    AFFECTED_ENGINES=$(python3 -c "
import json
report = json.load(open('$IMPACT_REPORT'))
print(' '.join(report.get('affected_engines', [])))
" 2>/dev/null || echo "")

    if [[ -z "$AFFECTED_ENGINES" ]]; then
        log "WARN" "No affected engines for $FINDING_ID"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "No affected engines"
        continue
    fi

    # Extract contracts for affected engines only
    # shellcheck disable=SC2086
    python3 "$SCRIPT_DIR/extract_contracts.py" \
        --packages-dir "$PACKAGES_DIR" --format markdown \
        --engines $AFFECTED_ENGINES \
        --output "$TMP_DIR/contracts_${FINDING_ID}.md" > /dev/null 2>&1

    # Compose PRD input
    COMPOSE_EXIT=0
    COMPOSE_ARGS=(
        --impact-report "$IMPACT_REPORT"
        --integration-plan "$INTEGRATION_PLAN"
        --contracts-md "$TMP_DIR/contracts_${FINDING_ID}.md"
        --engine-graph "$ENGINE_GRAPH"
        --category-map "$CATEGORY_MAP"
        --output "$TMP_DIR/prd_input_${FINDING_ID}.md"
    )

    if [[ -f "$MANIFEST" ]]; then
        COMPOSE_ARGS+=(--manifest "$MANIFEST")
    fi

    python3 "$SCRIPT_DIR/compose_prd_input.py" \
        "${COMPOSE_ARGS[@]}" > /dev/null 2>&1 || COMPOSE_EXIT=$?

    if [[ "$COMPOSE_EXIT" -ne 0 ]]; then
        log "ERROR" "compose_prd_input.py failed for $FINDING_ID"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "PRD input composition failed"
        continue
    fi

    # Create workspace
    WORKSPACE="$TMP_DIR/prd_workspace_${FINDING_ID}"
    mkdir -p "$WORKSPACE"

    # Assemble prompt from template
    echo "$PRD_SUMMARY_SCHEMA" > "$TMP_DIR/schema.txt"

    ARCHITECTURE_MD="$SCRIPT_DIR/../config/architecture.md"

    python3 - "$PROMPT_TEMPLATE_PATH" "$TMP_DIR/prd_input_${FINDING_ID}.md" \
        "$TMP_DIR/schema.txt" "$ENGINE_GRAPH" "$ARCHITECTURE_MD" \
        "$TMP_DIR/prompt_${FINDING_ID}.md" <<'PYEOF'
import sys

template_path, prd_input_path, schema_path, engine_graph_path, arch_path, output_path = sys.argv[1:7]

with open(template_path) as f:
    template = f.read()
with open(prd_input_path) as f:
    prd_input = f.read()
with open(schema_path) as f:
    schema = f.read()
with open(engine_graph_path) as f:
    engine_graph = f.read()
arch = ""
try:
    with open(arch_path) as f:
        arch = f.read()
except FileNotFoundError:
    pass

result = template
result = result.replace("{{PRD_INPUT}}", prd_input)
result = result.replace("{{PRD_SUMMARY_SCHEMA}}", schema)
result = result.replace("{{ENGINE_GRAPH}}", engine_graph)
result = result.replace("{{ARCHITECTURE_DESCRIPTION}}", arch)

with open(output_path, "w") as f:
    f.write(result)
PYEOF

    # -------------------------------------------------------------------
    # Retry loop: invoke AI → validate → retry with failure context
    # -------------------------------------------------------------------
    PRD_ATTEMPT=0
    PRD_ACCEPTED=false
    FAILURE_CONTEXT=""

    while [[ "$PRD_ATTEMPT" -lt "$MAX_PRD_RETRIES" ]]; do
        PRD_ATTEMPT=$((PRD_ATTEMPT + 1))
        log "INFO" "PRD attempt $PRD_ATTEMPT/$MAX_PRD_RETRIES for $FINDING_ID"

        # On retry, append failure context to prompt
        CURRENT_PROMPT="$TMP_DIR/prompt_${FINDING_ID}.md"
        if [[ -n "$FAILURE_CONTEXT" ]]; then
            RETRY_PROMPT="$TMP_DIR/prompt_${FINDING_ID}_retry${PRD_ATTEMPT}.md"
            cat "$CURRENT_PROMPT" > "$RETRY_PROMPT"
            cat >> "$RETRY_PROMPT" <<RETRY_EOF

## Previous Attempt Failed — Fix These Issues (attempt $((PRD_ATTEMPT - 1)))

The previous PRD generation was REJECTED by the quality gate. You MUST fix
the following validation failures before regenerating the 4 files:

$FAILURE_CONTEXT

Re-generate all 4 files (prd.md, prd-verification.md, prd-jira.md, prd-tests.md)
with these issues resolved. Do NOT skip any section or leave placeholders.
RETRY_EOF
            CURRENT_PROMPT="$RETRY_PROMPT"
        fi

        # Invoke AI analysis (builder-dir for skill access)
        RAW_OUTPUT="$TMP_DIR/raw_${FINDING_ID}_${PRD_ATTEMPT}.txt"
        CLAUDE_EXIT=0

        cd "$BUILDER_DIR"
        ai_invoke "$CURRENT_PROMPT" "$RAW_OUTPUT" "stage4" "$FINDING_ID" \
            --max-turns 20 \
            || CLAUDE_EXIT=$?

        if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
            log "INFO" "Session mode: skipping $FINDING_ID (prompt written, awaiting response)"
            break
        elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
            log "ERROR" "AI invocation failed for $FINDING_ID attempt $PRD_ATTEMPT (exit=$CLAUDE_EXIT)"
            continue
        fi

        # Collect PRD output files from builder dir (Claude writes them there)
        PRD_FILES_FOUND=0
        for prd_file in prd.md prd-verification.md prd-jira.md prd-tests.md; do
            if [[ -f "$BUILDER_DIR/$prd_file" ]]; then
                cp "$BUILDER_DIR/$prd_file" "$WORKSPACE/$prd_file"
                rm -f "$BUILDER_DIR/$prd_file"
                PRD_FILES_FOUND=$((PRD_FILES_FOUND + 1))
            fi
        done

        if [[ "$PRD_FILES_FOUND" -eq 0 ]]; then
            log "WARN" "No PRD files generated for $FINDING_ID (attempt $PRD_ATTEMPT)"
            FAILURE_CONTEXT="No PRD files were written to disk. You MUST use the Write tool to create all 4 files: prd.md, prd-verification.md, prd-jira.md, prd-tests.md in the current directory."
            continue
        fi

        # Quality scoring via extract_prd_metrics.py
        METRICS_FILE="$TMP_DIR/metrics_${FINDING_ID}.json"
        METRICS_EXIT=0

        METRICS_ARGS=(--output "$METRICS_FILE")
        [[ -f "$WORKSPACE/prd.md" ]] && METRICS_ARGS+=(--prd "$WORKSPACE/prd.md")
        [[ -f "$WORKSPACE/prd-verification.md" ]] && METRICS_ARGS+=(--verification "$WORKSPACE/prd-verification.md")
        [[ -f "$WORKSPACE/prd-tests.md" ]] && METRICS_ARGS+=(--tests "$WORKSPACE/prd-tests.md")

        python3 "$SCRIPT_DIR/extract_prd_metrics.py" \
            "${METRICS_ARGS[@]}" > /dev/null 2>&1 || METRICS_EXIT=$?

        if [[ "$METRICS_EXIT" -ne 0 ]]; then
            log "WARN" "Metrics extraction failed for $FINDING_ID (attempt $PRD_ATTEMPT)"
            FAILURE_CONTEXT="Metrics extraction failed. Ensure prd-verification.md includes '**Overall Score:** NN%' and prd.md has proper FR/AC IDs."
            continue
        fi

        # Quality gate
        GATE_RESULT=$(python3 - "$METRICS_FILE" "$CONFIG_PATH" <<'PYEOF'
import json, sys
metrics = json.load(open(sys.argv[1]))
config = json.load(open(sys.argv[2]))
threshold = config.get("stage_4", {}).get("prd_quality_minimum", 0.85)
score = (metrics.get("verification", {}) or {}).get("overall_score")
if score is None:
    print("NO_SCORE")
elif score >= threshold:
    print("PASS")
else:
    print(f"FAIL:{score:.2f}")
PYEOF
        )

        if [[ "$GATE_RESULT" == "NO_SCORE" ]]; then
            log "WARN" "No verification score for $FINDING_ID (attempt $PRD_ATTEMPT)"
        elif [[ "$GATE_RESULT" == FAIL:* ]]; then
            SCORE="${GATE_RESULT#FAIL:}"
            log "INFO" "Quality gate failed for $FINDING_ID (score=$SCORE, attempt $PRD_ATTEMPT)"
        fi

        # Validate PRD output
        VALIDATION_FILE="$OUTPUT_DIR/validation_stage4_${FINDING_ID}.json"
        VALIDATE_EXIT=0

        python3 "$SCRIPT_DIR/validate_prd_output.py" \
            --prd-dir "$WORKSPACE" \
            --integration-plan "$INTEGRATION_PLAN" \
            --engine-graph "$ENGINE_GRAPH" \
            --metrics "$METRICS_FILE" \
            --config "$CONFIG_PATH" \
            --output "$VALIDATION_FILE" > /dev/null 2>&1 || VALIDATE_EXIT=$?

        VALIDATION_RESULT=$(python3 -c "import json; print(json.load(open('$VALIDATION_FILE')).get('result', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

        if [[ "$VALIDATION_RESULT" == "ACCEPTED" ]]; then
            log "INFO" "Finding $FINDING_ID: PRD ACCEPTED (attempt $PRD_ATTEMPT)"
            PRD_ACCEPTED=true
            break
        fi

        # Build failure context for retry
        FAILURE_CONTEXT=$(python3 -c "
import json
data = json.load(open('$VALIDATION_FILE'))
failures = [c for c in data.get('checks', []) if c.get('result') == 'FAIL']
for f in failures:
    print(f'- FAILED: {f[\"check\"]} — {f.get(\"reason\", \"no details\")}')
" 2>/dev/null || echo "- Validation failed (unknown reason)")
        log "INFO" "Finding $FINDING_ID: PRD REJECTED (attempt $PRD_ATTEMPT), retrying..."
    done

    if [[ "$PRD_ACCEPTED" == "true" ]]; then
        # Copy PRD files + metrics to output
        PRD_OUTPUT_DIR="$OUTPUT_DIR/prd_output_${FINDING_ID}"
        mkdir -p "$PRD_OUTPUT_DIR"
        cp "$WORKSPACE"/*.md "$PRD_OUTPUT_DIR/" 2>/dev/null || true
        cp "$METRICS_FILE" "$PRD_OUTPUT_DIR/metrics.json" 2>/dev/null || true

        ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "ACCEPTED"
    else
        REJECT_REASON=$(python3 -c "
import json
data = json.load(open('$VALIDATION_FILE'))
failures = [c['reason'] for c in data.get('checks', []) if c.get('result') == 'FAIL']
print('; '.join(failures[:3]))" 2>/dev/null || echo "validation failed")
        log "INFO" "Finding $FINDING_ID: PRD REJECTED after $MAX_PRD_RETRIES attempts ($REJECT_REASON)"
        REJECTED_COUNT=$((REJECTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "REJECTED" "$REJECT_REASON"
    fi
done

# ---------------------------------------------------------------------------
# Write stage4_summary.json
# ---------------------------------------------------------------------------

TOTAL=$((ACCEPTED_COUNT + REJECTED_COUNT + FAILED_COUNT))

python3 - "$SUMMARY_FILE" "$OUTPUT_DIR/stage4_summary.json" "$TOTAL" "$ACCEPTED_COUNT" "$REJECTED_COUNT" "$FAILED_COUNT" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

summary_file = sys.argv[1]
output_file = sys.argv[2]
processed, accepted, rejected, failed = (int(x) for x in sys.argv[3:7])

with open(summary_file) as f:
    reports = json.load(f)

summary = {
    "stage": "prd_generation",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "findings_processed": processed,
    "accepted": accepted,
    "rejected": rejected,
    "failed": failed,
    "reports": reports,
}

with open(output_file, 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
PYEOF

log "INFO" "Stage 4 completed — processed=$TOTAL accepted=$ACCEPTED_COUNT rejected=$REJECTED_COUNT failed=$FAILED_COUNT"
log "INFO" "Summary written to $OUTPUT_DIR/stage4_summary.json"

exit 0
