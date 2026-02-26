#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage7-worker.sh — Per-module implementation worker (CLI mode)
# ============================================================================
#
# Implements a single work unit (one engine's file slice) using claude -p.
# Produces a patch file in a temp directory — does NOT modify the branch
# directly. The orchestrator applies patches sequentially.
#
# Usage:
#   scripts/stage7-worker.sh \
#       --work-unit /tmp/work_units/wu-001.json \
#       --builder-dir /path/to/target-product \
#       --branch pipeline/improvement-tv-001 \
#       --output /tmp/worker_output \
#       [--timeout 600]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage7_worker"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# POSIX-compatible timeout
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

WORK_UNIT=""
BUILDER_DIR=""
BRANCH=""
OUTPUT_DIR=""
TIMEOUT=600

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-unit) WORK_UNIT="$2"; shift 2;;
        --builder-dir) BUILDER_DIR="$2"; shift 2;;
        --branch) BRANCH="$2"; shift 2;;
        --output) OUTPUT_DIR="$2"; shift 2;;
        --timeout) TIMEOUT="$2"; shift 2;;
        *) log "ERROR" "Unknown argument: $1"; exit 1;;
    esac
done

for arg_name in WORK_UNIT BUILDER_DIR BRANCH OUTPUT_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        log "ERROR" "Missing required argument: --$(echo "$arg_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        exit 1
    fi
done

if [[ ! -f "$WORK_UNIT" ]]; then
    log "ERROR" "Work unit file not found: $WORK_UNIT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Read work unit
# ---------------------------------------------------------------------------

WU_ID=$(python3 -c "import json; print(json.load(open('$WORK_UNIT'))['id'])")
ENGINE=$(python3 -c "import json; print(json.load(open('$WORK_UNIT'))['engine'])")
FINDING_ID=$(python3 -c "import json; print(json.load(open('$WORK_UNIT'))['finding_id'])")

log "INFO" "Worker started — $WU_ID ($ENGINE) for $FINDING_ID"

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Setup temp working copy
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Checkout the branch in a worktree for isolation
WORKTREE_DIR="$TMP_DIR/worktree"
git -C "$BUILDER_DIR" worktree add "$WORKTREE_DIR" "$BRANCH" 2>/dev/null || {
    # Fallback: work directly on the branch
    WORKTREE_DIR="$BUILDER_DIR"
    git -C "$BUILDER_DIR" checkout "$BRANCH" 2>/dev/null
}

WORKTREE_CLEANUP() {
    if [[ "$WORKTREE_DIR" != "$BUILDER_DIR" ]]; then
        git -C "$BUILDER_DIR" worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap WORKTREE_CLEANUP EXIT

# ---------------------------------------------------------------------------
# Read project config for build/test commands
# ---------------------------------------------------------------------------

PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
BUILD_CMD=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('build_command', 'make build'))" 2>/dev/null || echo "make build")
TEST_CMD=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('test_command', 'make test'))" 2>/dev/null || echo "make test")

# ---------------------------------------------------------------------------
# Assemble worker prompt
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE="$SCRIPT_DIR/../prompts/worker.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
    log "ERROR" "Worker prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

# Extract fields from work unit for prompt substitution
python3 - "$WORK_UNIT" "$PROMPT_TEMPLATE" "$TMP_DIR/prompt.md" "$FINDING_ID" "$ENGINE" <<'PYEOF'
import json, sys

wu_path, template_path, output_path, finding_id, engine = sys.argv[1:6]

with open(wu_path) as f:
    wu = json.load(f)
with open(template_path) as f:
    template = f.read()

# File actions
file_actions_lines = []
for path, info in wu.get("file_actions", {}).items():
    action = info.get("action", "modify")
    desc = info.get("description", "")
    file_actions_lines.append(f"- `{path}` ({action}): {desc}")
file_actions = "\n".join(file_actions_lines) or "(no files specified)"

# Contract changes
contract_lines = []
for c in wu.get("contracts", []):
    protocol = c.get("protocol", "")
    change = c.get("change", "")
    contract_lines.append(f"- {protocol}: {change}")
contracts = "\n".join(contract_lines) or "(no contract changes)"

