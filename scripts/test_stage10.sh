#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage10.sh — Integration tests for Stage 10 Enforcement Gates
# ============================================================================
#
# Covers:
#   IT-005 (AC-E1-012): Gate 1 — prohibited pattern detection
#   IT-006 (AC-E1-012): Gate 1 — clean pass when no violations
#   IT-007 (AC-E1-012): Gate 1 — skips when no patterns file
#   IT-008 (AC-E1-013): Gate 2 — manifest compliance violations
#   IT-009 (AC-E1-013): Gate 2 — passes with no manifest
#   IT-010 (AC-E1-014): Gate 3 — orphan file detection
#   IT-011 (AC-E1-014): Gate 3 — no orphans when types referenced
#   IT-012 (AC-E1-015): Skip gate functionality (--skip-gate)
#   IT-013 (AC-E1-016): Report schema validation
#   IT-014 (AC-E1-017): Overall FAIL when any gate fails
#   IT-015 (AC-E1-017): Overall PASS when all gates pass
#   IT-016 (AC-E1-012): Structured log output
#
# Usage:
#   bash scripts/test_stage10.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE10_SCRIPT="$SCRIPT_DIR/stage10-gates.sh"

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

# Create a minimal builder dir with packages and library dirs, plus a git repo
make_builder_dir() {
    local dir="$1"
    mkdir -p "$dir/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities"
    mkdir -p "$dir/packages/AIPRDSharedUtilities/Tests"
    mkdir -p "$dir/library/Sources"
    mkdir -p "$dir/library/Tests"
    # Initialize a git repo so git-based gates work
    (cd "$dir" && git init -q && git config user.email "test@test.com" && git config user.name "Test")
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

make_patterns_file() {
    local file="$1"
    cat > "$file" <<'EOF'
TODO
FIXME
HACK
@_exported\s+import
\btypealias\b
EOF
}

# Create a Makefile in builder dir with stub targets for gates 4-6
make_builder_makefile() {
    local dir="$1"
    local build_exit="${2:-0}"
    local test_exit="${3:-0}"
    local dist_exit="${4:-0}"
    cat > "$dir/Makefile" <<EOF
.PHONY: build-library test-all distribute
build-library:
	@echo "Build OK"
	@exit $build_exit
test-all:
	@echo "Test Suite passed"
	@exit $test_exit
distribute:
	@echo "Distribution OK"
	@exit $dist_exit
EOF
}

# ---------------------------------------------------------------------------
# IT-005: Gate 1 — Prohibited Pattern Detection (violations found)
# ---------------------------------------------------------------------------

run_test "IT-005: Gate 1 detects prohibited patterns"

TMPDIR_005=$(mktemp -d)
BUILDER_005="$TMPDIR_005/builder"
RUN_DIR_005="$TMPDIR_005/runs/test"
CONFIG_005="$TMPDIR_005/config"
PATTERNS_005="$TMPDIR_005/patterns.txt"

make_builder_dir "$BUILDER_005"
mkdir -p "$RUN_DIR_005" "$CONFIG_005"
make_config "$CONFIG_005"
make_builder_makefile "$BUILDER_005"
make_patterns_file "$PATTERNS_005"

# Create a Swift file WITH prohibited patterns
cat > "$BUILDER_005/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/BadFile.swift" <<'SWIFT'
import Foundation

// TODO: Fix this later
public struct BadStruct {
    @_exported import CryptoKit
    public typealias Foo = String
}
SWIFT

# Create initial commit so git works
(cd "$BUILDER_005" && git add -A && git commit -q -m "initial")

# Run with skip on gates 4-6 (no real build needed)
EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_005" \
    --config "$CONFIG_005/thresholds.json" \
    --patterns "$PATTERNS_005" \
    --output "$RUN_DIR_005" \
    --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
    pass "Exit code non-zero when violations found"
else
    fail "Expected non-zero exit code when violations found, got 0"
fi

if [[ -f "$RUN_DIR_005/enforcement_report.json" ]]; then
    GATE1_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_005/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==1][0]; print(g['result'])")
    if [[ "$GATE1_RESULT" == "FAIL" ]]; then
        pass "Gate 1 result is FAIL when violations exist"
    else
        fail "Expected Gate 1 FAIL, got $GATE1_RESULT"
    fi

    VIOLATIONS=$(python3 -c "import json; r=json.load(open('$RUN_DIR_005/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==1][0]; print(g['details']['violations_found'])")
    if [[ "$VIOLATIONS" -gt 0 ]]; then
        pass "Violations count > 0 ($VIOLATIONS found)"
    else
        fail "Expected violations > 0, got $VIOLATIONS"
    fi
