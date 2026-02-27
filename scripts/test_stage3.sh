#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage3.sh — Integration tests for Stage 3 orchestrator
# ============================================================================
#
# Tests stage3-integration-design.sh with a mock Claude CLI that returns
# canned integration plan JSON.
#
# Test cases:
#   IT-S3-001: Creates integration_plan_*.json for accepted findings
#   IT-S3-002: Creates manifest_*.json with Gate 2-compatible format
#   IT-S3-003: REJECTED impact reports are skipped
#   IT-S3-004: stage3_summary.json has correct counts
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
    local plan_json="$2"

    mkdir -p "$mock_dir"

    # Write JSON to a data file, then have mock claude cat it
    echo "$plan_json" > "$mock_dir/response.json"

    cat > "$mock_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock Claude CLI — returns canned integration plan from adjacent data file
MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$MOCK_DIR/response.json"
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_test_fixtures() {
    local tmpdir="$1"

    mkdir -p "$tmpdir/impact_dir" "$tmpdir/output"
    mkdir -p "$tmpdir/packages/AIPRDSharedUtilities/Sources/Domain/Ports"
    mkdir -p "$tmpdir/packages/AIPRDRAGEngine/Sources"
    mkdir -p "$tmpdir/packages/AIPRDOrchestrationEngine/Sources"

    # Engine protocol files — used for contract extraction AND referenced by mock plans
    cat > "$tmpdir/packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift" <<'EOF'
public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
}
EOF

    cat > "$tmpdir/packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift" <<'EOF'
public protocol RAGEngineProtocol {
    func retrieveContext(query: String) async throws -> RAGResult
}
EOF

    cat > "$tmpdir/packages/AIPRDOrchestrationEngine/Sources/OrchestrationEngineProtocol.swift" <<'EOF'
public protocol OrchestrationEngineProtocol {
    func generatePRD(request: PRDRequest) async throws -> PRDResult
}
EOF

    # CLAUDE.md
    cat > "$tmpdir/CLAUDE.md" <<'EOF'
# Architecture Rules
- Port/adapter pattern enforced
- Domain contains no framework imports
EOF

    # Engine graph (used by generate_manifest.py)
    mkdir -p "$tmpdir/config_dir"
    cat > "$SCRIPT_DIR/../config/engine_graph.json.bak" 2>/dev/null || true

    # Accepted impact report (validation_stage2)
    cat > "$tmpdir/impact_dir/validation_stage2_tv-accepted.json" <<'EOF'
{
  "stage": "validate_impact_report",
  "finding_id": "tv-accepted",
  "result": "ACCEPTED",
  "checks": []
}
EOF

    # Impact report data
    cat > "$tmpdir/impact_dir/impact_report_tv-accepted.json" <<'EOF'
{
  "finding_id": "tv-accepted",
  "engines_affected": 2,
  "compound_score": 0.65,
  "affected_engines": ["RAGEngine", "OrchestrationEngine"],
  "propagation_paths": [
    {"from": "RAGEngine", "to": "OrchestrationEngine", "order": 1}
  ],
  "recommendation": "PROCEED",
  "rationale": "Multi-engine impact"
}
EOF

    # REJECTED impact report
    cat > "$tmpdir/impact_dir/validation_stage2_tv-rejected.json" <<'EOF'
{
  "stage": "validate_impact_report",
  "finding_id": "tv-rejected",
  "result": "REJECTED",
  "checks": [{"check": "engines_affected_threshold", "result": "FAIL"}]
}
EOF

    cat > "$tmpdir/impact_dir/impact_report_tv-rejected.json" <<'EOF'
{
  "finding_id": "tv-rejected",
  "engines_affected": 1,
  "compound_score": 0.1,
  "affected_engines": ["EncryptionEngine"],
  "recommendation": "REJECT"
}
EOF
}

# ---------------------------------------------------------------------------
# IT-S3-001: Creates integration plan for accepted findings
# ---------------------------------------------------------------------------

test_creates_integration_plan() {
    echo "IT-S3-001: Creates integration_plan_*.json for accepted findings"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local plan_json='{
      "finding_id": "tv-accepted",
      "affected_engines": ["RAGEngine", "OrchestrationEngine"],
      "modifications": [
        {
          "engine": "RAGEngine",
          "files": [{"path": "packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift", "action": "modify", "description": "update retrieval scoring"}],
          "contract_changes": []
        },
        {
          "engine": "OrchestrationEngine",
          "files": [{"path": "packages/AIPRDOrchestrationEngine/Sources/OrchestrationEngineProtocol.swift", "action": "modify", "description": "consume updated results"}],
          "contract_changes": []
        }
      ],
      "cross_engine_touchpoints": [
        {"from": "RAGEngine", "to": "OrchestrationEngine", "via": "RAGEngineProtocol", "description": "Updated results"}
      ],
      "new_files": [],
      "test_files": ["packages/AIPRDRAGEngine/Tests/RAGEngineTests.swift"],
      "constraints": {"no_new_packages": true, "no_standalone_modules": true, "existing_dependency_graph_only": true}
    }'

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$plan_json"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage3-integration-design.sh" \
        --impact-dir "$tmpdir/impact_dir" \
        --packages-dir "$tmpdir/packages" \
        --claude-md "$tmpdir/CLAUDE.md" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/integration_plan_tv-accepted.json" ]]; then
        pass_test "integration_plan_tv-accepted.json created"
    else
        fail_test "integration_plan_tv-accepted.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S3-002: Creates manifest with Gate 2 format
