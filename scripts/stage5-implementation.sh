#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage5-implementation.sh — Stage 5: Implementation (Claude Code CLI)
# ============================================================================
#
# Creates feature branches on the product repo and invokes Claude Code CLI
# to implement upgrades. Verifies that changes compile and tests pass.
#
# Usage (called by Makefile pipeline-stage5):
#   scripts/stage5-implementation.sh \
#       --run-dir runs/TIMESTAMP \
#       --builder-dir /path/to/target-product \
#       --engine-graph config/engine_graph.json \
#       --config config/thresholds.json \
#       --output runs/TIMESTAMP \
#       [--timeout 1800] [--max-implementations 5]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage5_implementation"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# POSIX-compatible timeout (works on macOS and Linux without coreutils)
# ---------------------------------------------------------------------------

run_with_timeout() {
    local secs="$1"; local outfile="$2"; shift 2
    "$@" > "$outfile" 2>/dev/null &
    local cmd_pid=$!
    ( sleep "$secs" && kill "$cmd_pid" 2>/dev/null ) &
    local watcher_pid=$!
    wait "$cmd_pid" 2>/dev/null
    local exit_code=$?
    kill "$watcher_pid" 2>/dev/null
    wait "$watcher_pid" 2>/dev/null
    return $exit_code
}

# Source shared AI invocation helper
source "$SCRIPT_DIR/ai_invoke.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

RUN_DIR=""
BUILDER_DIR=""
ENGINE_GRAPH=""
CONFIG_PATH=""
OUTPUT_DIR=""
TIMEOUT=1800
MAX_IMPLEMENTATIONS=5
SINGLE_FINDING_ID=""
FAILURE_CONTEXT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir)
            RUN_DIR="$2"
            shift 2
            ;;
        --builder-dir)
            BUILDER_DIR="$2"
            shift 2
            ;;
        --engine-graph)
            ENGINE_GRAPH="$2"
            shift 2
            ;;
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --max-implementations)
            MAX_IMPLEMENTATIONS="$2"
            shift 2
            ;;
        --finding-id)
            SINGLE_FINDING_ID="$2"
            shift 2
            ;;
        --failure-context)
            FAILURE_CONTEXT_FILE="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required args
for arg_name in RUN_DIR BUILDER_DIR ENGINE_GRAPH CONFIG_PATH OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -d "$RUN_DIR" ]]; then
    log "ERROR" "Run directory not found: $RUN_DIR"
    exit 1
fi

if [[ ! -d "$BUILDER_DIR" ]]; then
    log "ERROR" "Builder directory not found: $BUILDER_DIR"
    exit 1
fi

# Check for claude CLI
if ! command -v claude &> /dev/null; then
    log "ERROR" "claude CLI not found in PATH"
    exit 1
fi

# Verify clean working tree
DIRTY=$(git -C "$BUILDER_DIR" status --porcelain 2>/dev/null || echo "ERROR")
if [[ "$DIRTY" == "ERROR" ]]; then
    log "ERROR" "Cannot check git status in builder dir"
    exit 1
fi
if [[ -n "$DIRTY" ]]; then
    log "ERROR" "Builder repo has uncommitted changes. Commit or stash first."
    exit 1
fi

# Resolve paths to absolute (Stage 5 cd's to BUILDER_DIR)
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
BUILDER_DIR="$(cd "$BUILDER_DIR" && pwd)"
ENGINE_GRAPH="$(cd "$(dirname "$ENGINE_GRAPH")" && pwd)/$(basename "$ENGINE_GRAPH")"
CONFIG_PATH="$(cd "$(dirname "$CONFIG_PATH")" && pwd)/$(basename "$CONFIG_PATH")"

ORIGINAL_BRANCH=$(git -C "$BUILDER_DIR" branch --show-current)
log "INFO" "Builder repo on branch: $ORIGINAL_BRANCH"

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Temp directory with cleanup + branch safety
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
cleanup() {
    # Always return to original branch
    local current_branch
    current_branch=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "")
    if [[ -n "$current_branch" && "$current_branch" != "$ORIGINAL_BRANCH" ]]; then
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Read prompt template
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE_PATH="$SCRIPT_DIR/../prompts/implementation.md"
if [[ ! -f "$PROMPT_TEMPLATE_PATH" ]]; then
    log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract contracts once
# ---------------------------------------------------------------------------

PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
MODULES_DIR=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('modules_dir', 'packages'))" 2>/dev/null || echo "packages")
if [[ "$MODULES_DIR" == "." ]]; then
    PACKAGES_DIR="$BUILDER_DIR"
else
    PACKAGES_DIR="$BUILDER_DIR/$MODULES_DIR"
fi

log "INFO" "Extracting engine contracts from $PACKAGES_DIR"

python3 "$SCRIPT_DIR/extract_contracts.py" \
    --packages-dir "$PACKAGES_DIR" --format markdown \
    --output "$TMP_DIR/contracts.md" > /dev/null 2>&1

log "INFO" "Contracts extracted"

# ---------------------------------------------------------------------------
# Find accepted Stage 4 outputs
# ---------------------------------------------------------------------------

ACCEPTED_FINDINGS=()
if [[ -n "$SINGLE_FINDING_ID" ]]; then
    # Single-finding mode: process only the specified finding (used by retry orchestrator)
    ACCEPTED_FINDINGS=("$SINGLE_FINDING_ID")
    log "INFO" "Single-finding mode: processing $SINGLE_FINDING_ID"
else
    for validation_file in "$RUN_DIR"/validation_stage4_*.json; do
        [[ ! -f "$validation_file" ]] && continue

        RESULT=$(python3 -c "import json; print(json.load(open('$validation_file')).get('result', ''))" 2>/dev/null || echo "")
        if [[ "$RESULT" == "ACCEPTED" ]]; then
            FINDING_ID=$(python3 -c "import json; print(json.load(open('$validation_file')).get('finding_id', ''))" 2>/dev/null || echo "")
            if [[ -n "$FINDING_ID" ]]; then
                ACCEPTED_FINDINGS+=("$FINDING_ID")
            fi
        fi
    done
fi

log "INFO" "Stage 5 started — Implementation"
log "INFO" "Found ${#ACCEPTED_FINDINGS[@]} accepted PRDs"

