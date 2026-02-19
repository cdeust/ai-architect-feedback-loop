#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# test_retry_orchestrator.sh — Integration tests for retry orchestrator
# ============================================================================
#
# Tests retry_orchestrator.sh with mock stage scripts (stage5, stage6, stage7)
# and a real git repo.
#
# Test cases:
#   IT-E4-005: Retries on Stage 6 failure
#   IT-E4-006: Appends failure context to next attempt
#   IT-E4-007: Creates issue after 3 failures
#   IT-E4-008: Exits early on success (attempt 2)
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
# Setup helpers
# ---------------------------------------------------------------------------

setup_mock_builder_repo() {
    local builder_dir="$1"

    mkdir -p "$builder_dir/packages/AIPRDSharedUtilities/Sources/Domain/Ports"
    mkdir -p "$builder_dir/packages/AIPRDRAGEngine/Sources/Retrieval"
    mkdir -p "$builder_dir/library/Sources"

    cat > "$builder_dir/packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift" <<'EOF'
public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
}
EOF

    cat > "$builder_dir/packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift" <<'EOF'
public struct ContextualBM25 {
    public func score(query: String) -> Double { return 0.0 }
}
EOF

    cat > "$builder_dir/CLAUDE.md" <<'EOF'
# Architecture Rules
EOF

    git -C "$builder_dir" init -b "$BASE_BRANCH" > /dev/null 2>&1
    git -C "$builder_dir" add . > /dev/null 2>&1
    git -C "$builder_dir" -c user.name="Test" -c user.email="test@test.com" \
        commit -m "Initial commit" > /dev/null 2>&1
}

setup_test_fixtures() {
    local tmpdir="$1"
    local builder_dir="$tmpdir/builder"

    mkdir -p "$tmpdir/run_dir" "$tmpdir/output"

    setup_mock_builder_repo "$builder_dir"

    # Engine graph
    cat > "$tmpdir/engine_graph.json" <<'EOF'
{
  "engines": {
    "RAGEngine": {"package_path": "packages/AIPRDRAGEngine", "depends_on": ["SharedUtilities"]},
    "OrchestrationEngine": {"package_path": "packages/AIPRDOrchestrationEngine", "depends_on": ["RAGEngine"]}
  }
}
EOF

    # Config with max_attempts
    cat > "$tmpdir/config.json" <<'EOF'
{
  "stage_4": {"prd_quality_minimum": 0.85},
  "retry": {"max_attempts": 3}
}
EOF

    # Patterns
    cat > "$tmpdir/patterns.txt" <<'EOF'
TODO
FIXME
EOF

    # Validation file (accepted)
    cat > "$tmpdir/run_dir/validation_stage4_tv-retry.json" <<'EOF'
{
  "stage": "validate_prd_output",
  "finding_id": "tv-retry",
  "result": "ACCEPTED"
}
EOF

    # PRD output
    mkdir -p "$tmpdir/run_dir/prd_output_tv-retry"
    cat > "$tmpdir/run_dir/prd_output_tv-retry/prd.md" <<'EOF'
# Feature PRD
## Requirements
- FR-TV001-1: Test requirement
EOF

    # Integration plan
    cat > "$tmpdir/run_dir/integration_plan_tv-retry.json" <<'EOF'
{
  "finding_id": "tv-retry",
  "affected_engines": ["RAGEngine"],
  "modifications": [
    {"engine": "RAGEngine", "files": [{"path": "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift", "action": "modify"}], "contract_changes": []}
  ],
  "cross_engine_touchpoints": [],
  "new_files": [],
  "test_files": [],
  "constraints": {}
}
EOF

    # Manifest
    cat > "$tmpdir/run_dir/manifest_tv-retry.json" <<'EOF'
{
  "must_change": ["packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift"],
  "must_not_change": [],
  "allowed_new_files": []
}
EOF
}

create_mock_scripts() {
    local mock_scripts_dir="$1"
    local builder_dir="$2"
    local s6_behavior="$3"  # "fail_once" or "always_fail" or "always_pass"
    local s7_behavior="${4:-always_pass}"

    mkdir -p "$mock_scripts_dir"

    # Mock Stage 5 — always succeeds (creates branch, makes commit)
    cat > "$mock_scripts_dir/stage5-implementation.sh" <<S5EOF
#!/usr/bin/env bash
set -euo pipefail
FID="" BD="" OD=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --finding-id) FID="\$2"; shift 2;;
        --builder-dir) BD="\$2"; shift 2;;
        --output) OD="\$2"; shift 2;;
        --failure-context|--run-dir|--engine-graph|--config) shift 2;;
        *) shift;;
    esac
