#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_notify.sh — Tests for notify.sh
# ============================================================================
#
# Tests:
#   UT-E5-004: Notification from improvement report
#   UT-E5-005: Zero findings -> "product is healthy"
#   UT-E5-006: Mixed results (PRs + failures)
#   UT-E5-N01: Direct --message fallback
#
# Usage:
#   bash scripts/test_notify.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  FAIL: $1"
}

run_test() {
    echo ""
    echo "--- $1 ---"
}

# ---------------------------------------------------------------------------
# UT-E5-004: Notification from improvement report
# ---------------------------------------------------------------------------

run_test "UT-E5-004: Notification from improvement report"

TMPDIR_004=$(mktemp -d)
RUN_DIR_004="$TMPDIR_004/run"
mkdir -p "$RUN_DIR_004"

cat > "$RUN_DIR_004/improvement_report.json" <<'EOF'
{
    "findings_summary": {
        "total_found": 3,
        "prioritized": 3,
        "implemented": 2,
        "failed": 0,
        "prs_created": 2
    },
    "engines_improved": {
        "RAGEngine": {
            "findings": ["tv-001"],
            "ports_touched": ["EmbeddingGeneratorPort"],
            "pr_url": "https://github.com/test/repo/pull/42"
        },
        "OrchestrationEngine": {
            "findings": ["tv-003"],
            "ports_touched": ["ContextCompressorPort"],
            "pr_url": "https://github.com/test/repo/pull/43"
        }
    },
    "quality_impact": {
        "dimensions": {
            "completeness": {"baseline": 0.91, "current": 0.92, "delta": "+0.01"},
            "accuracy": {"baseline": 0.93, "current": 0.93, "delta": "0.00"}
        }
    },
    "pr_urls": ["https://github.com/test/repo/pull/42", "https://github.com/test/repo/pull/43"]
}
EOF

OUTPUT=$(bash "$NOTIFY_SCRIPT" --run-dir "$RUN_DIR_004" 2>&1) || true

if echo "$OUTPUT" | grep -q "RAGEngine"; then
    pass "Engine names included in notification"
else
    fail "Engine names not in notification"
fi

if echo "$OUTPUT" | grep -q "completeness"; then
    pass "Quality deltas included in notification"
else
    fail "Quality deltas not in notification"
fi

rm -rf "$TMPDIR_004"

# ---------------------------------------------------------------------------
# UT-E5-005: Zero findings -> "product is healthy"
# ---------------------------------------------------------------------------

run_test "UT-E5-005: Zero findings -> product is healthy"

TMPDIR_005=$(mktemp -d)
RUN_DIR_005="$TMPDIR_005/run"
mkdir -p "$RUN_DIR_005"

cat > "$RUN_DIR_005/improvement_report.json" <<'EOF'
{
    "findings_summary": {
        "total_found": 0,
        "prioritized": 0,
        "implemented": 0,
        "failed": 0,
        "prs_created": 0
    },
    "engines_improved": {},
    "quality_impact": {"dimensions": {}},
    "pr_urls": []
}
EOF

OUTPUT=$(bash "$NOTIFY_SCRIPT" --run-dir "$RUN_DIR_005" 2>&1) || true

if echo "$OUTPUT" | grep -qi "healthy"; then
    pass "Zero findings notification says 'healthy'"
else
    fail "Zero findings notification does not say 'healthy'"
fi

rm -rf "$TMPDIR_005"

# ---------------------------------------------------------------------------
# UT-E5-006: Mixed results (PRs + failures)
# ---------------------------------------------------------------------------

run_test "UT-E5-006: Mixed results (PRs + failures)"

TMPDIR_006=$(mktemp -d)
RUN_DIR_006="$TMPDIR_006/run"
mkdir -p "$RUN_DIR_006"

cat > "$RUN_DIR_006/improvement_report.json" <<'EOF'
{
    "findings_summary": {
        "total_found": 3,
        "prioritized": 3,
        "implemented": 2,
        "failed": 1,
        "prs_created": 2
    },
    "engines_improved": {
        "RAGEngine": {
            "findings": ["tv-001"],
            "ports_touched": ["EmbeddingGeneratorPort"],
            "pr_url": "https://github.com/test/repo/pull/42"
        }
    },
    "quality_impact": {
        "dimensions": {
            "completeness": {"baseline": 0.91, "current": 0.92, "delta": "+0.01"}
        }
    },
    "pr_urls": ["https://github.com/test/repo/pull/42"]
}
EOF

OUTPUT=$(bash "$NOTIFY_SCRIPT" --run-dir "$RUN_DIR_006" 2>&1) || true

if echo "$OUTPUT" | grep -q "2 PRs"; then
    pass "PR count in notification"
else
    fail "PR count not in notification"
fi

if echo "$OUTPUT" | grep -q "1 failure"; then
    pass "Failure count in notification"
else
    fail "Failure count not in notification"
fi

rm -rf "$TMPDIR_006"

# ---------------------------------------------------------------------------
# UT-E5-N01: Direct --message fallback
# ---------------------------------------------------------------------------

run_test "UT-E5-N01: Direct --message fallback"

OUTPUT=$(bash "$NOTIFY_SCRIPT" --message "Test pipeline message" 2>&1) || true

if echo "$OUTPUT" | grep -q "Test pipeline message"; then
    pass "Direct message passed through"
else
    fail "Direct message not passed through"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Notify Tests: $TESTS_RUN run, $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "============================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
