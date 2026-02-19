#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage3-integration-design.sh — Stage 3: Integration Design
# ============================================================================
#
# Takes accepted impact reports from Stage 2 and generates concrete
# integration plans through Claude Code CLI sessions.
#
# Usage (called by Makefile pipeline-stage3):
#   scripts/stage3-integration-design.sh \
#       --impact-dir runs/TIMESTAMP \
#       --packages-dir /path/to/target-product/packages \
#       --claude-md /path/to/target-product/CLAUDE.md \
#       --output runs/TIMESTAMP \
#       [--timeout 900]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage3_integration_design"

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

IMPACT_DIR=""
PACKAGES_DIR=""
CLAUDE_MD_PATH=""
OUTPUT_DIR=""
TIMEOUT=900
FINDING_ID_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --impact-dir)
            IMPACT_DIR="$2"
            shift 2
            ;;
        --packages-dir)
            PACKAGES_DIR="$2"
            shift 2
            ;;
        --claude-md)
            CLAUDE_MD_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --finding-id)
            FINDING_ID_FILTER="$2"
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
for arg_name in IMPACT_DIR PACKAGES_DIR CLAUDE_MD_PATH OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -d "$IMPACT_DIR" ]]; then
    log "ERROR" "Impact directory not found: $IMPACT_DIR"
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

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Temp directory with cleanup
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Integration plan schema for prompt injection
# ---------------------------------------------------------------------------

INTEGRATION_PLAN_SCHEMA='{
  "finding_id": "string",
  "affected_engines": ["list of engine names"],
  "modifications": [
    {
      "engine": "engine name",
      "files": [
        {"path": "relative/path.swift", "action": "modify", "description": "what changes"}
      ],
      "contract_changes": [
        {"protocol": "ProtocolName", "change": "add method / modify signature", "description": "details"}
      ]
    }
  ],
  "cross_engine_touchpoints": [
    {"from": "engine", "to": "engine", "via": "PortName", "description": "how they connect"}
  ],
  "new_files": [],
  "test_files": ["packages/module/tests/test_new.py"],
  "constraints": {
    "no_new_packages": true,
    "no_standalone_modules": true,
    "existing_dependency_graph_only": true
  }
}'