else
    fail "enforcement_report.json not created"
fi

rm -rf "$TMPDIR_005"

# ---------------------------------------------------------------------------
# IT-006: Gate 1 — Clean Pass (no violations)
# ---------------------------------------------------------------------------

run_test "IT-006: Gate 1 passes when no violations"

TMPDIR_006=$(mktemp -d)
BUILDER_006="$TMPDIR_006/builder"
RUN_DIR_006="$TMPDIR_006/runs/test"
CONFIG_006="$TMPDIR_006/config"
PATTERNS_006="$TMPDIR_006/patterns.txt"

make_builder_dir "$BUILDER_006"
mkdir -p "$RUN_DIR_006" "$CONFIG_006"
make_config "$CONFIG_006"
make_builder_makefile "$BUILDER_006"
make_patterns_file "$PATTERNS_006"

# Create a CLEAN Swift file (no prohibited patterns)
cat > "$BUILDER_006/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/CleanFile.swift" <<'SWIFT'
import Foundation

public struct CleanStruct {
    public let name: String
    public let value: Int
}
SWIFT

(cd "$BUILDER_006" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_006" \
    --config "$CONFIG_006/thresholds.json" \
    --patterns "$PATTERNS_006" \
    --output "$RUN_DIR_006" \
    --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when no violations"
else
    fail "Expected exit code 0, got $EXIT_CODE"
fi

GATE1_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_006/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==1][0]; print(g['result'])")
if [[ "$GATE1_RESULT" == "PASS" ]]; then
    pass "Gate 1 result is PASS when clean"
else
    fail "Expected Gate 1 PASS, got $GATE1_RESULT"
fi

rm -rf "$TMPDIR_006"

# ---------------------------------------------------------------------------
# IT-007: Gate 1 — No Patterns File
# ---------------------------------------------------------------------------

run_test "IT-007: Gate 1 skips when no patterns file"

TMPDIR_007=$(mktemp -d)
BUILDER_007="$TMPDIR_007/builder"
RUN_DIR_007="$TMPDIR_007/runs/test"

make_builder_dir "$BUILDER_007"
mkdir -p "$RUN_DIR_007"
make_builder_makefile "$BUILDER_007"
(cd "$BUILDER_007" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_007" \
    --output "$RUN_DIR_007" \
    --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when no patterns file"
else
    fail "Expected exit code 0 with no patterns file, got $EXIT_CODE"
fi

GATE1_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_007/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==1][0]; print(g['result'])")
if [[ "$GATE1_RESULT" == "SKIP" ]]; then
    pass "Gate 1 result is SKIP when no patterns file"
else
    fail "Expected Gate 1 SKIP, got $GATE1_RESULT"
fi

rm -rf "$TMPDIR_007"

# ---------------------------------------------------------------------------
# IT-008: Gate 2 — Manifest Compliance Violations
# ---------------------------------------------------------------------------

run_test "IT-008: Gate 2 detects manifest violations"

TMPDIR_008=$(mktemp -d)
BUILDER_008="$TMPDIR_008/builder"
RUN_DIR_008="$TMPDIR_008/runs/test"
MANIFEST_008="$TMPDIR_008/manifest.json"

make_builder_dir "$BUILDER_008"
mkdir -p "$RUN_DIR_008"
make_builder_makefile "$BUILDER_008"

# Create initial files and first commit
cat > "$BUILDER_008/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Original.swift" <<'SWIFT'
public struct Original {}
SWIFT
cat > "$BUILDER_008/library/Sources/Untouchable.swift" <<'SWIFT'
public struct Untouchable {}
SWIFT
(cd "$BUILDER_008" && git add -A && git commit -q -m "initial")

# Modify the untouchable file (violates not_advised_changes)
echo "// modified" >> "$BUILDER_008/library/Sources/Untouchable.swift"
(cd "$BUILDER_008" && git add -A && git commit -q -m "second")

