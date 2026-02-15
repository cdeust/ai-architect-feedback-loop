#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage1.sh — Integration tests for Stage 1 Trigger & Parse Script
# ============================================================================
#
# Covers:
#   IT-001 (AC-E1-005): Creates timestamped run directory
#   IT-002 (AC-E1-006): Invokes parse_findings.py, writes findings.json to run dir
#   IT-003 (AC-E1-007): Exits cleanly with code 0 when 0 findings
#   IT-004 (AC-E1-006): Structured log output with stage, timestamp, findings count
#
# Usage:
#   bash scripts/test_stage1.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE1_SCRIPT="$SCRIPT_DIR/stage1-parse-findings.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $1"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "--- $1 ---"
}

make_tv_output() {
    local dir="$1"
    local findings="$2"
    cat > "$dir/tv_output.json" <<EOF
{"findings": $findings}
EOF
}

make_config() {
    local dir="$1"
    cat > "$dir/thresholds.json" <<'EOF'
{
  "stage_1": {
    "relevance_score_minimum": 0.5,
    "relevance_categories": [
      "api_change", "behavior_change", "dependency_change", "config_change",
      "schema_change", "performance_change", "security_change",
      "prompting", "retrieval", "verification", "embeddings",
      "inference", "cost_optimization", "benchmarks"
    ]
  }
}
EOF
}

# ---------------------------------------------------------------------------
# IT-001: Run Directory Creation (AC-E1-005)
# ---------------------------------------------------------------------------

run_test "IT-001: Run directory is used for output"

TMPDIR_001=$(mktemp -d)
BUILDER_001="$TMPDIR_001/builder"
RUN_DIR_001="$TMPDIR_001/runs/20260211-120000"
CONFIG_001="$TMPDIR_001/config"

mkdir -p "$BUILDER_001" "$RUN_DIR_001" "$CONFIG_001"
make_config "$CONFIG_001"
# No TV output — script should handle gracefully

"$STAGE1_SCRIPT" \
    --builder-dir "$BUILDER_001" \
    --config "$CONFIG_001/thresholds.json" \
    --output "$RUN_DIR_001" > /dev/null 2>&1

if [[ -d "$RUN_DIR_001" ]]; then
    pass "Run directory exists after execution"
else
    fail "Run directory missing after execution"
fi

if [[ -f "$RUN_DIR_001/findings.json" ]]; then
    pass "findings.json written to run directory"
else
    fail "findings.json not found in run directory"
fi

rm -rf "$TMPDIR_001"

# ---------------------------------------------------------------------------
# IT-002: Adapter Invocation & findings.json (AC-E1-006)
# ---------------------------------------------------------------------------

run_test "IT-002: Adapter invoked, findings.json written with correct data"

TMPDIR_002=$(mktemp -d)
BUILDER_002="$TMPDIR_002/builder"
RUN_DIR_002="$TMPDIR_002/runs/20260211-120100"
CONFIG_002="$TMPDIR_002/config"

mkdir -p "$BUILDER_002" "$RUN_DIR_002" "$CONFIG_002"
make_config "$CONFIG_002"
make_tv_output "$BUILDER_002" '[
    {"id":"f01","title":"RAG improvement","description":"desc","source_url":"https://ex.com","relevance_category":"retrieval","relevance_score":0.9,"raw_data":{}},
    {"id":"f02","title":"Low score","description":"desc","source_url":"https://ex.com","relevance_category":"retrieval","relevance_score":0.2,"raw_data":{}},
    {"id":"f03","title":"Prompt tuning","description":"desc","source_url":"https://ex.com","relevance_category":"prompting","relevance_score":0.7,"raw_data":{}}
]'

"$STAGE1_SCRIPT" \
    --builder-dir "$BUILDER_002" \
    --config "$CONFIG_002/thresholds.json" \
    --output "$RUN_DIR_002" > /dev/null 2>&1

if [[ -f "$RUN_DIR_002/findings.json" ]]; then
    pass "findings.json created"
else
    fail "findings.json not created"
    rm -rf "$TMPDIR_002"
    # Skip remaining checks for this test
    run_test "IT-003: Clean exit on zero findings"
    fail "Skipped (IT-002 prerequisite failed)"
    run_test "IT-004: Structured log output"
    fail "Skipped (IT-002 prerequisite failed)"
    echo ""
    echo "Results: $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED failed"
    exit 1
fi

# Validate JSON structure
FILTERED=$(python3 -c "import json; print(json.load(open('$RUN_DIR_002/findings.json'))['stats']['filtered_findings'])")
if [[ "$FILTERED" -eq 2 ]]; then
    pass "Filtered findings count correct (2 of 3 above threshold 0.5)"
else
    fail "Expected 2 filtered findings, got $FILTERED"
fi

TOTAL=$(python3 -c "import json; print(json.load(open('$RUN_DIR_002/findings.json'))['stats']['total_findings'])")
if [[ "$TOTAL" -eq 3 ]]; then
    pass "Total findings count correct (3)"