if [[ ${#ACCEPTED_FINDINGS[@]} -eq 0 ]]; then
    log "INFO" "No accepted PRDs to implement"
    python3 -c "
import json
from datetime import datetime, timezone
summary = {
    'stage': 'implementation',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'findings_processed': 0,
    'accepted': 0,
    'rejected': 0,
    'failed': 0,
    'reports': [],
}
with open('$OUTPUT_DIR/stage5_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
"
    exit 0
fi

# ---------------------------------------------------------------------------
# Summary tracking
# ---------------------------------------------------------------------------

SUMMARY_FILE="$TMP_DIR/summary_results.json"
echo '[]' > "$SUMMARY_FILE"

ACCEPTED_COUNT=0
REJECTED_COUNT=0
FAILED_COUNT=0
PROCESSED=0

add_summary_result() {
    local finding_id="$1" result="$2" reason="${3:-}"
    python3 - "$SUMMARY_FILE" "$finding_id" "$result" "$reason" <<'PYEOF'
import json, sys
summary_file, fid, result, reason = sys.argv[1:5]
with open(summary_file) as f:
    results = json.load(f)
entry = {"finding_id": fid, "result": result}
if reason:
    entry["reason"] = reason
results.append(entry)
with open(summary_file, 'w') as f:
    json.dump(results, f)
PYEOF
}

# ---------------------------------------------------------------------------
# Process each accepted PRD
# ---------------------------------------------------------------------------

for FINDING_ID in "${ACCEPTED_FINDINGS[@]}"; do
    if [[ "$PROCESSED" -ge "$MAX_IMPLEMENTATIONS" ]]; then
        log "INFO" "Reached max implementations limit ($MAX_IMPLEMENTATIONS), stopping"
        break
    fi

    log "INFO" "Processing finding: $FINDING_ID"
    PROCESSED=$((PROCESSED + 1))

    # Locate files
    PRD_DIR="$RUN_DIR/prd_output_${FINDING_ID}"
    INTEGRATION_PLAN="$RUN_DIR/integration_plan_${FINDING_ID}.json"
    MANIFEST="$RUN_DIR/manifest_${FINDING_ID}.json"

    if [[ ! -d "$PRD_DIR" ]]; then
        log "WARN" "PRD output dir not found: $PRD_DIR — skipping"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "PRD output dir not found"
        continue
    fi

    if [[ ! -f "$INTEGRATION_PLAN" ]]; then
        log "WARN" "Integration plan not found: $INTEGRATION_PLAN — skipping"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "Integration plan not found"
        continue
    fi

    # Read manifest
    MUST_CHANGE=""
    MUST_NOT_CHANGE=""
    if [[ -f "$MANIFEST" ]]; then
        MUST_CHANGE=$(python3 -c "import json; print('\n'.join(json.load(open('$MANIFEST')).get('must_change', [])))" 2>/dev/null || echo "")
        MUST_NOT_CHANGE=$(python3 -c "import json; print('\n'.join(json.load(open('$MANIFEST')).get('must_not_change', [])))" 2>/dev/null || echo "")
    fi

    # Get affected engines
    AFFECTED_ENGINES=$(python3 -c "
import json
plan = json.load(open('$INTEGRATION_PLAN'))
print(' '.join(plan.get('affected_engines', [])))
" 2>/dev/null || echo "")

    if [[ -z "$AFFECTED_ENGINES" ]]; then
        log "WARN" "No affected engines for $FINDING_ID"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "No affected engines"
        continue
    fi

    # Pre-flight handoff check: PRD vs manifest conflict
    if [[ -f "$PRD_DIR/prd.md" && -f "$MANIFEST" ]]; then
        CONFLICT=$(python3 - "$PRD_DIR/prd.md" "$MANIFEST" <<'PYEOF'
import json, re, sys
prd_text = open(sys.argv[1]).read()
manifest = json.load(open(sys.argv[2]))
prd_files = set(re.findall(r'packages/\S+\.\w+', prd_text))
must_not_change = set(manifest.get("must_not_change", []))
conflicts = prd_files & must_not_change
if conflicts:
    print(",".join(sorted(conflicts)))
else:
    print("")
PYEOF
        )

        if [[ -n "$CONFLICT" ]]; then
            log "WARN" "PRD references protected files: $CONFLICT"
            REJECTED_COUNT=$((REJECTED_COUNT + 1))
            add_summary_result "$FINDING_ID" "REJECTED" "PRD/manifest conflict: $CONFLICT"
            continue
        fi
    fi

    # Create or checkout feature branch
    BRANCH_NAME="pipeline/improvement-${FINDING_ID}"
    if git -C "$BUILDER_DIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
        log "INFO" "Checking out existing branch: $BRANCH_NAME"
        git -C "$BUILDER_DIR" checkout "$BRANCH_NAME" 2>/dev/null
    else
        log "INFO" "Creating branch: $BRANCH_NAME"
        git -C "$BUILDER_DIR" checkout -b "$BRANCH_NAME" 2>/dev/null
    fi

    # Generate build commands from project config
    PROJECT_CONFIG_FILE="$SCRIPT_DIR/../config/project.json"
    BUILD_CMD_CFG="make build"
    TEST_CMD_CFG="make test"
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        BUILD_CMD_CFG=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG_FILE')).get('build_command', 'make build'))" 2>/dev/null || echo "make build")
        TEST_CMD_CFG=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG_FILE')).get('test_command', 'make test'))" 2>/dev/null || echo "make test")
    fi
    BUILD_CMDS="cd $BUILDER_DIR && $BUILD_CMD_CFG"$'\n'"cd $BUILDER_DIR && $TEST_CMD_CFG"$'\n'

    # Read CLAUDE.md from builder repo
    CLAUDE_MD_RULES=""
    if [[ -f "$BUILDER_DIR/CLAUDE.md" ]]; then
        CLAUDE_MD_RULES=$(head -c 3000 "$BUILDER_DIR/CLAUDE.md")
    fi

    # Extract contracts for affected engines
    # shellcheck disable=SC2086
    python3 "$SCRIPT_DIR/extract_contracts.py" \
        --packages-dir "$PACKAGES_DIR" --format markdown \
        --engines $AFFECTED_ENGINES \
        --output "$TMP_DIR/contracts_${FINDING_ID}.md" > /dev/null 2>&1

    # Read engine graph subgraph
    ENGINE_GRAPH_TEXT=$(python3 -c "
import json
g = json.load(open('$ENGINE_GRAPH'))
affected = '$AFFECTED_ENGINES'.split()
lines = []
for e in affected:
    info = g['engines'].get(e, {})
    deps = info.get('depends_on', [])
    feeds = info.get('feeds', [])
    lines.append(f'{e} ({info.get(\"package_path\", \"?\")}) depends_on: [{chr(44).join(deps)}]')
    for t in feeds:
        lines.append(f'  -> feeds: {t}')
print(chr(10).join(lines))
" 2>/dev/null || echo "")

    # Read PRD
    PRD_CONTENT=""
    [[ -f "$PRD_DIR/prd.md" ]] && PRD_CONTENT=$(cat "$PRD_DIR/prd.md")

    # Assemble prompt
    echo "$CLAUDE_MD_RULES" > "$TMP_DIR/claude_md.txt"
    echo "$ENGINE_GRAPH_TEXT" > "$TMP_DIR/engine_graph_text.txt"
    echo "$PRD_CONTENT" > "$TMP_DIR/prd_content.txt"
    echo "$MUST_CHANGE" > "$TMP_DIR/must_change.txt"
    echo "$MUST_NOT_CHANGE" > "$TMP_DIR/must_not_change.txt"
    echo "$BUILD_CMDS" > "$TMP_DIR/build_cmds.txt"
    cat "$INTEGRATION_PLAN" > "$TMP_DIR/plan_content.txt"

    python3 - "$PROMPT_TEMPLATE_PATH" "$TMP_DIR/engine_graph_text.txt" \
        "$TMP_DIR/claude_md.txt" "$TMP_DIR/prd_content.txt" \
        "$TMP_DIR/plan_content.txt" "$TMP_DIR/must_change.txt" \
        "$TMP_DIR/must_not_change.txt" "$TMP_DIR/contracts_${FINDING_ID}.md" \
        "$TMP_DIR/build_cmds.txt" "$FINDING_ID" \
        "$TMP_DIR/prompt_${FINDING_ID}.md" <<'PYEOF'
import sys

(template_path, graph_path, claude_md_path, prd_path,
 plan_path, must_change_path, must_not_change_path,
 contracts_path, build_cmds_path, finding_id, output_path) = sys.argv[1:12]

with open(template_path) as f:
    template = f.read()

def read_file(p):
    with open(p) as f:
        return f.read()

result = template
result = result.replace("{{ENGINE_GRAPH}}", read_file(graph_path))
result = result.replace("{{CLAUDE_MD_RULES}}", read_file(claude_md_path))
result = result.replace("{{UPGRADE_PRD}}", read_file(prd_path))
result = result.replace("{{INTEGRATION_PLAN}}", read_file(plan_path))
result = result.replace("{{MUST_CHANGE}}", read_file(must_change_path))
result = result.replace("{{MUST_NOT_CHANGE}}", read_file(must_not_change_path))
result = result.replace("{{ENGINE_CONTRACTS}}", read_file(contracts_path))
result = result.replace("{{BUILD_COMMANDS}}", read_file(build_cmds_path))
result = result.replace("{{FINDING_ID}}", finding_id)

with open(output_path, "w") as f:
    f.write(result)
PYEOF

    # Append failure context from previous retry attempts (if provided)
    if [[ -n "$FAILURE_CONTEXT_FILE" && -f "$FAILURE_CONTEXT_FILE" ]]; then
        {
            echo ""
            echo "## Previous Attempt Failures"
            echo "The following issues were found in previous implementation attempts."
            echo "You MUST fix these problems in this attempt:"
            echo ""
            cat "$FAILURE_CONTEXT_FILE"
        } >> "$TMP_DIR/prompt_${FINDING_ID}.md"
        log "INFO" "Appended failure context from $FAILURE_CONTEXT_FILE"
    fi

    # Invoke AI analysis (builder dir for code modification)
    RAW_OUTPUT="$TMP_DIR/raw_impl_${FINDING_ID}.txt"
    CLAUDE_EXIT=0

    cd "$BUILDER_DIR"
    ai_invoke "$TMP_DIR/prompt_${FINDING_ID}.md" "$RAW_OUTPUT" "stage5" "$FINDING_ID" \
        --max-turns 30 \
        || CLAUDE_EXIT=$?

    if [[ "$CLAUDE_EXIT" -eq 42 ]]; then
        log "INFO" "Session mode: skipping $FINDING_ID (prompt written, awaiting response)"
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        git -C "$BUILDER_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
        continue
    elif [[ "$CLAUDE_EXIT" -ne 0 ]]; then
        log "ERROR" "AI invocation failed for $FINDING_ID (exit=$CLAUDE_EXIT)"
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        git -C "$BUILDER_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
        FAILED_COUNT=$((FAILED_COUNT + 1))
        add_summary_result "$FINDING_ID" "FAILED" "AI invocation failed"
        continue
    fi

    # Post-implementation checks
    COMMIT_COUNT=$(git -C "$BUILDER_DIR" rev-list --count HEAD ^"${ORIGINAL_BRANCH}" 2>/dev/null || echo "0")

    if [[ "$COMMIT_COUNT" -eq 0 ]]; then
        log "WARN" "No commits produced for $FINDING_ID"
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        git -C "$BUILDER_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
        REJECTED_COUNT=$((REJECTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "REJECTED" "No commits produced"
        continue
    fi

    log "INFO" "Found $COMMIT_COUNT commits for $FINDING_ID"

    # Check manifest compliance: only must_change files were modified
    MANIFEST_OK=true
    if [[ -f "$MANIFEST" ]]; then
        MODIFIED_FILES=$(git -C "$BUILDER_DIR" diff --name-only "${ORIGINAL_BRANCH}..HEAD" 2>/dev/null || echo "")
        MANIFEST_VIOLATION=$(python3 - "$MANIFEST" <<PYEOF
import json, sys
manifest = json.load(open(sys.argv[1]))
must_not_change = set(manifest.get("must_not_change", []))
modified = """$MODIFIED_FILES""".strip().split("\n")
violations = [f for f in modified if f in must_not_change]
if violations:
    print(",".join(violations))
else:
    print("")
PYEOF
        )

        if [[ -n "$MANIFEST_VIOLATION" ]]; then
            log "WARN" "Manifest violation for $FINDING_ID: $MANIFEST_VIOLATION"
            MANIFEST_OK=false
        fi
    fi

    # Build verification using project config
    BUILD_OK=true
    if [[ "$MANIFEST_OK" == "true" ]]; then
        local verify_build_cmd="make build"
        if [[ -f "$SCRIPT_DIR/../config/project.json" ]]; then
            verify_build_cmd=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/../config/project.json')).get('build_command', 'make build'))" 2>/dev/null || echo "make build")
        fi
        if ! (cd "$BUILDER_DIR" && eval "$verify_build_cmd" > /dev/null 2>&1); then
            log "WARN" "Build verification failed"
            BUILD_OK=false
        fi
    fi

    # Decision
    if [[ "$MANIFEST_OK" == "true" && "$BUILD_OK" == "true" ]]; then
        log "INFO" "Finding $FINDING_ID: Implementation ACCEPTED ($COMMIT_COUNT commits on $BRANCH_NAME)"
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "ACCEPTED"
    else
        REASON=""
        [[ "$MANIFEST_OK" != "true" ]] && REASON="Manifest violation: $MANIFEST_VIOLATION"
        [[ "$BUILD_OK" != "true" ]] && REASON="${REASON:+$REASON; }Build failed"

        log "WARN" "Finding $FINDING_ID: Implementation REJECTED ($REASON)"
        git -C "$BUILDER_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        git -C "$BUILDER_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
        REJECTED_COUNT=$((REJECTED_COUNT + 1))
        add_summary_result "$FINDING_ID" "REJECTED" "$REASON"
    fi
done

# ---------------------------------------------------------------------------
# Write stage5_summary.json
# ---------------------------------------------------------------------------

TOTAL=$((ACCEPTED_COUNT + REJECTED_COUNT + FAILED_COUNT))

python3 - "$SUMMARY_FILE" "$OUTPUT_DIR/stage5_summary.json" "$TOTAL" "$ACCEPTED_COUNT" "$REJECTED_COUNT" "$FAILED_COUNT" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

summary_file = sys.argv[1]
output_file = sys.argv[2]
processed, accepted, rejected, failed = (int(x) for x in sys.argv[3:7])

with open(summary_file) as f:
    reports = json.load(f)

summary = {
    "stage": "implementation",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "findings_processed": processed,
    "accepted": accepted,
    "rejected": rejected,
    "failed": failed,
    "reports": reports,
}

with open(output_file, 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
PYEOF

log "INFO" "Stage 5 completed — processed=$TOTAL accepted=$ACCEPTED_COUNT rejected=$REJECTED_COUNT failed=$FAILED_COUNT"
log "INFO" "Summary written to $OUTPUT_DIR/stage5_summary.json"

exit 0