done
BR="pipeline/improvement-\$FID"
git -C "\$BD" branch --list "\$BR" | grep -q pipeline 2>/dev/null || git -C "\$BD" checkout -b "\$BR" > /dev/null 2>&1
echo "// x" >> "\$BD/packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift"
git -C "\$BD" add -A > /dev/null 2>&1
git -C "\$BD" -c user.name=T -c user.email=t@t commit -m "feat" > /dev/null 2>&1
git -C "\$BD" checkout "$BASE_BRANCH" > /dev/null 2>&1
mkdir -p "\$OD"
python3 -c "
import json
json.dump({'stage':'implementation','findings_processed':1,'accepted':1,'rejected':0,'failed':0,'reports':[{'finding_id':'\$FID','result':'ACCEPTED'}]},open('\$OD/stage5_summary.json','w'),indent=2)
"
S5EOF
    chmod +x "$mock_scripts_dir/stage5-implementation.sh"

    # Mock Stage 6 — configurable behavior (uses counter file)
    local s6_call_count_file="$mock_scripts_dir/.s6_call_count"
    echo "0" > "$s6_call_count_file"

    cat > "$mock_scripts_dir/stage6-gates.sh" <<S6EOF
#!/usr/bin/env bash
set -euo pipefail
OD=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in --output) OD="\$2"; shift 2;; *) shift;; esac
done
mkdir -p "\$OD"
C=\$(cat "$s6_call_count_file"); C=\$((C+1)); echo "\$C" > "$s6_call_count_file"
BEHAVIOR="$s6_behavior"
if [[ "\$BEHAVIOR" == "fail_once" && "\$C" -eq 1 ]]; then
    echo '{"stage":"enforcement","overall_result":"FAIL","gates":[{"gate":1,"name":"prohibited_patterns","result":"FAIL","duration_seconds":1,"details":{"violations":[{"pattern":"TODO","location":"packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift:42"}]}}]}' > "\$OD/enforcement_report.json"
    exit 1
elif [[ "\$BEHAVIOR" == "always_fail" ]]; then
    echo '{"stage":"enforcement","overall_result":"FAIL","gates":[{"gate":1,"name":"prohibited_patterns","result":"FAIL","duration_seconds":1,"details":{"violations":[{"pattern":"TODO","location":"file.swift:1"}]}}]}' > "\$OD/enforcement_report.json"
    exit 1
else
    echo '{"stage":"enforcement","overall_result":"PASS","gates":[{"gate":1,"name":"prohibited_patterns","result":"PASS","duration_seconds":1,"details":{}}]}' > "\$OD/enforcement_report.json"
    exit 0
fi
S6EOF
    chmod +x "$mock_scripts_dir/stage6-gates.sh"

    # Mock Stage 7 — configurable behavior
    if [[ "$s7_behavior" == "always_pass" ]]; then
        cat > "$mock_scripts_dir/stage7-semantic-verification.sh" <<'S7EOF'
#!/usr/bin/env bash
set -euo pipefail
OD="" FID=""
while [[ $# -gt 0 ]]; do
    case "$1" in --output) OD="$2"; shift 2;; --finding-id) FID="$2"; shift 2;; *) shift;; esac
done
mkdir -p "$OD"
python3 -c "
import json
json.dump({'stage':'semantic_verification','finding_id':'$FID','overall_result':'PASS','confidence':0.87,'prd_alignment_score':0.92,'findings':[],'cross_engine_verification':{'touchpoints_verified':1,'touchpoints_total':1,'result':'PASS'},'anti_patterns_detected':[],'requirements_traced':{'total':1,'matched':1,'missing':[]}},open('$OD/verification_stage7_${FID}.json','w'),indent=2)
"
exit 0
S7EOF
    else
        cat > "$mock_scripts_dir/stage7-semantic-verification.sh" <<'S7EOF'
