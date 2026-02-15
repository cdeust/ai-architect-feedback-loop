#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage8.sh — Integration tests for Stage 8 quality gate (compare mode)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    echo "  PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "  FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---------------------------------------------------------------------------
# Setup: create synthetic baselines and current metrics
# ---------------------------------------------------------------------------

setup_test_fixtures() {
    TEST_DIR=$(mktemp -d)
    BASELINES_DIR="$TEST_DIR/baselines"
    CURRENT_DIR="$TEST_DIR/current"
    OUTPUT_DIR="$TEST_DIR/output"

    mkdir -p "$BASELINES_DIR/test_bench" "$CURRENT_DIR/test_bench" "$OUTPUT_DIR"

    # Baseline metrics
    cat > "$BASELINES_DIR/test_bench/metrics.json" <<'EOF'
{
  "verification": {
    "overall_score": 0.93,
    "completeness": { "total_items": 88, "logged": 88, "missing": 0, "coverage": 1.0 }
  },
  "traceability": {
    "fr_to_ac_coverage": 1.0,
    "ac_to_test_coverage": 1.0,
    "cross_ref_integrity": 1.0
  }
}
EOF
}

cleanup() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# IT-S8-001: PASS when metrics match baselines
# ---------------------------------------------------------------------------

test_pass_on_maintained() {
    echo "IT-S8-001: PASS when all dimensions maintained"
    setup_test_fixtures

    # Current = same as baseline
    cp "$BASELINES_DIR/test_bench/metrics.json" "$CURRENT_DIR/test_bench/metrics.json"

    local exit_code=0
    "$SCRIPT_DIR/stage8-benchmark.sh" \
        --baselines "$BASELINES_DIR" \
        --current-dir "$CURRENT_DIR" \
        --output "$OUTPUT_DIR" \
        --mode compare > /dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        pass "Exit code 0"
    else
        fail "Expected exit code 0, got $exit_code"
    fi

    if [[ -f "$OUTPUT_DIR/benchmark_report.json" ]]; then
        local result
        result=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/benchmark_report.json'))['overall_result'])")
        if [[ "$result" == "PASS" ]]; then
            pass "Overall result is PASS"
        else
            fail "Expected PASS, got $result"
        fi
    else
        fail "benchmark_report.json not created"
    fi

    cleanup
}

# ---------------------------------------------------------------------------
# IT-S8-002: PASS when metrics improve
# ---------------------------------------------------------------------------

test_pass_on_improved() {
    echo "IT-S8-002: PASS when dimensions improve"
    setup_test_fixtures

    # Current = improved (delta must exceed threshold 0.05)
    cat > "$CURRENT_DIR/test_bench/metrics.json" <<'EOF'
{
  "verification": {
    "overall_score": 0.99,
    "completeness": { "total_items": 88, "logged": 88, "missing": 0, "coverage": 1.0 }
  },
  "traceability": {
    "fr_to_ac_coverage": 1.0,
    "ac_to_test_coverage": 1.0,
    "cross_ref_integrity": 1.0
  }
}
EOF

    local exit_code=0
    "$SCRIPT_DIR/stage8-benchmark.sh" \
        --baselines "$BASELINES_DIR" \
        --current-dir "$CURRENT_DIR" \
        --output "$OUTPUT_DIR" \
        --mode compare > /dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        pass "Exit code 0"
    else
        fail "Expected exit code 0, got $exit_code"
    fi

    if [[ -f "$OUTPUT_DIR/benchmark_report.json" ]]; then
        local improved
        improved=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/benchmark_report.json'))['summary']['improved'])")
        if [[ "$improved" -ge 1 ]]; then
            pass "At least 1 dimension improved"
        else
            fail "Expected >= 1 improved, got $improved"
        fi
    else
        fail "benchmark_report.json not created"
    fi

    cleanup
}

# ---------------------------------------------------------------------------
# IT-S8-003: FAIL when regression detected
# ---------------------------------------------------------------------------