# ---------------------------------------------------------------------------
# Read prompt template and CLAUDE.md
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE_PATH="$SCRIPT_DIR/../prompts/integration_design.md"
if [[ ! -f "$PROMPT_TEMPLATE_PATH" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE_PATH"
    exit 1
fi

CLAUDE_MD_RULES=""
if [[ -f "$CLAUDE_MD_PATH" ]]; then
    # Extract architecture-relevant sections (1-4)
    CLAUDE_MD_RULES=$(cat "$CLAUDE_MD_PATH")
fi

# ---------------------------------------------------------------------------
# Extract contracts once
# ---------------------------------------------------------------------------

log "INFO" "Extracting engine contracts from $PACKAGES_DIR"

python3 "$SCRIPT_DIR/extract_contracts.py" \
    --packages-dir "$PACKAGES_DIR" --format markdown \
    --output "$TMP_DIR/contracts.md" > /dev/null 2>&1

python3 "$SCRIPT_DIR/extract_contracts.py" \
    --packages-dir "$PACKAGES_DIR" --format json \
    --output "$TMP_DIR/contracts.json" > /dev/null 2>&1

log "INFO" "Contracts extracted"

# ---------------------------------------------------------------------------
# Find accepted impact reports
# ---------------------------------------------------------------------------

ACCEPTED_FINDINGS=()
for validation_file in "$IMPACT_DIR"/validation_stage2_*.json; do
    [[ ! -f "$validation_file" ]] && continue

    RESULT=$(python3 -c "import json; print(json.load(open('$validation_file')).get('result', ''))" 2>/dev/null || echo "")
    if [[ "$RESULT" == "ACCEPTED" ]]; then
        FINDING_ID=$(python3 -c "import json; print(json.load(open('$validation_file')).get('finding_id', ''))" 2>/dev/null || echo "")
        if [[ -n "$FINDING_ID" ]]; then
            # If --finding-id is set, only include that specific finding
            if [[ -n "$FINDING_ID_FILTER" && "$FINDING_ID" != "$FINDING_ID_FILTER" ]]; then
                continue
            fi
            ACCEPTED_FINDINGS+=("$FINDING_ID")
        fi
    fi
done

log "INFO" "Stage 3 started — Integration Design"
log "INFO" "Found ${#ACCEPTED_FINDINGS[@]} accepted impact reports"

if [[ ${#ACCEPTED_FINDINGS[@]} -eq 0 ]]; then
    log "INFO" "No accepted findings to process"
    # Write empty summary
    python3 -c "
import json
from datetime import datetime, timezone
summary = {
    'stage': 'integration_design',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'findings_processed': 0,
    'accepted': 0,
    'rejected': 0,
    'failed': 0,
    'reports': [],
}
with open('$OUTPUT_DIR/stage3_summary.json', 'w') as f:
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
    log "INFO" "Processing finding: $FINDING_ID"

    IMPACT_REPORT="$IMPACT_DIR/impact_report_${FINDING_ID}.json"
    if [[ ! -f "$IMPACT_REPORT" ]]; then
        log "WARN" "Impact report not found: $IMPACT_REPORT — skipping"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "Impact report not found"
        continue
    fi

    # Get affected engines from impact report
    AFFECTED_ENGINES=$(python3 -c "
import json
report = json.load(open('$IMPACT_REPORT'))
print(' '.join(report.get('affected_engines', [])))
" 2>/dev/null || echo "")

    if [[ -z "$AFFECTED_ENGINES" ]]; then
        log "WARN" "No affected engines in impact report for $FINDING_ID"
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

    # Build file tree for affected engines (language-agnostic)
    # Read module prefix and source extensions from project config
    PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
    MODULE_PREFIX=""
    SOURCE_EXTS=".py"
    if [[ -f "$PROJECT_CONFIG" ]]; then
        MODULE_PREFIX=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('module_prefix', ''))" 2>/dev/null || echo "")
        SOURCE_EXTS=$(python3 -c "import json; print(' '.join(json.load(open('$PROJECT_CONFIG')).get('source_extensions', ['.py'])))" 2>/dev/null || echo ".py")
    fi

    FILE_TREE=""
    for engine in $AFFECTED_ENGINES; do
        engine_dir="$PACKAGES_DIR/${MODULE_PREFIX}${engine}"
        if [[ -d "$engine_dir" ]]; then
            FILE_TREE+="## $engine"$'\n'
            for ext in $SOURCE_EXTS; do
                FILE_TREE+=$(find "$engine_dir" -name "*${ext}" -not -path "*/.build/*" -not -path "*/node_modules/*" -not -path "*/__pycache__/*" 2>/dev/null | sort | sed "s|$PACKAGES_DIR/||")
            done
            FILE_TREE+=$'\n\n'
        fi
    done

    # Assemble prompt — use Python with file reads (no shell variable injection)
    echo "$CLAUDE_MD_RULES" > "$TMP_DIR/claude_md_rules.txt"
    echo "$FILE_TREE" > "$TMP_DIR/file_tree_${FINDING_ID}.txt"
    echo "$INTEGRATION_PLAN_SCHEMA" > "$TMP_DIR/schema.txt"

    python3 - "$PROMPT_TEMPLATE_PATH" "$IMPACT_REPORT" "$TMP_DIR/contracts_${FINDING_ID}.md" \
        "$TMP_DIR/claude_md_rules.txt" "$TMP_DIR/file_tree_${FINDING_ID}.txt" \
        "$TMP_DIR/schema.txt" "$TMP_DIR/prompt_${FINDING_ID}.md" <<'PYEOF'
import sys

template_path, impact_path, contracts_path, claude_md_path, file_tree_path, schema_path, output_path = sys.argv[1:8]

with open(template_path) as f:
    template = f.read()
with open(impact_path) as f:
    impact_report = f.read()
with open(contracts_path) as f:
    contracts = f.read()
with open(claude_md_path) as f:
    claude_md = f.read()[:2000]
with open(file_tree_path) as f:
    file_tree = f.read()
with open(schema_path) as f:
    schema = f.read()

result = template
result = result.replace("{{CLAUDE_MD_RULES}}", claude_md)
result = result.replace("{{IMPACT_REPORT}}", impact_report)
result = result.replace("{{ENGINE_CONTRACTS}}", contracts)
result = result.replace("{{FILE_TREE}}", file_tree)
result = result.replace("{{INTEGRATION_PLAN_SCHEMA}}", schema)

with open(output_path, "w") as f:
    f.write(result)
PYEOF

    # Invoke AI analysis
    RAW_OUTPUT="$TMP_DIR/raw_${FINDING_ID}.json"
    CLAUDE_EXIT=0

    ai_invoke "$TMP_DIR/prompt_${FINDING_ID}.md" "$RAW_OUTPUT" "stage3" "$FINDING_ID" \
        --output-format json --max-turns 5 \
        || CLAUDE_EXIT=$?

    if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
        log "INFO" "Session mode: skipping $FINDING_ID (prompt written, awaiting response)"
        continue
    elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
        log "ERROR" "AI invocation failed for $FINDING_ID (exit=$CLAUDE_EXIT)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "AI invocation failed"
        continue
    fi

    # Extract JSON from Claude output
    PLAN_FILE="$OUTPUT_DIR/integration_plan_${FINDING_ID}.json"
    EXTRACT_EXIT=0
    python3 - "$RAW_OUTPUT" "$PLAN_FILE" <<'PYEOF' || EXTRACT_EXIT=$?
import json, sys

raw_file, plan_file = sys.argv[1], sys.argv[2]

with open(raw_file, 'r') as f:
    raw = f.read()

# Try parsing structured output
try:
    data = json.loads(raw)
    if isinstance(data, dict) and "result" in data:
        text = data["result"]
    elif isinstance(data, list):
        text = ""
        for msg in data:
            if isinstance(msg, dict) and msg.get("role") == "assistant":
                content = msg.get("content", "")
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text = block.get("text", "")
                elif isinstance(content, str):
                    text = content
    else:
        text = raw
except json.JSONDecodeError:
    text = raw

start = text.find('{')
end = text.rfind('}')
if start == -1 or end == -1:
    print("ERROR: No JSON object found in Claude output", file=sys.stderr)
    sys.exit(1)

plan = json.loads(text[start:end+1])

with open(plan_file, 'w') as f:
    json.dump(plan, f, indent=2)
    f.write('\n')
PYEOF

    if [[ "$EXTRACT_EXIT" -ne 0 ]]; then
        log "ERROR" "Failed to extract JSON for $FINDING_ID"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "JSON extraction failed"
        continue
    fi

    # Validate integration plan
    VALIDATION_FILE="$OUTPUT_DIR/validation_stage3_${FINDING_ID}.json"
    VALIDATE_EXIT=0

    python3 "$SCRIPT_DIR/validate_integration_plan.py" \
        --plan "$PLAN_FILE" \
        --packages-dir "$PACKAGES_DIR" \
        --contracts "$TMP_DIR/contracts.json" \
        --output "$VALIDATION_FILE" > /dev/null 2>&1 || VALIDATE_EXIT=$?

    VALIDATION_RESULT=$(python3 -c "import json; print(json.load(open('$VALIDATION_FILE')).get('result', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

    if [[ "$VALIDATION_RESULT" == "ACCEPTED" ]]; then
        log "INFO" "Finding $FINDING_ID: Integration plan ACCEPTED"

        # Generate manifest
        ENGINE_GRAPH_PATH="$SCRIPT_DIR/../config/engine_graph.json"
        MANIFEST_FILE="$OUTPUT_DIR/manifest_${FINDING_ID}.json"

        python3 "$SCRIPT_DIR/generate_manifest.py" \
            --plan "$PLAN_FILE" \
            --engine-graph "$ENGINE_GRAPH_PATH" \
            --output "$MANIFEST_FILE" > /dev/null 2>&1

        log "INFO" "Manifest generated: $MANIFEST_FILE"
        ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "ACCEPTED"
    else
        REJECT_REASON=$(python3 -c "
import json
data = json.load(open('$VALIDATION_FILE'))
failures = [c['reason'] for c in data.get('checks', []) if c.get('result') == 'FAIL']
print('; '.join(failures[:3]))" 2>/dev/null || echo "validation failed")
        log "INFO" "Finding $FINDING_ID: Integration plan REJECTED ($REJECT_REASON)"
        REJECTED_COUNT=$((REJECTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "REJECTED" "$REJECT_REASON"
    fi
done

# ---------------------------------------------------------------------------
# Write stage3_summary.json
# ---------------------------------------------------------------------------

TOTAL=$((ACCEPTED_COUNT + REJECTED_COUNT + FAILED_COUNT))

python3 - "$SUMMARY_FILE" "$OUTPUT_DIR/stage3_summary.json" "$TOTAL" "$ACCEPTED_COUNT" "$REJECTED_COUNT" "$FAILED_COUNT" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

summary_file = sys.argv[1]
output_file = sys.argv[2]
processed, accepted, rejected, failed = (int(x) for x in sys.argv[3:7])

with open(summary_file) as f:
    reports = json.load(f)

summary = {
    "stage": "integration_design",
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

log "INFO" "Stage 3 completed — processed=$TOTAL accepted=$ACCEPTED_COUNT rejected=$REJECTED_COUNT failed=$FAILED_COUNT"
log "INFO" "Summary written to $OUTPUT_DIR/stage3_summary.json"

exit 0