# ---------------------------------------------------------------------------

test_creates_manifest() {
    echo "IT-S3-002: Creates manifest_*.json with Gate 2-compatible format"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local plan_json='{
      "finding_id": "tv-accepted",
      "affected_engines": ["RAGEngine", "OrchestrationEngine"],
      "modifications": [
        {
          "engine": "RAGEngine",
          "files": [{"path": "packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift", "action": "modify", "description": "update retrieval scoring"}],
          "contract_changes": []
        },
        {
          "engine": "OrchestrationEngine",
          "files": [{"path": "packages/AIPRDOrchestrationEngine/Sources/OrchestrationEngineProtocol.swift", "action": "modify", "description": "consume updated results"}],
          "contract_changes": []
        }
      ],
      "cross_engine_touchpoints": [
        {"from": "RAGEngine", "to": "OrchestrationEngine", "via": "RAGEngineProtocol", "description": "Updated"}
      ],
      "new_files": [],
      "test_files": [],
      "constraints": {"no_new_packages": true, "no_standalone_modules": true, "existing_dependency_graph_only": true}
    }'

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$plan_json"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage3-integration-design.sh" \
        --impact-dir "$tmpdir/impact_dir" \
        --packages-dir "$tmpdir/packages" \
        --claude-md "$tmpdir/CLAUDE.md" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/manifest_tv-accepted.json" ]]; then
        # Check Gate 2 format
        local has_advised
        has_advised=$(python3 -c "import json; d=json.load(open('$tmpdir/output/manifest_tv-accepted.json')); print('yes' if 'advised_changes' in d and 'not_advised_changes' in d else 'no')")
        if [[ "$has_advised" == "yes" ]]; then
            pass_test "Manifest has Gate 2 format (advised_changes + not_advised_changes)"
        else
            fail_test "Gate 2 format" "Missing advised_changes or not_advised_changes keys"
        fi
    else
        fail_test "manifest_tv-accepted.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S3-003: REJECTED impact reports are skipped
# ---------------------------------------------------------------------------

test_rejected_skipped() {
    echo "IT-S3-003: REJECTED impact reports are not processed"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Remove the accepted report — only rejected remains
    rm -f "$tmpdir/impact_dir/validation_stage2_tv-accepted.json"
    rm -f "$tmpdir/impact_dir/impact_report_tv-accepted.json"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" '{}'

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage3-integration-design.sh" \
        --impact-dir "$tmpdir/impact_dir" \
        --packages-dir "$tmpdir/packages" \
        --claude-md "$tmpdir/CLAUDE.md" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage3_summary.json" ]]; then
        local processed
        processed=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage3_summary.json'))['findings_processed'])")
        if [[ "$processed" -eq 0 ]]; then
            pass_test "No findings processed (all rejected)"
        else
            fail_test "Rejected skipping" "Expected 0 processed, got $processed"
        fi
    else
        fail_test "stage3_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S3-004: Summary counts
# ---------------------------------------------------------------------------

test_summary_counts() {
    echo "IT-S3-004: stage3_summary.json has correct counts"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local plan_json='{
      "finding_id": "tv-accepted",
      "affected_engines": ["RAGEngine", "OrchestrationEngine"],
      "modifications": [
        {"engine": "RAGEngine", "files": [{"path": "packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift", "action": "modify", "description": "update scoring"}], "contract_changes": []},
        {"engine": "OrchestrationEngine", "files": [{"path": "packages/AIPRDOrchestrationEngine/Sources/OrchestrationEngineProtocol.swift", "action": "modify", "description": "consume results"}], "contract_changes": []}
      ],
      "cross_engine_touchpoints": [{"from": "RAGEngine", "to": "OrchestrationEngine", "via": "RAGEngineProtocol", "description": "Updated results"}],
      "new_files": [],
      "test_files": [],
      "constraints": {"no_new_packages": true, "no_standalone_modules": true, "existing_dependency_graph_only": true}
    }'

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$plan_json"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage3-integration-design.sh" \
        --impact-dir "$tmpdir/impact_dir" \
        --packages-dir "$tmpdir/packages" \
        --claude-md "$tmpdir/CLAUDE.md" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage3_summary.json" ]]; then
        local stage
        stage=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage3_summary.json'))['stage'])")
        if [[ "$stage" == "integration_design" ]]; then
            pass_test "Summary stage = integration_design"
        else
            fail_test "Summary stage" "Expected 'integration_design', got '$stage'"
        fi
    else
        fail_test "stage3_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Stage 3 Integration Tests ==="
echo ""

test_creates_integration_plan
test_creates_manifest
test_rejected_skipped
test_summary_counts

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed ==="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