# Create manifest: advised_changes a file that didn't change, not_advised_changes one that did
cat > "$MANIFEST_008" <<'JSON'
{
    "advised_changes": ["packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Original.swift"],
    "not_advised_changes": ["library/Sources/Untouchable.swift"]
}
JSON

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_008" \
    --output "$RUN_DIR_008" \
    --manifest "$MANIFEST_008" \
    --skip-gate 1 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
    pass "Exit code non-zero with manifest violations"
else
    fail "Expected non-zero exit code with manifest violations, got 0"
fi

GATE2_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_008/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==2][0]; print(g['result'])")
if [[ "$GATE2_RESULT" == "FAIL" ]]; then
    pass "Gate 2 result is FAIL with manifest violations"
else
    fail "Expected Gate 2 FAIL, got $GATE2_RESULT"
fi

rm -rf "$TMPDIR_008"

# ---------------------------------------------------------------------------
# IT-009: Gate 2 — No Manifest (pass by default)
# ---------------------------------------------------------------------------

run_test "IT-009: Gate 2 passes with no manifest"

TMPDIR_009=$(mktemp -d)
BUILDER_009="$TMPDIR_009/builder"
RUN_DIR_009="$TMPDIR_009/runs/test"

make_builder_dir "$BUILDER_009"
mkdir -p "$RUN_DIR_009"
make_builder_makefile "$BUILDER_009"
(cd "$BUILDER_009" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_009" \
    --output "$RUN_DIR_009" \
    --skip-gate 1 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when no manifest"
else
    fail "Expected exit code 0 with no manifest, got $EXIT_CODE"
fi

GATE2_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_009/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==2][0]; print(g['result'])")
if [[ "$GATE2_RESULT" == "PASS" ]]; then
    pass "Gate 2 result is PASS with no manifest"
else
    fail "Expected Gate 2 PASS, got $GATE2_RESULT"
fi

rm -rf "$TMPDIR_009"

# ---------------------------------------------------------------------------
# IT-010: Gate 3 — Orphan File Detection
# ---------------------------------------------------------------------------

run_test "IT-010: Gate 3 detects orphan files"

TMPDIR_010=$(mktemp -d)
BUILDER_010="$TMPDIR_010/builder"
RUN_DIR_010="$TMPDIR_010/runs/test"

make_builder_dir "$BUILDER_010"
mkdir -p "$RUN_DIR_010"
make_builder_makefile "$BUILDER_010"

# Create initial commit
cat > "$BUILDER_010/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Core.swift" <<'SWIFT'
public struct Core {
    public let name: String
}
SWIFT
(cd "$BUILDER_010" && git add -A && git commit -q -m "initial")

# Add a new file with a type that's NOT referenced anywhere else
cat > "$BUILDER_010/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/OrphanType.swift" <<'SWIFT'
public struct NobodyUsesThis {
    public let value: Int
}
SWIFT
(cd "$BUILDER_010" && git add -A && git commit -q -m "add orphan")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_010" \
    --output "$RUN_DIR_010" \
    --skip-gate 1 --skip-gate 2 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ -f "$RUN_DIR_010/enforcement_report.json" ]]; then
    GATE3_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_010/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==3][0]; print(g['result'])")
    ORPHAN_COUNT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_010/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==3][0]; print(g['details']['orphans_found'])")

    if [[ "$GATE3_RESULT" == "FAIL" ]]; then
        pass "Gate 3 result is FAIL when orphans exist"
    else
        fail "Expected Gate 3 FAIL, got $GATE3_RESULT"
    fi

    if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
        pass "Orphan count > 0 ($ORPHAN_COUNT found)"
    else
        fail "Expected orphan count > 0, got $ORPHAN_COUNT"
    fi
else
    fail "enforcement_report.json not created"
fi

rm -rf "$TMPDIR_010"

# ---------------------------------------------------------------------------
# IT-011: Gate 3 — No Orphans (referenced types)
# ---------------------------------------------------------------------------

run_test "IT-011: Gate 3 passes when types are referenced"

TMPDIR_011=$(mktemp -d)
BUILDER_011="$TMPDIR_011/builder"
RUN_DIR_011="$TMPDIR_011/runs/test"

make_builder_dir "$BUILDER_011"
mkdir -p "$RUN_DIR_011"
make_builder_makefile "$BUILDER_011"

