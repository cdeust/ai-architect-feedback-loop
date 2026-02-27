#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage2-impact-analysis.sh — Stage 2: Cross-Engine Impact Analysis
# ============================================================================
#
# Processes prioritized findings through Claude Code CLI sessions with
# full product context injection. Reads prioritized_findings.json
# (pre-sorted by priority_score descending).
#
# Usage (called by Makefile pipeline-stage2):
#   scripts/stage2-impact-analysis.sh \
#       --findings runs/TIMESTAMP/prioritized_findings.json \
#       --engine-graph config/engine_graph.json \
#       --category-map config/category_engine_map.json \
#       --packages-dir /path/to/target-product/packages \
#       --config config/thresholds.json \
#       --output runs/TIMESTAMP \
#       [--max-findings 20] \
#       [--timeout 900]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage2_impact_analysis"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# POSIX-compatible timeout + AI invocation helper
# Runs: run_with_timeout <seconds> <output_file> <cmd...>
# Stdout is captured to output_file; stderr is suppressed.
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

FINDINGS_PATH=""
ENGINE_GRAPH=""
CATEGORY_MAP=""
PACKAGES_DIR=""
CONFIG_PATH=""
OUTPUT_DIR=""
MAX_FINDINGS=20
TIMEOUT=900
FINDING_ID_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --findings)
            FINDINGS_PATH="$2"
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
        --packages-dir)
            PACKAGES_DIR="$2"
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
        --max-findings)
            MAX_FINDINGS="$2"
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
for arg_name in FINDINGS_PATH ENGINE_GRAPH CATEGORY_MAP PACKAGES_DIR OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

for file_path in "$FINDINGS_PATH" "$ENGINE_GRAPH" "$CATEGORY_MAP"; do
    if [[ ! -f "$file_path" ]]; then
        log "ERROR" "File not found: $file_path"
        exit 1
    fi
done

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
# Impact report schema for prompt injection
# ---------------------------------------------------------------------------

IMPACT_REPORT_SCHEMA='{
  "finding_id": "string — the original finding ID",
  "engines_affected": "integer — count of distinct engines affected",
  "compound_score": "float — computed from scoring_breakdown",
  "affected_engines": ["list of engine names"],
  "propagation_paths": [
    {"from": "engine", "to": "engine", "order": 1, "mechanism": "description"}
  ],
  "scoring_breakdown": {
    "engines_affected": {"value": 0, "weight": 0.3},
    "propagation_depth": {"value": 0, "weight": 0.2},
    "contract_impact": {"value": 0.0, "weight": 0.3},
    "test_coverage_delta": {"value": 0.0, "weight": 0.2}
  },
  "recommendation": "PROCEED or REJECT",
  "rationale": "string — brief explanation"
}'

