#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_launchd.sh — Tests for launchd plist
# ============================================================================
#
# Tests:
#   IT-E5-010: Plist valid XML (plutil -lint)
#   IT-E5-PL1: caffeinate in ProgramArguments
#
# Usage:
#   bash scripts/test_launchd.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$REPO_DIR/config/com.ai-architect.pipeline-feedback.plist"

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
# IT-E5-010: Plist valid XML
# ---------------------------------------------------------------------------

run_test "IT-E5-010: Plist valid XML (plutil -lint)"

if [[ ! -f "$PLIST" ]]; then
    fail "Plist file not found: $PLIST"
else
    if plutil -lint "$PLIST" > /dev/null 2>&1; then
        pass "Plist passes plutil -lint"
    else
        fail "Plist fails plutil -lint"
    fi
fi

# ---------------------------------------------------------------------------
# IT-E5-PL1: caffeinate in ProgramArguments
# ---------------------------------------------------------------------------

run_test "IT-E5-PL1: caffeinate in ProgramArguments"

if grep -q "caffeinate" "$PLIST"; then
    pass "caffeinate found in ProgramArguments"
else
    fail "caffeinate not found in plist"
fi

if grep -q "/usr/bin/caffeinate" "$PLIST"; then
    pass "Full path to caffeinate used"
else
    fail "caffeinate should use full path /usr/bin/caffeinate"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Launchd Tests: $TESTS_RUN run, $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "============================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