# Create initial commit with a referencing file
cat > "$BUILDER_011/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Core.swift" <<'SWIFT'
public struct Core {
    public let name: String
}
SWIFT
(cd "$BUILDER_011" && git add -A && git commit -q -m "initial")

# Add a new file whose type IS referenced in Core.swift
cat > "$BUILDER_011/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/UsedType.swift" <<'SWIFT'
public struct UsedType {
    public let value: Int
}
SWIFT
# Update Core.swift to reference UsedType
cat > "$BUILDER_011/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Core.swift" <<'SWIFT'
public struct Core {
    public let name: String
    public let used: UsedType
}
SWIFT
(cd "$BUILDER_011" && git add -A && git commit -q -m "add used type")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_011" \
    --output "$RUN_DIR_011" \
    --skip-gate 1 --skip-gate 2 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ -f "$RUN_DIR_011/enforcement_report.json" ]]; then
    GATE3_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_011/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==3][0]; print(g['result'])")
    if [[ "$GATE3_RESULT" == "PASS" ]]; then
        pass "Gate 3 result is PASS when types are referenced"
    else
        fail "Expected Gate 3 PASS, got $GATE3_RESULT"
    fi
else
    fail "enforcement_report.json not created"
fi

rm -rf "$TMPDIR_011"

# ---------------------------------------------------------------------------
# IT-012: Skip Gate Functionality
# ---------------------------------------------------------------------------

run_test "IT-012: Skip gate functionality (--skip-gate)"

TMPDIR_012=$(mktemp -d)
BUILDER_012="$TMPDIR_012/builder"
RUN_DIR_012="$TMPDIR_012/runs/test"

make_builder_dir "$BUILDER_012"
mkdir -p "$RUN_DIR_012"
make_builder_makefile "$BUILDER_012"

cat > "$BUILDER_012/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/File.swift" <<'SWIFT'
public struct Example {}
SWIFT
(cd "$BUILDER_012" && git add -A && git commit -q -m "initial")

# Skip ALL gates
EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_012" \
    --output "$RUN_DIR_012" \
    --skip-gate 1 --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when all gates skipped"
else
    fail "Expected exit code 0 with all skipped, got $EXIT_CODE"
fi

# Verify all 6 gates are SKIP in report
SKIP_COUNT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_012/enforcement_report.json')); print(sum(1 for g in r['gates'] if g['result']=='SKIP'))")
if [[ "$SKIP_COUNT" -eq 6 ]]; then
    pass "All 6 gates marked as SKIP"
else
    fail "Expected 6 SKIP gates, got $SKIP_COUNT"
fi

GATE_COUNT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_012/enforcement_report.json')); print(len(r['gates']))")
if [[ "$GATE_COUNT" -eq 6 ]]; then
    pass "Report contains all 6 gate entries"
else
    fail "Expected 6 gate entries, got $GATE_COUNT"
fi

rm -rf "$TMPDIR_012"

# ---------------------------------------------------------------------------
# IT-013: Report Schema Validation
# ---------------------------------------------------------------------------

run_test "IT-013: Report schema has all required keys"

TMPDIR_013=$(mktemp -d)
BUILDER_013="$TMPDIR_013/builder"
RUN_DIR_013="$TMPDIR_013/runs/test"

make_builder_dir "$BUILDER_013"
mkdir -p "$RUN_DIR_013"
make_builder_makefile "$BUILDER_013"

cat > "$BUILDER_013/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/File.swift" <<'SWIFT'
public struct Example {}
SWIFT
(cd "$BUILDER_013" && git add -A && git commit -q -m "initial")

"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_013" \
    --output "$RUN_DIR_013" \
    --skip-gate 1 --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || true

python3 -c "
import json, sys
r = json.load(open('$RUN_DIR_013/enforcement_report.json'))

# Top-level keys
required_top = ['stage', 'timestamp', 'overall_result', 'gates']
missing_top = [k for k in required_top if k not in r]
if missing_top:
    print(f'Missing top-level keys: {missing_top}', file=sys.stderr)
    sys.exit(1)

# Gate entry keys
required_gate = ['gate', 'name', 'result', 'duration_seconds', 'details']
for g in r['gates']:
    missing_gate = [k for k in required_gate if k not in g]
    if missing_gate:
        print(f'Gate {g.get(\"gate\",\"?\")} missing keys: {missing_gate}', file=sys.stderr)
        sys.exit(1)

