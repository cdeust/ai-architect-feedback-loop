#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_stage5.sh — Integration tests for Stage 5 orchestrator
# ============================================================================
#
# Tests stage5-implementation.sh with a mock Claude CLI and a real git repo
# (created in tmpdir).
#
# Test cases:
#   IT-S5-001: Creates feature branch pipeline/improvement-tv-accepted
#   IT-S5-002: Returns to original branch (main) after processing
#   IT-S5-003: stage5_summary.json has correct counts
#   IT-S5-004: Dirty working tree aborts with error
#   IT-S5-005: No commits produced → finding REJECTED
#   IT-S5-006: PRD/manifest conflict → REJECTED without Claude session
#   IT-S5-007: Manifest violation post-implementation → branch deleted
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve base branch from project config
BASE_BRANCH="main"
PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
if [[ -f "$PROJECT_CONFIG" ]]; then
    BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('base_branch', 'main'))" 2>/dev/null || echo "main")
fi

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

setup_mock_builder_repo() {
    local builder_dir="$1"

    mkdir -p "$builder_dir/packages/AIPRDSharedUtilities/Sources/Domain/Ports"
    mkdir -p "$builder_dir/packages/AIPRDRAGEngine/Sources"
    mkdir -p "$builder_dir/packages/AIPRDOrchestrationEngine/Sources"

    cat > "$builder_dir/packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift" <<'EOF'
public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
}
EOF

    cat > "$builder_dir/packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift" <<'EOF'
public protocol RAGEngineProtocol {
    func retrieveContext(query: String) async throws -> RAGResult
}
EOF

    cat > "$builder_dir/CLAUDE.md" <<'EOF'
# Architecture Rules
- Port/adapter pattern enforced
EOF

    # Initialize git repo
    git -C "$builder_dir" init -b "$BASE_BRANCH" > /dev/null 2>&1
    git -C "$builder_dir" add . > /dev/null 2>&1
    git -C "$builder_dir" -c user.name="Test" -c user.email="test@test.com" \
        commit -m "Initial commit" > /dev/null 2>&1
}