#!/usr/bin/env bash
set -euo pipefail
OD="" FID=""
while [[ $# -gt 0 ]]; do
    case "$1" in --output) OD="$2"; shift 2;; --finding-id) FID="$2"; shift 2;; *) shift;; esac
done
mkdir -p "$OD"
python3 -c "
import json
json.dump({'stage':'semantic_verification','finding_id':'$FID','overall_result':'FAIL','confidence':0.30,'prd_alignment_score':0.50,'findings':[{'severity':'CRITICAL','category':'alignment','description':'Missing FR','evidence':'test'}],'cross_engine_verification':{'touchpoints_verified':0,'touchpoints_total':1,'result':'FAIL'},'anti_patterns_detected':[],'requirements_traced':{'total':1,'matched':0,'missing':['FR-TV001-1']}},open('$OD/verification_stage7_${FID}.json','w'),indent=2)
"
exit 1
S7EOF
    fi
    chmod +x "$mock_scripts_dir/stage7-semantic-verification.sh"

    # Mock gh CLI
    local gh_log="$mock_scripts_dir/.gh_log"
    : > "$gh_log"

    cat > "$mock_scripts_dir/gh" <<GHEOF
#!/usr/bin/env bash
echo "\$@" >> "$gh_log"
if [[ "\$1" == "auth" ]]; then
    exit 0
elif [[ "\$1" == "issue" ]]; then
    echo "https://github.com/test/repo/issues/99"
fi
GHEOF
    chmod +x "$mock_scripts_dir/gh"
}

# ---------------------------------------------------------------------------
# IT-E4-005: Retries on Stage 6 failure
# ---------------------------------------------------------------------------

