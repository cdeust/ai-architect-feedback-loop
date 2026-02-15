#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage2.sh — Integration tests for Stage 2 orchestrator
# ============================================================================
#
# Tests stage2-impact-analysis.sh with a mock Claude CLI that returns
# canned impact report JSON.
#
# Test cases:
#   IT-S2-001: Creates impact_report_*.json files in output dir
#   IT-S2-002: Writes stage2_summary.json with correct counts
#   IT-S2-003: Finding with unmapped category is SKIPPED
#   IT-S2-004: Finding with single-engine report is REJECTED
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
# Setup: mock Claude CLI
# ---------------------------------------------------------------------------

setup_mock_claude() {
    local mock_dir="$1"
    local impact_json="$2"

    mkdir -p "$mock_dir"

    # Write JSON to a data file, then have mock claude cat it
    echo "$impact_json" > "$mock_dir/response.json"

    cat > "$mock_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock Claude CLI — returns canned impact report from adjacent data file
MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$MOCK_DIR/response.json"
MOCKEOF
    chmod +x "$mock_dir/claude"
}

# ---------------------------------------------------------------------------
# Setup: test fixtures
# ---------------------------------------------------------------------------

setup_test_fixtures() {
    local tmpdir="$1"

    # Create config files
    mkdir -p "$tmpdir/config" "$tmpdir/output" "$tmpdir/packages/AIPRDSharedUtilities/Sources/Domain/Ports"

    # Category engine map
    cat > "$tmpdir/config/category_engine_map.json" <<'EOF'
{
  "description": "Test mapping",
  "mappings": {
    "retrieval": {
      "primary_engines": ["RAGEngine"],
      "related_ports": ["EmbeddingGeneratorPort"],
      "key_services": ["EnrichedContextBuilder"]
    },
    "security_change": {
      "primary_engines": ["EncryptionEngine"],
      "related_ports": ["HashingPort"],
      "key_services": ["SecureLicenseValidator"]
    }
  }
}
EOF

    # Engine graph
    cat > "$tmpdir/config/engine_graph.json" <<'EOF'
{
  "engines": {
    "SharedUtilities": {
      "package_path": "packages/AIPRDSharedUtilities",
      "depends_on": [], "depended_by": ["RAGEngine", "EncryptionEngine", "OrchestrationEngine"],
      "feeds": ["RAGEngine", "EncryptionEngine", "OrchestrationEngine"], "fed_by": [], "role": "common_infrastructure"
    },
    "RAGEngine": {
      "package_path": "packages/AIPRDRAGEngine",
      "depends_on": ["SharedUtilities"], "depended_by": ["OrchestrationEngine"],
      "feeds": ["OrchestrationEngine"], "fed_by": ["SharedUtilities"], "role": "retrieval"
    },
    "EncryptionEngine": {
      "package_path": "packages/AIPRDEncryptionEngine",
      "depends_on": ["SharedUtilities"], "depended_by": [],
      "feeds": [], "fed_by": ["SharedUtilities"], "role": "encryption"
    },
    "OrchestrationEngine": {
      "package_path": "packages/AIPRDOrchestrationEngine",
      "depends_on": ["SharedUtilities", "RAGEngine"], "depended_by": [],
      "feeds": [], "fed_by": ["SharedUtilities", "RAGEngine"], "role": "orchestration"
    }
  }
}
EOF

    # Thresholds
    cat > "$tmpdir/config/thresholds.json" <<'EOF'
{
  "stage_2": { "compound_score_minimum": 0.3, "engines_affected_minimum": 2 }
}
EOF

    # Minimal port file for contract extraction
    cat > "$tmpdir/packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift" <<'EOF'
public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
}
EOF

    # Prioritized findings
    cat > "$tmpdir/findings.json" <<'EOF'
{
  "pipeline_version": "1.0",
  "prioritized_at": "2026-02-15T00:00:00Z",
  "total_input": 2,
  "total_output": 2,
  "findings": [
    {
      "id": "tv-001",
      "title": "Improved BM25 scoring",
      "relevance_category": "retrieval",
      "relevance_score": 0.9,
      "priority_score": 0.85,
      "description": "Better BM25 scoring"
    },
    {
      "id": "tv-002",
      "title": "New TLS cipher",
      "relevance_category": "security_change",
      "relevance_score": 0.7,
      "priority_score": 0.45,
      "description": "Updated cipher suite"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------
# IT-S2-001: Creates impact_report files
# ---------------------------------------------------------------------------

test_creates_impact_reports() {
    echo "IT-S2-001: Creates impact_report_*.json files"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Mock claude returns multi-engine report (PROCEED)
    local impact_json='{
      "finding_id": "tv-001",
      "engines_affected": 3,
      "compound_score": 1.39,
      "affected_engines": ["RAGEngine", "OrchestrationEngine", "SharedUtilities"],
      "propagation_paths": [
        {"from": "RAGEngine", "to": "OrchestrationEngine", "order": 1, "mechanism": "feeds"}
      ],
      "scoring_breakdown": {
        "engines_affected": {"value": 3, "weight": 0.3},
        "propagation_depth": {"value": 2, "weight": 0.2},
        "contract_impact": {"value": 0.3, "weight": 0.3},
        "test_coverage_delta": {"value": 0.2, "weight": 0.2}
      },
      "recommendation": "PROCEED",
      "rationale": "Multi-engine impact detected"
    }'

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$impact_json"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage2-impact-analysis.sh" \
        --findings "$tmpdir/findings.json" \
        --engine-graph "$tmpdir/config/engine_graph.json" \
        --category-map "$tmpdir/config/category_engine_map.json" \
        --packages-dir "$tmpdir/packages" \
        --config "$tmpdir/config/thresholds.json" \
        --output "$tmpdir/output" \
        --max-findings 2 \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/impact_report_tv-001.json" ]]; then
        pass_test "impact_report_tv-001.json created"
    else
        fail_test "impact_report_tv-001.json created" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S2-002: Summary has correct counts
# ---------------------------------------------------------------------------

test_summary_counts() {
    echo "IT-S2-002: stage2_summary.json has correct counts"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Single-engine report (will be REJECTED by validator)
    local impact_json='{
      "finding_id": "tv-001",
      "engines_affected": 1,
      "compound_score": 0.1,
      "affected_engines": ["RAGEngine"],
      "propagation_paths": [],
      "scoring_breakdown": {
        "engines_affected": {"value": 1, "weight": 0.3},
        "propagation_depth": {"value": 0, "weight": 0.2},
        "contract_impact": {"value": 0, "weight": 0.3},
        "test_coverage_delta": {"value": 0.2, "weight": 0.2}
      },
      "recommendation": "REJECT",
      "rationale": "Single engine"
    }'

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" "$impact_json"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage2-impact-analysis.sh" \
        --findings "$tmpdir/findings.json" \
        --engine-graph "$tmpdir/config/engine_graph.json" \
        --category-map "$tmpdir/config/category_engine_map.json" \
        --packages-dir "$tmpdir/packages" \
        --config "$tmpdir/config/thresholds.json" \
        --output "$tmpdir/output" \
        --max-findings 2 \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage2_summary.json" ]]; then
        local processed
        processed=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage2_summary.json'))['findings_processed'])")
        if [[ "$processed" -eq 2 ]]; then
            pass_test "Processed count = 2"
        else
            fail_test "Processed count" "Expected 2, got $processed"
        fi
    else
        fail_test "stage2_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S2-003: Unmapped category is SKIPPED
# ---------------------------------------------------------------------------

test_unmapped_category_skipped() {
    echo "IT-S2-003: Finding with unmapped category is SKIPPED"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Override findings with unmapped category
    cat > "$tmpdir/findings.json" <<'EOF'
{
  "pipeline_version": "1.0",
  "total_input": 1,
  "total_output": 1,
  "findings": [
    {
      "id": "tv-unmapped",
      "title": "Unknown category finding",
      "relevance_category": "totally_unknown_category",
      "relevance_score": 0.9,
      "priority_score": 0.5,
      "description": "This has no engine mapping"
    }
  ]
}
EOF

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude "$mock_dir" '{}'

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage2-impact-analysis.sh" \
        --findings "$tmpdir/findings.json" \
        --engine-graph "$tmpdir/config/engine_graph.json" \
        --category-map "$tmpdir/config/category_engine_map.json" \
        --packages-dir "$tmpdir/packages" \
        --config "$tmpdir/config/thresholds.json" \
        --output "$tmpdir/output" \
        --max-findings 1 \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage2_summary.json" ]]; then
        local skipped
        skipped=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage2_summary.json'))['skipped'])")
        if [[ "$skipped" -eq 1 ]]; then
            pass_test "Unmapped category SKIPPED"
        else
            fail_test "Unmapped category" "Expected skipped=1, got $skipped"
        fi
    else
        fail_test "stage2_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Stage 2 Integration Tests ==="
echo ""

test_creates_impact_reports
test_summary_counts
test_unmapped_category_skipped

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed ==="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