# ---------------------------------------------------------------------------
# Extract contracts once (shared across all findings)
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
# Read prompt template
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE_PATH="$SCRIPT_DIR/../prompts/impact_analysis.md"
if [[ ! -f "$PROMPT_TEMPLATE_PATH" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE_PATH"
    exit 1
fi
PROMPT_TEMPLATE=$(cat "$PROMPT_TEMPLATE_PATH")

# Read engine graph and category map content
ENGINE_GRAPH_CONTENT=$(cat "$ENGINE_GRAPH")
CONTRACTS_MD=$(cat "$TMP_DIR/contracts.md")

# ---------------------------------------------------------------------------
# Summary tracking
# ---------------------------------------------------------------------------

SUMMARY_FILE="$TMP_DIR/summary_results.json"
echo '[]' > "$SUMMARY_FILE"

ACCEPTED=0
REJECTED=0
FAILED=0
SKIPPED=0

add_summary_result() {
    local finding_id="$1" result="$2" score="$3" engines="$4" reason="${5:-}"
    python3 - "$SUMMARY_FILE" "$finding_id" "$result" "$score" "$engines" "$reason" <<'PYEOF'
import json, sys
summary_file, fid, result, score, engines, reason = sys.argv[1:7]
with open(summary_file) as f:
    results = json.load(f)
entry = {"finding_id": fid, "result": result, "compound_score": float(score), "engines_affected": int(engines)}
if reason:
    entry["reason"] = reason
results.append(entry)
with open(summary_file, 'w') as f:
    json.dump(results, f)
PYEOF
}

# ---------------------------------------------------------------------------
# Process each finding
# ---------------------------------------------------------------------------

log "INFO" "Stage 2 started — Cross-Engine Impact Analysis"
log "INFO" "Processing up to $MAX_FINDINGS findings from $FINDINGS_PATH"

FINDINGS_COUNT=$(python3 -c "
import json
data = json.load(open('$FINDINGS_PATH'))
findings = data.get('findings', [])
print(len(findings))
")

log "INFO" "Total findings available: $FINDINGS_COUNT"

PROCESSED=0

python3 -c "
import json
data = json.load(open('$FINDINGS_PATH'))
findings = data.get('findings', [])
finding_id_filter = '$FINDING_ID_FILTER'
if finding_id_filter:
    findings = [f for f in findings if f.get('id', f.get('finding_id', '')) == finding_id_filter]
else:
    findings = findings[:$MAX_FINDINGS]
for i, f in enumerate(findings):
    with open('$TMP_DIR/finding_{}.json'.format(i), 'w') as out:
        json.dump(f, out, indent=2)
    print(f.get('id', f.get('finding_id', 'unknown-{}'.format(i))))
" > "$TMP_DIR/finding_ids.txt"

while IFS= read -r FINDING_ID; do
    [[ -z "$FINDING_ID" ]] && continue

    if [[ "$PROCESSED" -ge "$MAX_FINDINGS" ]]; then
        break
    fi

    FINDING_FILE="$TMP_DIR/finding_${PROCESSED}.json"
    if [[ ! -f "$FINDING_FILE" ]]; then
        PROCESSED=$((PROCESSED + 1))
        continue
    fi

    log "INFO" "Processing finding $((PROCESSED + 1))/$MAX_FINDINGS: $FINDING_ID"

    # Get finding category and look up mapping
    FINDING_CATEGORY=$(python3 -c "import json; print(json.load(open('$FINDING_FILE')).get('relevance_category', 'unknown'))")
    FINDING_JSON=$(cat "$FINDING_FILE")

    # Check if category has a mapping
    HAS_MAPPING=$(python3 -c "
import json
cat_map = json.load(open('$CATEGORY_MAP'))
print('yes' if '$FINDING_CATEGORY' in cat_map.get('mappings', {}) else 'no')
")

    if [[ "$HAS_MAPPING" == "no" ]]; then
        log "WARN" "Finding $FINDING_ID has unmapped category: $FINDING_CATEGORY — skipping"
        SKIPPED=$((SKIPPED + 1))
        add_summary_result "$FINDING_ID" "SKIPPED" "0" "0" "No engine mapping for category $FINDING_CATEGORY"
        PROCESSED=$((PROCESSED + 1))
        continue
    fi

    # Get category-specific mapping
    CATEGORY_MAPPING=$(python3 -c "
import json
cat_map = json.load(open('$CATEGORY_MAP'))
mapping = cat_map['mappings'].get('$FINDING_CATEGORY', {})
print(json.dumps(mapping, indent=2))
")

    # Get engines to include in context (primary + 1st-order propagation)
    CONTEXT_ENGINES=$(python3 -c "
import json
graph = json.load(open('$ENGINE_GRAPH'))
cat_map = json.load(open('$CATEGORY_MAP'))
mapping = cat_map['mappings'].get('$FINDING_CATEGORY', {})
primary = set(mapping.get('primary_engines', []))
for e in list(primary):
    engine_data = graph['engines'].get(e, {})
    primary.update(engine_data.get('feeds', []))
    primary.update(engine_data.get('depended_by', []))
print(' '.join(sorted(primary)))
")

    # Assemble prompt — use Python for all substitutions (sed can't handle multi-line JSON)
    # Write the schema and category mapping to temp files so Python reads them directly
    echo "$IMPACT_REPORT_SCHEMA" > "$TMP_DIR/schema.txt"
    echo "$CATEGORY_MAPPING" > "$TMP_DIR/category_mapping_${PROCESSED}.txt"

    python3 - "$PROMPT_TEMPLATE_PATH" "$ENGINE_GRAPH" "$TMP_DIR/contracts.md" \
        "$FINDING_FILE" "$TMP_DIR/schema.txt" "$TMP_DIR/category_mapping_${PROCESSED}.txt" \
        "$CONFIG_PATH" "$TMP_DIR/prompt_${PROCESSED}.md" <<'PYEOF'
import json, sys

template_path, engine_graph_path, contracts_path, finding_path, schema_path, cat_map_path, config_path, output_path = sys.argv[1:9]

with open(template_path) as f:
    template = f.read()
with open(engine_graph_path) as f:
    engine_graph = f.read()
with open(contracts_path) as f:
    contracts = f.read()
with open(finding_path) as f:
    finding = f.read()
with open(schema_path) as f:
    schema = f.read()
with open(cat_map_path) as f:
    category_mapping = f.read()

# Read thresholds for prompt injection
engines_min = 2
score_min = 0.3
if config_path:
    try:
        cfg = json.load(open(config_path))
        s2 = cfg.get("stage_2", {})
        engines_min = s2.get("engines_affected_minimum", 2)
        score_min = s2.get("compound_score_minimum", 0.3)
    except Exception:
        pass

result = template
result = result.replace("{{ENGINE_GRAPH}}", engine_graph)
result = result.replace("{{CATEGORY_ENGINE_MAP}}", category_mapping)
result = result.replace("{{ENGINE_CONTRACTS}}", contracts)
result = result.replace("{{FINDING}}", finding)
result = result.replace("{{IMPACT_REPORT_SCHEMA}}", schema)
result = result.replace("{{ENGINES_AFFECTED_MINIMUM}}", str(engines_min))
result = result.replace("{{COMPOUND_SCORE_MINIMUM}}", str(score_min))

with open(output_path, "w") as f:
    f.write(result)
PYEOF

    # Invoke AI analysis
    RAW_OUTPUT="$TMP_DIR/raw_${PROCESSED}.json"
    CLAUDE_EXIT=0

    ai_invoke "$TMP_DIR/prompt_${PROCESSED}.md" "$RAW_OUTPUT" "stage2" "$FINDING_ID" \
        --output-format json --max-turns 15 \
        || CLAUDE_EXIT=$?

    if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
        log "INFO" "Session mode: skipping $FINDING_ID (prompt written, awaiting response)"
        PROCESSED=$((PROCESSED + 1))
        continue
    elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
        log "ERROR" "AI invocation failed for $FINDING_ID (exit=$CLAUDE_EXIT)"
        FAILED=$((FAILED + 1))
        add_summary_result "$FINDING_ID" "FAILED" "0" "0" "AI invocation failed"
        PROCESSED=$((PROCESSED + 1))
        continue
    fi

    # Extract JSON from Claude output
    REPORT_FILE=$(artifact_impact "$OUTPUT_DIR" "$FINDING_ID")
    EXTRACT_EXIT=0
    python3 - "$RAW_OUTPUT" "$REPORT_FILE" <<'PYEOF' || EXTRACT_EXIT=$?
import json, re, sys

raw_file, report_file = sys.argv[1], sys.argv[2]

with open(raw_file, 'r') as f:
    raw = f.read()

# Try parsing the raw output as structured JSON first
try:
    data = json.loads(raw)
    # Check for Claude CLI error responses or missing result
    if isinstance(data, dict) and data.get("is_error"):
        print(f"ERROR: Claude returned error: {data.get('result', 'unknown')}", file=sys.stderr)
        sys.exit(1)
    if isinstance(data, dict) and data.get("subtype", "").startswith("error"):
        print(f"ERROR: Claude CLI error: {data.get('subtype', 'unknown')} (turns={data.get('num_turns', '?')})", file=sys.stderr)
        sys.exit(1)
    # If it's the Claude output format, extract the result text
    if isinstance(data, dict) and "result" in data:
        text = data["result"]
    elif isinstance(data, list):
        # Find the last assistant text block
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

# Find JSON object in text
start = text.find('{')
end = text.rfind('}')
if start == -1 or end == -1:
    print("ERROR: No JSON object found in Claude output", file=sys.stderr)
    sys.exit(1)

candidate = text[start:end+1]
try:
    report = json.loads(candidate)
except json.JSONDecodeError:
    # Repair non-strict JSON: single quotes → double quotes, trailing commas
    fixed = candidate
    fixed = re.sub(r',\s*([}\]])', r'\1', fixed)
    fixed = re.sub(r"(?<=[\[{,:])\s*'([^']*?)'\s*", r' "\1" ', fixed)
    fixed = re.sub(r"{\s*'([^']*?)'\s*:", r'{ "\1" :', fixed)
    try:
        report = json.loads(fixed)
    except json.JSONDecodeError:
        import ast
        try:
            report = ast.literal_eval(candidate)
        except (ValueError, SyntaxError):
            print(f"ERROR: Failed to parse JSON from Claude output (first 200 chars): {candidate[:200]}", file=sys.stderr)
            sys.exit(1)

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')
PYEOF

    if [[ "$EXTRACT_EXIT" -ne 0 ]]; then
        log "ERROR" "Failed to extract JSON from Claude output for $FINDING_ID"
        FAILED=$((FAILED + 1))
        add_summary_result "$FINDING_ID" "FAILED" "0" "0" "JSON extraction failed"
        PROCESSED=$((PROCESSED + 1))
        continue
    fi

    # Validate via validate_impact_report.py
    VALIDATION_FILE=$(artifact_validation2 "$OUTPUT_DIR" "$FINDING_ID")
    VALIDATE_EXIT=0

    VALIDATE_ARGS=(
        --report "$REPORT_FILE"
        --engine-graph "$ENGINE_GRAPH"
        --output "$VALIDATION_FILE"
        --contracts "$TMP_DIR/contracts.json"
    )
    if [[ -n "$CONFIG_PATH" ]]; then
        VALIDATE_ARGS+=(--config "$CONFIG_PATH")
    fi

    python3 "$SCRIPT_DIR/validate_impact_report.py" "${VALIDATE_ARGS[@]}" > /dev/null 2>&1 || VALIDATE_EXIT=$?

    # Read validation result
    VALIDATION_RESULT=$(python3 -c "import json; print(json.load(open('$VALIDATION_FILE')).get('result', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    COMPOUND_SCORE=$(python3 -c "import json; print(json.load(open('$REPORT_FILE')).get('compound_score', 0))" 2>/dev/null || echo "0")
    ENGINES_COUNT=$(python3 -c "import json; print(json.load(open('$REPORT_FILE')).get('engines_affected', 0))" 2>/dev/null || echo "0")

    if [[ "$VALIDATION_RESULT" == "ACCEPTED" ]]; then
        log "INFO" "Finding $FINDING_ID: ACCEPTED (score=$COMPOUND_SCORE, engines=$ENGINES_COUNT)"
        ACCEPTED=$((ACCEPTED + 1))
        add_summary_result "$FINDING_ID" "ACCEPTED" "$COMPOUND_SCORE" "$ENGINES_COUNT"
    else
        REJECT_REASON=$(python3 -c "
import json
data = json.load(open('$VALIDATION_FILE'))
failures = [c['reason'] for c in data.get('checks', []) if c.get('result') == 'FAIL']
print('; '.join(failures[:3]))" 2>/dev/null || echo "validation failed")
        log "INFO" "Finding $FINDING_ID: REJECTED ($REJECT_REASON)"
        REJECTED=$((REJECTED + 1))
        add_summary_result "$FINDING_ID" "REJECTED" "$COMPOUND_SCORE" "$ENGINES_COUNT" "$REJECT_REASON"
    fi

    PROCESSED=$((PROCESSED + 1))
done < "$TMP_DIR/finding_ids.txt"

# ---------------------------------------------------------------------------
# Write stage2_summary.json
# ---------------------------------------------------------------------------

python3 - "$SUMMARY_FILE" "$OUTPUT_DIR/stage2_summary.json" "$PROCESSED" "$ACCEPTED" "$REJECTED" "$FAILED" "$SKIPPED" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

summary_file = sys.argv[1]
output_file = sys.argv[2]
processed, accepted, rejected, failed, skipped = (int(x) for x in sys.argv[3:8])

with open(summary_file) as f:
    reports = json.load(f)

summary = {
    "stage": "impact_analysis",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "findings_processed": processed,
    "accepted": accepted,
    "rejected": rejected,
    "failed": failed,
    "skipped": skipped,
    "reports": reports,
}

with open(output_file, 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
PYEOF

log "INFO" "Stage 2 completed — processed=$PROCESSED accepted=$ACCEPTED rejected=$REJECTED failed=$FAILED skipped=$SKIPPED"
log "INFO" "Summary written to $OUTPUT_DIR/stage2_summary.json"

# Exit success (individual finding failures don't fail the stage)
exit 0