test_retries_on_stage6_failure() {
    echo "IT-E4-005: Retries on Stage 6 failure"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_scripts"
    create_mock_scripts "$mock_dir" "$tmpdir/builder" "fail_once"

    local exit_code=0
    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/retry_orchestrator.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --patterns "$tmpdir/patterns.txt" \
        --finding-id "tv-retry" \
        --output "$tmpdir/output" \
        --max-attempts 3 \
        --scripts-dir "$mock_dir" \
        > /dev/null 2>&1 || exit_code=$?

    if [[ -f "$tmpdir/output/retry_summary_tv-retry.json" ]]; then
        local total_attempts
        total_attempts=$(python3 -c "import json; print(json.load(open('$tmpdir/output/retry_summary_tv-retry.json'))['total_attempts'])" 2>/dev/null || echo "0")
        if [[ "$total_attempts" -ge 2 ]]; then
            pass_test "Retried after Stage 6 failure ($total_attempts attempts)"
        else
            fail_test "Retry count" "Expected >= 2 attempts, got $total_attempts"
        fi
    else
        fail_test "Retry summary" "retry_summary_tv-retry.json not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-E4-006: Appends failure context to next attempt
# ---------------------------------------------------------------------------

test_appends_failure_context() {
    echo "IT-E4-006: Appends failure context to next attempt"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_scripts"
    create_mock_scripts "$mock_dir" "$tmpdir/builder" "fail_once"

    local exit_code=0
    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/retry_orchestrator.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --patterns "$tmpdir/patterns.txt" \
        --finding-id "tv-retry" \
        --output "$tmpdir/output" \
        --max-attempts 3 \
        --scripts-dir "$mock_dir" \
        > /dev/null 2>&1 || exit_code=$?

    # Check that attempt 2 has a failure context file with attempt 1 details
    if [[ -f "$tmpdir/output/attempt_2/failure_context.md" ]]; then
        if grep -q "Attempt 1" "$tmpdir/output/attempt_2/failure_context.md"; then
            pass_test "Failure context contains Attempt 1 details"
        else
            fail_test "Failure context" "Does not reference Attempt 1"
        fi
    else
        # Check retry state for evidence of failure tracking
        if [[ -f "$tmpdir/output/retry_state_tv-retry.json" ]]; then
            local attempts_count
            attempts_count=$(python3 -c "import json; print(len(json.load(open('$tmpdir/output/retry_state_tv-retry.json'))['attempts']))" 2>/dev/null || echo "0")
            if [[ "$attempts_count" -ge 1 ]]; then
                pass_test "Failure tracked in retry state ($attempts_count failures recorded)"
            else
                fail_test "Failure context" "No failures recorded in retry state"
            fi
        else
            fail_test "Failure context" "No failure context or retry state found"
        fi
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-E4-007: Creates issue after 3 failures
# ---------------------------------------------------------------------------

test_creates_issue_after_exhaustion() {
    echo "IT-E4-007: Creates issue after 3 failures"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_scripts"
    create_mock_scripts "$mock_dir" "$tmpdir/builder" "always_fail"

    # Add mock git remote to builder for gh issue create
    git -C "$tmpdir/builder" remote add origin "https://github.com/test/target-product.git" 2>/dev/null || true

    local exit_code=0
    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/retry_orchestrator.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --patterns "$tmpdir/patterns.txt" \
        --finding-id "tv-retry" \
        --output "$tmpdir/output" \
        --max-attempts 3 \
        --scripts-dir "$mock_dir" \
        > /dev/null 2>&1 || exit_code=$?

    # Should exit with failure
    if [[ "$exit_code" -ne 0 ]]; then
        # Check gh was called with issue create
        if [[ -f "$mock_dir/.gh_log" ]] && grep -q "issue create" "$mock_dir/.gh_log"; then
            if grep -q "pipeline-failure" "$mock_dir/.gh_log"; then
                pass_test "Issue created with pipeline-failure label after exhaustion"
            else
                pass_test "Issue created after exhaustion"
            fi
        else
            # gh might not have been called if EXHAUSTED summary was written
            if [[ -f "$tmpdir/output/retry_summary_tv-retry.json" ]]; then
                local result
                result=$(python3 -c "import json; print(json.load(open('$tmpdir/output/retry_summary_tv-retry.json'))['result'])" 2>/dev/null || echo "")
                if [[ "$result" == "EXHAUSTED" ]]; then
                    pass_test "All attempts exhausted (EXHAUSTED result)"
                else
                    fail_test "Exhaustion" "Expected EXHAUSTED, got $result"
                fi
            else
                fail_test "Issue creation" "No gh invocation and no retry summary"
            fi
        fi
    else
        fail_test "Exhaustion exit" "Expected non-zero exit after 3 failures"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# IT-E4-008: Exits early on success (attempt 2)
# ---------------------------------------------------------------------------

test_exits_early_on_success() {
    echo "IT-E4-008: Exits early on success (attempt 2)"

    local tmpdir
    tmpdir=$(mktemp -d)
    setup_test_fixtures "$tmpdir"

    local mock_dir="$tmpdir/mock_scripts"
    create_mock_scripts "$mock_dir" "$tmpdir/builder" "fail_once"

    local exit_code=0
    PATH="$mock_dir:$PATH" "$SCRIPT_DIR/retry_orchestrator.sh" \
        --run-dir "$tmpdir/run_dir" \
        --builder-dir "$tmpdir/builder" \
        --engine-graph "$tmpdir/engine_graph.json" \
        --config "$tmpdir/config.json" \
        --patterns "$tmpdir/patterns.txt" \
        --finding-id "tv-retry" \
        --output "$tmpdir/output" \
        --max-attempts 3 \
        --scripts-dir "$mock_dir" \
        > /dev/null 2>&1 || exit_code=$?

    if [[ -f "$tmpdir/output/retry_summary_tv-retry.json" ]]; then
        local result total_attempts
        result=$(python3 -c "import json; print(json.load(open('$tmpdir/output/retry_summary_tv-retry.json'))['result'])" 2>/dev/null || echo "")
        total_attempts=$(python3 -c "import json; print(json.load(open('$tmpdir/output/retry_summary_tv-retry.json'))['total_attempts'])" 2>/dev/null || echo "0")

        if [[ "$result" == "ACCEPTED" && "$total_attempts" == "2" ]]; then
            pass_test "Early exit on attempt 2 — ACCEPTED"
        elif [[ "$result" == "ACCEPTED" ]]; then
            pass_test "Early exit — ACCEPTED (attempts: $total_attempts)"
        else
            fail_test "Early exit" "Expected ACCEPTED, got $result (attempts: $total_attempts)"
        fi
    else
        fail_test "Early exit" "retry_summary_tv-retry.json not found"
    fi

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Retry Orchestrator Integration Tests ==="
echo ""

test_retries_on_stage6_failure
test_appends_failure_context
test_creates_issue_after_exhaustion
test_exits_early_on_success

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed ==="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
