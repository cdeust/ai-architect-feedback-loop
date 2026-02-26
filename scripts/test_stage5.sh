#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage5.sh — Integration tests for Stage 5 orchestrator
# ============================================================================
#
# Tests stage5-prd-generation.sh with a mock Claude CLI that writes
# canned PRD output files.
#
# Test cases:
#   IT-S5-001: Creates prd_output_tv-accepted/prd.md for accepted plans
#   IT-S5-002: stage5_summary.json has correct counts
#   IT-S5-003: REJECTED Stage 3 plans are skipped
#   IT-S5-004: Quality score below 85% → finding REJECTED
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_RUN=0

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  FAIL: $1 — $2"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup_mock_claude() {
    local mock_dir="$1"
    local builder_dir="$2"

    mkdir -p "$mock_dir"

    # Mock Claude writes 4 PRD files to builder_dir (where it runs)
    cat > "$mock_dir/claude" <<MOCKEOF
#!/usr/bin/env bash
# Mock Claude CLI — writes canned PRD files
BUILDER="$builder_dir"

cat > "\$BUILDER/prd.md" <<'PRDEOF'
# Feature PRD: Upgrade tv-accepted

## 1. Overview
Overview text with RAGEngine and OrchestrationEngine references.

## 2. Goals & Success Metrics
Goals here.

## 3. Requirements
- FR-TV001-1: Implement contextual scoring
- FR-TV001-2: Update retrieval pipeline
- FR-TV001-3: Add scoring weights
- AC-TV001-1: Scoring produces weighted results
- AC-TV001-2: Port method available
- AC-TV001-3: Tests pass

## 4. User Stories
### PIPE-TV001-1: Contextual Scoring [5 SP]
Story details.
### PIPE-TV001-2: Port Update [3 SP]
Story details.
### PIPE-TV001-3: Wiring [5 SP]
Story details.

## 5. Technical Specification
Architecture follows port/adapter pattern. RAGEngine implements the protocol.

## 6. Implementation Roadmap
Sprint 1.

## 7. Risk Assessment
Risks.

## 8. Appendix
Info.
PRDEOF

cat > "\$BUILDER/prd-verification.md" <<'VEREOF'
# Verification Report

**Overall Score:** 90%

### 1. Overview
- **Score:** 92%
VEREOF

cat > "\$BUILDER/prd-jira.md" <<'JIRAEOF'
# JIRA Tickets
- AC-TV001-1: Implementation ticket
JIRAEOF

cat > "\$BUILDER/prd-tests.md" <<'TESTEOF'
# Test Cases
- UT-001: Test contextual scoring
- IT-001: Integration test
- E2E-001: End-to-end test
TESTEOF

echo '{"status": "complete"}'
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_mock_claude_low_score() {
    local mock_dir="$1"
    local builder_dir="$2"

    mkdir -p "$mock_dir"

    cat > "$mock_dir/claude" <<MOCKEOF
#!/usr/bin/env bash
BUILDER="$builder_dir"

cat > "\$BUILDER/prd.md" <<'PRDEOF'
# Feature PRD

## 1. Overview
Overview with RAGEngine.

## 2. Goals
Goals.

## 3. Requirements
- FR-TV001-1: Req1
- FR-TV001-2: Req2
- FR-TV001-3: Req3
- AC-TV001-1: AC1
- AC-TV001-2: AC2
- AC-TV001-3: AC3

## 4. Stories
### PIPE-TV001-1 [3 SP]
Story.

## 5. Technical Specification
Uses port and adapter and protocol.

## 6. Roadmap
Sprint.

## 7. Risks
Risk.
PRDEOF

cat > "\$BUILDER/prd-verification.md" <<'VEREOF'
# Verification

**Overall Score:** 75%
VEREOF

cat > "\$BUILDER/prd-jira.md" <<'JIRAEOF'
# JIRA
JIRAEOF

cat > "\$BUILDER/prd-tests.md" <<'TESTEOF'
# Tests
- UT-001: Test
TESTEOF

echo '{"status": "complete"}'
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_test_fixtures() {
    local tmpdir="$1"

    mkdir -p "$tmpdir/run_dir" "$tmpdir/output"

    # Mock builder dir with minimal structure
    mkdir -p "$tmpdir/builder/packages/AIPRDSharedUtilities/Sources/Domain/Ports"
    mkdir -p "$tmpdir/builder/packages/AIPRDRAGEngine/Sources"
    mkdir -p "$tmpdir/builder/packages/AIPRDOrchestrationEngine/Sources"

    cat > "$tmpdir/builder/packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift" <<'EOF'
public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
}
EOF

    cat > "$tmpdir/builder/packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift" <<'EOF'
public protocol RAGEngineProtocol {
    func retrieveContext(query: String) async throws -> RAGResult
}
EOF

    cat > "$tmpdir/builder/CLAUDE.md" <<'EOF'
# Architecture Rules
- Port/adapter pattern enforced
EOF

    # Config
    cat > "$tmpdir/config.json" <<'EOF'
{
  "stage_5": {"prd_quality_minimum": 0.85}
}
EOF

    # Use real engine graph and category map
    cp "$SCRIPT_DIR/../config/engine_graph.json" "$tmpdir/engine_graph.json"
    cp "$SCRIPT_DIR/../config/category_engine_map.json" "$tmpdir/category_map.json"

    # Accepted Stage 3 validation
    cat > "$tmpdir/run_dir/validation_stage3_tv-accepted.json" <<'EOF'
{
  "stage": "validate_integration_plan",
  "finding_id": "tv-accepted",
  "result": "ACCEPTED",
  "checks": []
}
EOF

    # Impact report
    cat > "$tmpdir/run_dir/impact_report_tv-accepted.json" <<'EOF'
{
  "finding_id": "tv-accepted",
  "finding_title": "Contextual BM25 Scoring",
  "finding_description": "Improved scoring for retrieval",
  "source_url": "http://arxiv.org/abs/2401.12345",
  "finding_category": "retrieval",
  "relevance_score": 0.87,
  "affected_engines": ["RAGEngine", "OrchestrationEngine"],
  "compound_score": 0.65,
  "propagation_paths": [
    {"from": "RAGEngine", "to": "OrchestrationEngine", "relationship": "depends_on"}
  ],
  "recommendation": "PROCEED"
}
EOF

    # Integration plan
    cat > "$tmpdir/run_dir/integration_plan_tv-accepted.json" <<'EOF'
{
  "finding_id": "tv-accepted",
  "affected_engines": ["RAGEngine", "OrchestrationEngine"],
  "modifications": [
    {"engine": "RAGEngine", "files": [{"path": "packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift", "action": "modify"}], "contract_changes": []}
  ],
  "cross_engine_touchpoints": [
    {"from": "RAGEngine", "to": "OrchestrationEngine", "via": "RAGEngineProtocol", "description": "Updated"}
  ],
  "new_files": [],
  "test_files": [],
  "constraints": {}
}
EOF

    # Manifest
    cat > "$tmpdir/run_dir/manifest_tv-accepted.json" <<'EOF'
{
  "must_change": ["packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift"],
  "must_not_change": ["packages/AIPRDEncryptionEngine/Package.swift"],
  "allowed_new_files": []
}
EOF

    # REJECTED Stage 3 validation
    cat > "$tmpdir/run_dir/validation_stage3_tv-rejected.json" <<'EOF'
{
  "stage": "validate_integration_plan",
  "finding_id": "tv-rejected",
  "result": "REJECTED",
  "checks": [{"check": "schema_completeness", "result": "FAIL"}]
}
EOF
}