# Touchpoints
tp_lines = []
for tp in wu.get("touchpoints", []):
    fr = tp.get("from", "?")
    to = tp.get("to", "?")
    via = tp.get("via", "?")
    desc = tp.get("description", "")
    tp_lines.append(f"- {fr} -> {to} via {via}: {desc}")
touchpoints = "\n".join(tp_lines) or "(no cross-engine touchpoints for this module)"

must_change = "\n".join(f"- {f}" for f in wu.get("must_change", [])) or "(none specified)"
must_not_change = "\n".join(f"- {f}" for f in wu.get("must_not_change", [])) or "(none)"
prd_slice = wu.get("prd_slice", "(no PRD slice available)")

result = template
result = result.replace("{{ENGINE_NAME}}", engine)
result = result.replace("{{FINDING_ID}}", finding_id)
result = result.replace("{{PRD_SLICE}}", prd_slice)
result = result.replace("{{FILE_ACTIONS}}", file_actions)
result = result.replace("{{CONTRACT_CHANGES}}", contracts)
result = result.replace("{{TOUCHPOINTS}}", touchpoints)
result = result.replace("{{MUST_CHANGE}}", must_change)
result = result.replace("{{MUST_NOT_CHANGE}}", must_not_change)

# Placeholders that stage7 orchestrator fills (or left empty for worker)
for placeholder in ("{{ARCHITECTURE_DESCRIPTION}}", "{{ENGINE_GRAPH}}",
                     "{{CLAUDE_MD_RULES}}", "{{ENGINE_CONTRACTS}}", "{{BUILD_COMMANDS}}"):
    if placeholder in result:
        result = result.replace(placeholder, "(provided by orchestrator)")

with open(output_path, "w") as f:
    f.write(result)
PYEOF

log "INFO" "Worker prompt assembled for $WU_ID"

# ---------------------------------------------------------------------------
# Invoke Claude Code CLI
# ---------------------------------------------------------------------------

RAW_OUTPUT="$TMP_DIR/raw_output.txt"
CLAUDE_EXIT=0

cd "$WORKTREE_DIR"
AI_TIMEOUT="$TIMEOUT" ai_invoke "$TMP_DIR/prompt.md" "$RAW_OUTPUT" "stage7" "$FINDING_ID" \
    --max-turns 10 \
    || CLAUDE_EXIT=$?

if [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    log "ERROR" "Worker $WU_ID failed (exit=$CLAUDE_EXIT)"
    echo "{\"id\":\"$WU_ID\",\"engine\":\"$ENGINE\",\"result\":\"FAILED\",\"reason\":\"AI invocation failed (exit=$CLAUDE_EXIT)\"}" > "$OUTPUT_DIR/result_${WU_ID}.json"
    exit 1
fi

# ---------------------------------------------------------------------------
# Generate patch from worker's changes
# ---------------------------------------------------------------------------

COMMIT_COUNT=$(git -C "$WORKTREE_DIR" rev-list --count HEAD ^"$BRANCH" 2>/dev/null || echo "0")

if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    # Check for uncommitted changes
    if [[ -n "$(git -C "$WORKTREE_DIR" status --porcelain)" ]]; then
        git -C "$WORKTREE_DIR" add -A
        git -C "$WORKTREE_DIR" commit -m "pipeline: $FINDING_ID — $ENGINE implementation ($WU_ID)" 2>/dev/null || true
        COMMIT_COUNT=1
    fi
fi

if [[ "$COMMIT_COUNT" -gt 0 ]]; then
    git -C "$WORKTREE_DIR" format-patch -"$COMMIT_COUNT" -o "$OUTPUT_DIR/patches_${WU_ID}" 2>/dev/null
    log "INFO" "Worker $WU_ID: $COMMIT_COUNT commits, patches written"
    echo "{\"id\":\"$WU_ID\",\"engine\":\"$ENGINE\",\"result\":\"SUCCESS\",\"commits\":$COMMIT_COUNT}" > "$OUTPUT_DIR/result_${WU_ID}.json"
else
    log "WARN" "Worker $WU_ID: no changes produced"
    echo "{\"id\":\"$WU_ID\",\"engine\":\"$ENGINE\",\"result\":\"NO_CHANGES\",\"commits\":0}" > "$OUTPUT_DIR/result_${WU_ID}.json"
fi

log "INFO" "Worker $WU_ID completed"