# Validate types
assert isinstance(r['overall_result'], str), 'overall_result not string'
assert r['overall_result'] in ('PASS', 'FAIL'), f'overall_result not PASS/FAIL: {r[\"overall_result\"]}'
assert isinstance(r['gates'], list), 'gates not list'
assert len(r['gates']) == 6, f'expected 6 gates, got {len(r[\"gates\"])}'
" && pass "Report schema has all required keys and valid types" || fail "Report schema validation failed"

rm -rf "$TMPDIR_013"

# ---------------------------------------------------------------------------
# IT-014: Overall FAIL when any gate fails
# ---------------------------------------------------------------------------

run_test "IT-014: Overall result is FAIL when any gate fails"

TMPDIR_014=$(mktemp -d)
BUILDER_014="$TMPDIR_014/builder"
RUN_DIR_014="$TMPDIR_014/runs/test"
PATTERNS_014="$TMPDIR_014/patterns.txt"

make_builder_dir "$BUILDER_014"
mkdir -p "$RUN_DIR_014"
make_builder_makefile "$BUILDER_014"
make_patterns_file "$PATTERNS_014"

# Swift file with a violation
cat > "$BUILDER_014/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Bad.swift" <<'SWIFT'
// FIXME: this is bad
public struct Bad {}
SWIFT
(cd "$BUILDER_014" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_014" \
    --output "$RUN_DIR_014" \
    --patterns "$PATTERNS_014" \
    --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

OVERALL=$(python3 -c "import json; print(json.load(open('$RUN_DIR_014/enforcement_report.json'))['overall_result'])")
if [[ "$OVERALL" == "FAIL" ]]; then
    pass "Overall result is FAIL when Gate 1 fails"
else
    fail "Expected overall FAIL, got $OVERALL"
fi

if [[ "$EXIT_CODE" -ne 0 ]]; then
    pass "Script exit code non-zero on overall FAIL"
else
    fail "Expected non-zero exit code on FAIL"
fi

rm -rf "$TMPDIR_014"

# ---------------------------------------------------------------------------
# IT-015: Overall PASS when all gates pass
# ---------------------------------------------------------------------------

run_test "IT-015: Overall result is PASS when all gates pass"

TMPDIR_015=$(mktemp -d)
BUILDER_015="$TMPDIR_015/builder"
RUN_DIR_015="$TMPDIR_015/runs/test"
PATTERNS_015="$TMPDIR_015/patterns.txt"

make_builder_dir "$BUILDER_015"
mkdir -p "$RUN_DIR_015"
make_builder_makefile "$BUILDER_015"
make_patterns_file "$PATTERNS_015"

# Clean Swift file
cat > "$BUILDER_015/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/Clean.swift" <<'SWIFT'
public struct Clean {
    public let value: Int
}
SWIFT
(cd "$BUILDER_015" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_015" \
    --output "$RUN_DIR_015" \
    --patterns "$PATTERNS_015" \
    --skip-gate 4 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

OVERALL=$(python3 -c "import json; print(json.load(open('$RUN_DIR_015/enforcement_report.json'))['overall_result'])")
if [[ "$OVERALL" == "PASS" ]]; then
    pass "Overall result is PASS when gates 1-3 pass"
else
    fail "Expected overall PASS, got $OVERALL"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Script exit code 0 on overall PASS"
else
    fail "Expected exit code 0 on PASS, got $EXIT_CODE"
fi

rm -rf "$TMPDIR_015"

# ---------------------------------------------------------------------------
# IT-016: Structured Log Output
# ---------------------------------------------------------------------------

run_test "IT-016: Structured JSON log output"

TMPDIR_016=$(mktemp -d)
BUILDER_016="$TMPDIR_016/builder"
RUN_DIR_016="$TMPDIR_016/runs/test"

make_builder_dir "$BUILDER_016"
mkdir -p "$RUN_DIR_016"
make_builder_makefile "$BUILDER_016"

cat > "$BUILDER_016/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/File.swift" <<'SWIFT'
public struct File {}
SWIFT
(cd "$BUILDER_016" && git add -A && git commit -q -m "initial")

LOG_OUTPUT=$("$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_016" \
    --output "$RUN_DIR_016" \
    --skip-gate 1 --skip-gate 2 --skip-gate 3 --skip-gate 4 --skip-gate 5 --skip-gate 6 2>&1)

# Check that log lines contain stage field
STAGE_LINES=$(echo "$LOG_OUTPUT" | grep '"stage"' | head -1)
if [[ -n "$STAGE_LINES" ]]; then
    pass "Log output contains stage field"
else
    fail "Log output missing stage field"
fi

# Check timestamp field
TIMESTAMP_LINES=$(echo "$LOG_OUTPUT" | grep '"timestamp"' | head -1)
if [[ -n "$TIMESTAMP_LINES" ]]; then
    pass "Log output contains timestamp field"
else
    fail "Log output missing timestamp field"
fi

# Check overall_result in log
RESULT_LOG=$(echo "$LOG_OUTPUT" | grep 'overall result')
if [[ -n "$RESULT_LOG" ]]; then
    pass "Log output contains overall result"
else
    fail "Log output missing overall result"
fi

# Verify structured log lines are valid JSON
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

rm -rf "$TMPDIR_016"

# ---------------------------------------------------------------------------
# IT-017: Gates 4-6 with stub Makefile (pass)
# ---------------------------------------------------------------------------

run_test "IT-017: Gates 4-6 pass with working builder Makefile"

TMPDIR_017=$(mktemp -d)
BUILDER_017="$TMPDIR_017/builder"
RUN_DIR_017="$TMPDIR_017/runs/test"

make_builder_dir "$BUILDER_017"
mkdir -p "$RUN_DIR_017"
make_builder_makefile "$BUILDER_017" 0 0 0  # all succeed

cat > "$BUILDER_017/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/File.swift" <<'SWIFT'
public struct File {}
SWIFT
(cd "$BUILDER_017" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_017" \
    --output "$RUN_DIR_017" \
    --skip-gate 1 --skip-gate 2 --skip-gate 3 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "Exit code 0 when gates 4-6 succeed"
else
    fail "Expected exit code 0, got $EXIT_CODE"
fi

# Check each gate result
for gate_num in 4 5 6; do
    GATE_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_017/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==$gate_num][0]; print(g['result'])")
    if [[ "$GATE_RESULT" == "PASS" ]]; then
        pass "Gate $gate_num result is PASS"
    else
        fail "Expected Gate $gate_num PASS, got $GATE_RESULT"
    fi
done

rm -rf "$TMPDIR_017"

# ---------------------------------------------------------------------------
# IT-018: Gate 4 failure propagates
# ---------------------------------------------------------------------------

run_test "IT-018: Gate 4 build failure propagates to overall FAIL"

TMPDIR_018=$(mktemp -d)
BUILDER_018="$TMPDIR_018/builder"
RUN_DIR_018="$TMPDIR_018/runs/test"

make_builder_dir "$BUILDER_018"
mkdir -p "$RUN_DIR_018"
make_builder_makefile "$BUILDER_018" 1 0 0  # build fails

cat > "$BUILDER_018/packages/AIPRDSharedUtilities/Sources/AIPRDSharedUtilities/File.swift" <<'SWIFT'
public struct File {}
SWIFT
(cd "$BUILDER_018" && git add -A && git commit -q -m "initial")

EXIT_CODE=0
"$STAGE10_SCRIPT" \
    --builder-dir "$BUILDER_018" \
    --output "$RUN_DIR_018" \
    --skip-gate 1 --skip-gate 2 --skip-gate 3 --skip-gate 5 --skip-gate 6 > /dev/null 2>&1 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
    pass "Exit code non-zero when build fails"
else
    fail "Expected non-zero exit code when build fails"
fi

GATE4_RESULT=$(python3 -c "import json; r=json.load(open('$RUN_DIR_018/enforcement_report.json')); g=[x for x in r['gates'] if x['gate']==4][0]; print(g['result'])")
if [[ "$GATE4_RESULT" == "FAIL" ]]; then
    pass "Gate 4 result is FAIL when build fails"
else
    fail "Expected Gate 4 FAIL, got $GATE4_RESULT"
fi

rm -rf "$TMPDIR_018"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Stage 10 Integration Tests: $TESTS_RUN run, $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "============================================"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