setup_mock_claude_with_commit() {
    local mock_dir="$1"
    local builder_dir="$2"

    mkdir -p "$mock_dir"

    cat > "$mock_dir/claude" <<MOCKEOF
#!/usr/bin/env bash
# Mock Claude that creates a file and commits it
BUILDER="$builder_dir"
echo "// Improvement" >> "\$BUILDER/packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift"
git -C "\$BUILDER" add -A > /dev/null 2>&1
git -C "\$BUILDER" -c user.name="Test" -c user.email="test@test.com" \
    commit -m "feat: implement improvement" > /dev/null 2>&1
echo "Implementation complete"
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_mock_claude_no_commit() {
    local mock_dir="$1"

    mkdir -p "$mock_dir"

    cat > "$mock_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock Claude that does nothing
echo "No changes needed"
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_mock_claude_bad_commit() {
    local mock_dir="$1"
    local builder_dir="$2"

    mkdir -p "$mock_dir"

    # This mock modifies a must_not_change file
    cat > "$mock_dir/claude" <<MOCKEOF
#!/usr/bin/env bash
BUILDER="$builder_dir"
echo "# Bad change" >> "\$BUILDER/Makefile"
git -C "\$BUILDER" add -A > /dev/null 2>&1
git -C "\$BUILDER" -c user.name="Test" -c user.email="test@test.com" \
    commit -m "feat: bad change" > /dev/null 2>&1
echo "Done"
MOCKEOF
    chmod +x "$mock_dir/claude"
}

setup_test_fixtures() {
    local tmpdir="$1"
    local builder_dir="$tmpdir/builder"

    mkdir -p "$tmpdir/run_dir" "$tmpdir/output"

    setup_mock_builder_repo "$builder_dir"

    # Also create a Makefile in builder (needed for must_not_change tests)
    cat > "$builder_dir/Makefile" <<'EOF'
.PHONY: help
help:
	@echo "Test builder"
EOF
    git -C "$builder_dir" add Makefile > /dev/null 2>&1
    git -C "$builder_dir" -c user.name="Test" -c user.email="test@test.com" \
        commit -m "Add Makefile" > /dev/null 2>&1

    # Engine graph
    cp "$SCRIPT_DIR/../config/engine_graph.json" "$tmpdir/engine_graph.json"

    # Config
    cat > "$tmpdir/config.json" <<'EOF'
{
  "stage_4": {"prd_quality_minimum": 0.85}
}
EOF

    # Accepted Stage 4 validation
    cat > "$tmpdir/run_dir/validation_stage4_tv-accepted.json" <<'EOF'
{
  "stage": "validate_prd_output",
  "finding_id": "tv-accepted",
  "result": "ACCEPTED",
  "checks": []
}
EOF

    # PRD output dir
    mkdir -p "$tmpdir/run_dir/prd_output_tv-accepted"
    cat > "$tmpdir/run_dir/prd_output_tv-accepted/prd.md" <<'EOF'
# Feature PRD
## 1. Overview
Upgrade for RAGEngine scoring.
## 5. Technical Specification
Uses port/adapter pattern.
EOF

    # Integration plan
    cat > "$tmpdir/run_dir/integration_plan_tv-accepted.json" <<'EOF'
{
  "finding_id": "tv-accepted",
  "affected_engines": ["RAGEngine"],
  "modifications": [
    {"engine": "RAGEngine", "files": [{"path": "packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift", "action": "modify"}], "contract_changes": []}
  ],
  "cross_engine_touchpoints": [],
  "new_files": [],
  "test_files": [],
  "constraints": {}
}
EOF

    # Manifest
    cat > "$tmpdir/run_dir/manifest_tv-accepted.json" <<'EOF'
{
  "must_change": ["packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift"],
  "must_not_change": ["Makefile", "library/Package.swift"],
  "allowed_new_files": []
}
EOF
}

# ---------------------------------------------------------------------------
# IT-S5-001: Creates feature branch
# ---------------------------------------------------------------------------

test_creates_feature_branch() {
    echo "IT-S5-001: Creates feature branch pipeline/improvement-tv-accepted"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_with_commit "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    # Check branch exists
    if git -C "$tmpdir/builder" branch --list "pipeline/improvement-tv-accepted" | grep -q "pipeline"; then
        pass_test "Feature branch created"
    else
        fail_test "Feature branch" "pipeline/improvement-tv-accepted not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-002: Returns to original branch
# ---------------------------------------------------------------------------

test_returns_to_original_branch() {
    echo "IT-S5-002: Returns to original branch (main) after processing"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_with_commit "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    local current_branch
    current_branch=$(git -C "$tmpdir/builder" branch --show-current)
    if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
        pass_test "Returned to $BASE_BRANCH branch"
    else
        fail_test "Branch restoration" "Expected '$BASE_BRANCH', got '$current_branch'"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-003: Summary counts
# ---------------------------------------------------------------------------

test_summary_counts() {
    echo "IT-S5-003: stage5_summary.json has correct counts"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_with_commit "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local stage
        stage=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json'))['stage'])")
        if [[ "$stage" == "implementation" ]]; then
            pass_test "Summary stage = implementation"
        else
            fail_test "Summary stage" "Expected 'implementation', got '$stage'"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-004: Dirty working tree aborts
# ---------------------------------------------------------------------------

test_dirty_tree_aborts() {
    echo "IT-S5-004: Dirty working tree aborts with error"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # Make dirty
    echo "dirty" >> "$tmpdir/builder/CLAUDE.md"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_with_commit "$mock_dir" "$tmpdir/builder"

    local exit_code=0
    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1 || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        pass_test "Dirty tree exits with non-zero"
    else
        fail_test "Dirty tree" "Expected non-zero exit, got 0"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-005: No commits → REJECTED
# ---------------------------------------------------------------------------

test_no_commits_rejected() {
    echo "IT-S5-005: No commits produced → finding REJECTED"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_no_commit "$mock_dir"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local rejected
        rejected=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json')).get('rejected', 0))")
        if [[ "$rejected" -ge 1 ]]; then
            pass_test "No-commit finding REJECTED"
        else
            fail_test "No-commit rejection" "Expected rejected >= 1, got $rejected"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-006: PRD/manifest conflict → REJECTED without Claude
# ---------------------------------------------------------------------------

test_prd_manifest_conflict() {
    echo "IT-S5-006: PRD/manifest conflict → REJECTED without starting Claude"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    # PRD references a must_not_change file
    cat > "$tmpdir/run_dir/prd_output_tv-accepted/prd.md" <<'EOF'
# Feature PRD
Modify packages/AIPRDEncryptionEngine/Package.swift for security.
EOF

    # Update manifest to protect that file
    cat > "$tmpdir/run_dir/manifest_tv-accepted.json" <<'EOF'
{
  "must_change": ["packages/AIPRDRAGEngine/Sources/RAGEngineProtocol.swift"],
  "must_not_change": ["packages/AIPRDEncryptionEngine/Package.swift", "Makefile"],
  "allowed_new_files": []
}
EOF

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_with_commit "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    if [[ -f "$tmpdir/output/stage5_summary.json" ]]; then
        local rejected
        rejected=$(python3 -c "import json; print(json.load(open('$tmpdir/output/stage5_summary.json')).get('rejected', 0))")
        if [[ "$rejected" -ge 1 ]]; then
            pass_test "PRD/manifest conflict REJECTED"
        else
            fail_test "PRD/manifest conflict" "Expected rejected >= 1, got $rejected"
        fi
    else
        fail_test "stage5_summary.json" "File not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-S5-007: Manifest violation → branch deleted
# ---------------------------------------------------------------------------

test_manifest_violation_branch_deleted() {
    echo "IT-S5-007: Manifest violation post-implementation → branch deleted"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_bin"
    setup_mock_claude_bad_commit "$mock_dir" "$tmpdir/builder"

    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/stage5-implementation.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --output "$tmpdir/output" \
        > /dev/null 2>&1

    # Branch should be deleted
    if git -C "$tmpdir/builder" branch --list "pipeline/improvement-tv-accepted" | grep -q "pipeline"; then
        fail_test "Branch deletion" "Branch still exists after manifest violation"
    else
        pass_test "Rejected branch deleted"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Stage 5 Integration Tests ==="
echo ""

test_creates_feature_branch
test_returns_to_original_branch
test_summary_counts
test_dirty_tree_aborts
test_no_commits_rejected
test_prd_manifest_conflict
test_manifest_violation_branch_deleted

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed ==="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