else
    fail "Expected 3 total findings, got $TOTAL"
fi

# Verify output has required schema keys
python3 -c "
import json, sys
d = json.load(open('$RUN_DIR_002/findings.json'))
required = ['pipeline_version', 'generated_at', 'source', 'threshold_used', 'findings', 'stats']
missing = [k for k in required if k not in d]
if missing:
    print(f'Missing keys: {missing}', file=sys.stderr)
    sys.exit(1)
" && pass "Output schema has all required keys" || fail "Output schema missing required keys"

rm -rf "$TMPDIR_002"

# ---------------------------------------------------------------------------
# IT-003: No-Findings Clean Exit (AC-E1-007)
# ---------------------------------------------------------------------------

run_test "IT-003: Clean exit (code 0) on zero findings"

TMPDIR_003=$(mktemp -d)
BUILDER_003="$TMPDIR_003/builder"
RUN_DIR_003="$TMPDIR_003/runs/20260211-120200"
CONFIG_003="$TMPDIR_003/config"

mkdir -p "$BUILDER_003" "$RUN_DIR_003" "$CONFIG_003"
make_config "$CONFIG_003"

# Case A: No TV output file at all
EXIT_CODE=0
"$STAGE1_SCRIPT" \
    --builder-dir "$BUILDER_003" \
    --config "$CONFIG_003/thresholds.json" \
    --output "$RUN_DIR_003" > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when no TV output file"
else
    fail "Expected exit code 0, got $EXIT_CODE when no TV output"
fi

# Check findings.json still written (empty)
if [[ -f "$RUN_DIR_003/findings.json" ]]; then
    EMPTY_COUNT=$(python3 -c "import json; print(json.load(open('$RUN_DIR_003/findings.json'))['stats']['filtered_findings'])")
    if [[ "$EMPTY_COUNT" -eq 0 ]]; then
        pass "Empty findings.json written (0 filtered findings)"
    else
        fail "Expected 0 filtered findings, got $EMPTY_COUNT"
    fi
else
    fail "findings.json not written when no TV output"
fi

# Case B: TV output with empty findings array
make_tv_output "$BUILDER_003" '[]'
RUN_DIR_003B="$TMPDIR_003/runs/20260211-120201"
mkdir -p "$RUN_DIR_003B"

EXIT_CODE=0
"$STAGE1_SCRIPT" \
    --builder-dir "$BUILDER_003" \
    --config "$CONFIG_003/thresholds.json" \
    --output "$RUN_DIR_003B" > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when TV output has empty findings"
else
    fail "Expected exit code 0 with empty findings, got $EXIT_CODE"
fi

rm -rf "$TMPDIR_003"

# ---------------------------------------------------------------------------
# IT-004: Structured Log Output (AC-E1-006)
# ---------------------------------------------------------------------------

run_test "IT-004: Structured JSON log output"

TMPDIR_004=$(mktemp -d)
BUILDER_004="$TMPDIR_004/builder"
RUN_DIR_004="$TMPDIR_004/runs/20260211-120300"
CONFIG_004="$TMPDIR_004/config"

mkdir -p "$BUILDER_004" "$RUN_DIR_004" "$CONFIG_004"
make_config "$CONFIG_004"
make_tv_output "$BUILDER_004" '[
    {"id":"f01","title":"Test","description":"d","source_url":"https://ex.com","relevance_category":"retrieval","relevance_score":0.9,"raw_data":{}}
]'

LOG_OUTPUT=$("$STAGE1_SCRIPT" \
    --builder-dir "$BUILDER_004" \
    --config "$CONFIG_004/thresholds.json" \
    --output "$RUN_DIR_004" 2>&1)

# Check that log lines are parseable JSON with required fields
STAGE_LINES=$(echo "$LOG_OUTPUT" | grep '"stage"' | head -1)
if [[ -n "$STAGE_LINES" ]]; then
    pass "Log output contains stage field"
else
    fail "Log output missing stage field"
fi

TIMESTAMP_LINES=$(echo "$LOG_OUTPUT" | grep '"timestamp"' | head -1)
if [[ -n "$TIMESTAMP_LINES" ]]; then
    pass "Log output contains timestamp field"
else
    fail "Log output missing timestamp field"
fi

FINDINGS_LOG=$(echo "$LOG_OUTPUT" | grep 'findings_count')
if [[ -n "$FINDINGS_LOG" ]]; then
    pass "Log output contains findings_count"
else
    fail "Log output missing findings_count"
fi

# Verify log lines are valid JSON (structured logging)
VALID_JSON=true
while IFS= read -r line; do
    if echo "$line" | grep -q '^{'; then
        python3 -c "import json; json.loads('''$line''')" 2>/dev/null || VALID_JSON=false
    fi
done <<< "$LOG_OUTPUT"

if [[ "$VALID_JSON" == "true" ]]; then
    pass "All structured log lines are valid JSON"
else
    fail "Some log lines are not valid JSON"
fi

rm -rf "$TMPDIR_004"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Stage 1 Integration Tests: $TESTS_RUN run, $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "============================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