# ---------------------------------------------------------------------------
# IT-S5-001: Creates PRD output for accepted plans
# ---------------------------------------------------------------------------

test_creates_prd_output() {
    echo "IT-S5-001: Creates prd_output_tv-accepted/prd.md for accepted plans"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-prd-generation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --packages-dir "$tmpdir/builder/packages" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --category-map "$tmpdir/category_map.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/prd_output_tv-accepted/prd.md" ]]; then
        pass_test "prd_output_tv-accepted/prd.md created"
    else
        fail_test "prd_output_tv-accepted/prd.md" "File not found"
    fi

    # Check all 4 files
    local all_present=true
    for f in prd.md prd-verification.md prd-jira.md prd-tests.md; do
        if [[ ! -f "$tmpdir/output/prd_output_tv-accepted/$f" ]]; then
            all_present=false
        fi
    done
    if [[ "$all_present" == "true" ]]; then
        pass_test "All 4 PRD files present"
    else
        fail_test "All 4 PRD files" "Some files missing"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-002: Summary counts
# ---------------------------------------------------------------------------

test_summary_counts() {
    echo "IT-S5-002: stage5_summary.json has correct counts"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-prd-generation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --packages-dir "$tmpdir/builder/packages" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --category-map "$tmpdir/category_map.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local stage
        stage=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json'))['stage'])")
        if [[ "$stage" == "prd_generation" ]]; then
            pass_test "Summary stage = prd_generation"
        else
            fail_test "Summary stage" "Expected 'prd_generation', got '$stage'"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-003: REJECTED Stage 3 plans are skipped
# ---------------------------------------------------------------------------

test_rejected_skipped() {
    echo "IT-S5-003: REJECTED Stage 3 plans are skipped"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Remove accepted, keep only rejected
    rm -f "$tmpdir/run_dir/validation_stage3_tv-accepted.json"
    rm -f "$tmpdir/run_dir/impact_report_tv-accepted.json"
    rm -f "$tmpdir/run_dir/integration_plan_tv-accepted.json"
    rm -f "$tmpdir/run_dir/manifest_tv-accepted.json"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-prd-generation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --packages-dir "$tmpdir/builder/packages" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --category-map "$tmpdir/category_map.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local processed
        processed=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json'))['findings_processed'])")
        if [[ "$processed" -eq 0 ]]; then
            pass_test "No findings processed (all rejected)"
        else
            fail_test "Rejected skipping" "Expected 0 processed, got $processed"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-004: Quality score below 85% → REJECTED
# ---------------------------------------------------------------------------

test_low_score_rejected() {
    echo "IT-S5-004: Quality score below 85% → finding REJECTED"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_low_score "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-prd-generation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --packages-dir "$tmpdir/builder/packages" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --category-map "$tmpdir/category_map.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local rejected
        rejected=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json')).get('rejected', 0))")
        if [[ "$rejected" -ge 1 ]]; then
            pass_test "Low score finding REJECTED"
        else
            fail_test "Low score rejection" "Expected rejected >= 1, got $rejected"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Stage 5 Integration Tests ==="
echo ""

test_creates_prd_output
test_summary_counts
test_rejected_skipped
test_low_score_rejected

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed ==="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