test_fail_on_regression() {
    echo "IT-S8-003: FAIL when regression detected"
    setup_test_fixtures

    # Current = regressed (0.93 -> 0.80, delta = -0.13 > threshold 0.05)
    cat > "$CURRENT_DIR/test_bench/metrics.json" <<'EOF'
{
  "verification": {
    "overall_score": 0.80,
    "completeness": { "total_items": 88, "logged": 88, "missing": 0, "coverage": 1.0 }
  },
  "traceability": {
    "fr_to_ac_coverage": 1.0,
    "ac_to_test_coverage": 1.0,
    "cross_ref_integrity": 1.0
  }
}
EOF

    local exit_code=0
    "$SCRIPT_DIR/stage8-benchmark.sh" \
        --baselines "$BASELINES_DIR" \
        --current-dir "$CURRENT_DIR" \
        --output "$OUTPUT_DIR" \
        --mode compare > /dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "Exit code non-zero on regression"
    else
        fail "Expected non-zero exit code on regression"
    fi

    if [[ -f "$OUTPUT_DIR/benchmark_report.json" ]]; then
        local result
        result=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/benchmark_report.json'))['overall_result'])")
        if [[ "$result" == "FAIL" ]]; then
            pass "Overall result is FAIL"
        else
            fail "Expected FAIL, got $result"
        fi

        local regressed
        regressed=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/benchmark_report.json'))['summary']['regressed'])")
        if [[ "$regressed" -ge 1 ]]; then
            pass "At least 1 dimension regressed"
        else
            fail "Expected >= 1 regressed, got $regressed"
        fi

        # Verify the regression details show correct values
        local dim_result
        dim_result=$(python3 -c "
import json
r = json.load(open('$OUTPUT_DIR/benchmark_report.json'))
d = r['benchmarks'][0]['dimensions']['verification_score']
print(f\"{d['baseline']}|{d['current']}|{d['delta']}|{d['result']}\")
")
        if echo "$dim_result" | grep -q "REGRESSED"; then
            pass "Dimension shows REGRESSED with details"
        else
            fail "Expected REGRESSED in dimension details, got $dim_result"
        fi
    else
        fail "benchmark_report.json not created"
    fi

    cleanup
}

# ---------------------------------------------------------------------------
# IT-S8-004: Report schema validation
# ---------------------------------------------------------------------------

test_report_schema() {
    echo "IT-S8-004: Report schema has required fields"
    setup_test_fixtures

    cp "$BASELINES_DIR/test_bench/metrics.json" "$CURRENT_DIR/test_bench/metrics.json"

    "$SCRIPT_DIR/stage8-benchmark.sh" \
        --baselines "$BASELINES_DIR" \
        --current-dir "$CURRENT_DIR" \
        --output "$OUTPUT_DIR" \
        --mode compare > /dev/null 2>&1 || true

    if [[ -f "$OUTPUT_DIR/benchmark_report.json" ]]; then
        local valid
        valid=$(python3 -c "
import json, sys
r = json.load(open('$OUTPUT_DIR/benchmark_report.json'))
required = ['stage', 'timestamp', 'overall_result', 'mode', 'regression_threshold', 'benchmarks', 'summary']
missing = [k for k in required if k not in r]
if missing:
    print('MISSING: ' + ', '.join(missing))
    sys.exit(1)
summary_required = ['total_checks', 'improved', 'maintained', 'regressed']
missing_s = [k for k in summary_required if k not in r['summary']]
if missing_s:
    print('MISSING in summary: ' + ', '.join(missing_s))
    sys.exit(1)
print('OK')
")
        if [[ "$valid" == "OK" ]]; then
            pass "Report has all required fields"
        else
            fail "Report missing fields: $valid"
        fi
    else
        fail "benchmark_report.json not created"
    fi

    cleanup
}

# ---------------------------------------------------------------------------
# IT-S8-005: Missing baselines directory
# ---------------------------------------------------------------------------

test_missing_baselines() {
    echo "IT-S8-005: Error on missing baselines directory"

    local exit_code=0
    TEST_DIR=$(mktemp -d)
    "$SCRIPT_DIR/stage8-benchmark.sh" \
        --baselines "$TEST_DIR/nonexistent" \
        --current-dir "$TEST_DIR" \
        --output "$TEST_DIR/output" \
        --mode compare > /dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "Exit code non-zero on missing baselines"
    else
        fail "Expected non-zero exit code on missing baselines"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "========================================"
echo "Stage 8 Integration Tests"
echo "========================================"
echo ""

test_pass_on_maintained
echo ""
test_pass_on_improved
echo ""
test_fail_on_regression
echo ""
test_report_schema
echo ""
test_missing_baselines
echo ""

echo "========================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "========================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
