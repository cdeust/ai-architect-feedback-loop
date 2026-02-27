#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# retry_orchestrator.sh — Stage 7→10→11 Retry Loop (per finding)
# ============================================================================
#
# Manages the implementation/enforcement/verification cycle with up to N
# retries. Each retry appends failure context so subsequent attempts learn
# from previous failures.
#
# Usage:
#   scripts/retry_orchestrator.sh \
#       --run-dir runs/TIMESTAMP \
#       --builder-dir /path/to/target-product \
#       --engine-graph config/engine_graph.json \
#       --config config/thresholds.json \
#       --patterns config/prohibited_patterns.txt \
#       --finding-id tv-001 \
#       --output runs/TIMESTAMP \
#       [--max-attempts 3]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="retry_orchestrator"

# Resolve base branch from project config
BASE_BRANCH="main"
PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
if [[ -f "$PROJECT_CONFIG" ]]; then
    BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('base_branch', 'main'))" 2>/dev/null || echo "main")
fi

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

RUN_DIR=""
BUILDER_DIR=""
ENGINE_GRAPH=""
CONFIG_PATH=""
PATTERNS_FILE=""
FINDING_ID=""
OUTPUT_DIR=""
MAX_ATTEMPTS=""
STAGES_DIR=""

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
        --patterns)
            PATTERNS_FILE="$2"
            shift 2
            ;;
        --finding-id)
            FINDING_ID="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --max-attempts)
            MAX_ATTEMPTS="$2"
            shift 2
            ;;
        --scripts-dir)
            STAGES_DIR="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Default scripts dir to SCRIPT_DIR (co-located stage scripts)
if [[ -z "$STAGES_DIR" ]]; then
    STAGES_DIR="$SCRIPT_DIR"
fi

# Validate required args
for arg_name in RUN_DIR BUILDER_DIR ENGINE_GRAPH CONFIG_PATH FINDING_ID OUTPUT_DIR; do
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

mkdir -p "$OUTPUT_DIR"

# Read max_attempts from config if not provided via flag
if [[ -z "$MAX_ATTEMPTS" ]]; then
    MAX_ATTEMPTS=$(python3 -c "import json; print(json.load(open('$CONFIG_PATH')).get('retry', {}).get('max_attempts', 3))" 2>/dev/null || echo "3")
fi

BRANCH_NAME="pipeline/improvement-${FINDING_ID}"

# Source artifact path helpers
source "$SCRIPT_DIR/artifact_paths.sh"

# Progress event helper — writes to progress.jsonl in the run dir
emit_progress() {
    local stage="$1" status="$2"
    echo "{\"fid\":\"$FINDING_ID\",\"stage\":$stage,\"status\":\"$status\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$RUN_DIR/progress.jsonl"
}

log "INFO" "Retry orchestrator started — finding: $FINDING_ID, max_attempts: $MAX_ATTEMPTS"

# ---------------------------------------------------------------------------
# Retry state tracking
# ---------------------------------------------------------------------------

RETRY_STATE_FILE=$(artifact_retry_state "$OUTPUT_DIR" "$FINDING_ID")
python3 -c "
import json
from datetime import datetime, timezone
state = {
    'finding_id': '$FINDING_ID',
    'max_attempts': $MAX_ATTEMPTS,
    'current_attempt': 0,
    'attempts': []
}
with open('$RETRY_STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"

record_attempt_failure() {
    local attempt="$1" failed_stage="$2" failure_reason="$3"
    local failed_gate="${4:-}" files_affected="${5:-}"

    python3 - "$RETRY_STATE_FILE" "$attempt" "$failed_stage" "$failure_reason" "$failed_gate" "$files_affected" <<'PYEOF'
import json, sys

state_file = sys.argv[1]
attempt = int(sys.argv[2])
failed_stage = sys.argv[3]
failure_reason = sys.argv[4]
failed_gate = sys.argv[5] if len(sys.argv) > 5 else ""
files_affected_str = sys.argv[6] if len(sys.argv) > 6 else ""

with open(state_file) as f:
    state = json.load(f)

entry = {
    "attempt": attempt,
    "failed_stage": failed_stage,
    "failure_reason": failure_reason
}
if failed_gate:
    entry["failed_gate"] = failed_gate
if files_affected_str:
    entry["files_affected"] = [f.strip() for f in files_affected_str.split(",") if f.strip()]

state["attempts"].append(entry)
state["current_attempt"] = attempt

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF
}

# ---------------------------------------------------------------------------
# Failure context file composer
# ---------------------------------------------------------------------------

write_failure_context_file() {
    local output_file="$1"

    python3 - "$RETRY_STATE_FILE" "$output_file" <<'PYEOF'
import json, sys

state_file, output_file = sys.argv[1:3]

with open(state_file) as f:
    state = json.load(f)

attempts = state.get("attempts", [])
if not attempts:
    # No previous failures — write empty file
    with open(output_file, 'w') as f:
        f.write("")
    sys.exit(0)

lines = []
for a in attempts:
    attempt_num = a["attempt"]
    stage = a["failed_stage"]
    reason = a["failure_reason"]
    gate = a.get("failed_gate", "")
    files = a.get("files_affected", [])

    stage_label = {
        "stage_7": "Stage 7 (Implementation)",
        "stage_10": "Stage 10 (Enforcement)",
        "stage_11": "Stage 11 (Verification)"
    }.get(stage, stage)

    lines.append(f"### Attempt {attempt_num} — Failed at {stage_label}")

    if gate:
        lines.append(f"- **Failed Gate:** {gate}")

    lines.append(f"- **Failure Reason:** {reason}")

    if files:
        lines.append(f"- **Files Affected:** {', '.join(files)}")

    # Add remediation guidance based on failure type
    if "prohibited_patterns" in (gate or "").lower() or "prohibited" in reason.lower():
        lines.append("- **Action Required:** Remove all TODO/FIXME/HACK comments. Use real implementation or raise an issue.")
    elif "build" in reason.lower():
        lines.append("- **Action Required:** Fix compilation errors. Ensure all imports are correct and types match.")
    elif "test" in reason.lower():
        lines.append("- **Action Required:** Fix failing tests. Ensure new code does not break existing functionality.")
    elif "alignment" in reason.lower() or "FR-" in reason:
        lines.append("- **Action Required:** Implement the missing functionality as specified in the PRD.")
    elif "manifest" in reason.lower():
        lines.append("- **Action Required:** Prefer changing files in the advised list. Avoid changing files in the not-advised list unless necessary.")
    elif "orphan" in reason.lower():
        lines.append("- **Action Required:** Ensure all new types are referenced by existing code.")

    lines.append("")

with open(output_file, 'w') as f:
    f.write("\n".join(lines))
PYEOF
}

# ---------------------------------------------------------------------------
# Summary writer
# ---------------------------------------------------------------------------

write_retry_summary() {
    local result="$1" attempt_count="$2" issue_url="${3:-}"

    local _retry_summary
    _retry_summary=$(artifact_retry_summary "$OUTPUT_DIR" "$FINDING_ID")
    python3 - "$RETRY_STATE_FILE" "$_retry_summary" \
        "$result" "$attempt_count" "$BRANCH_NAME" "$MAX_ATTEMPTS" "$issue_url" <<'PYEOF'
import json, sys
from datetime import datetime, timezone

state_file, output_file = sys.argv[1:3]
result, attempt_count, branch, max_attempts, issue_url = sys.argv[3:8]

with open(state_file) as f:
    state = json.load(f)

summary = {
    "stage": "retry_orchestrator",
    "finding_id": state["finding_id"],
    "result": result,
    "total_attempts": int(attempt_count),
    "max_attempts": int(max_attempts),
    "branch": branch,
    "attempts": state.get("attempts", []),
    "issue_url": issue_url if issue_url else None,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}

with open(output_file, 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
PYEOF
}

# ---------------------------------------------------------------------------
# Failure issue creation (after all attempts exhausted)
# ---------------------------------------------------------------------------

create_failure_issue() {
    if ! command -v gh &> /dev/null; then
        log "WARN" "gh CLI not found — skipping issue creation"
        return
    fi

    local issue_body
    issue_body=$(python3 - "$RETRY_STATE_FILE" "$FINDING_ID" "$MAX_ATTEMPTS" <<'PYEOF'
import json, sys

state_file, finding_id, max_attempts = sys.argv[1:4]

with open(state_file) as f:
    state = json.load(f)

lines = [
    f"## Pipeline Failure Report",
    f"",
    f"**Finding:** `{finding_id}`",
    f"**Attempts:** {max_attempts} (all exhausted)",
    f"**Branch:** `pipeline/improvement-{finding_id}`",
    f"",
    f"## Attempt History",
    f"",
    f"| Attempt | Failed Stage | Gate | Reason |",
    f"|---------|-------------|------|--------|",
]

for a in state.get("attempts", []):
    attempt = a["attempt"]
    stage = a["failed_stage"]
    gate = a.get("failed_gate", "—")
    reason = a["failure_reason"][:80]
    lines.append(f"| {attempt} | {stage} | {gate} | {reason} |")

lines.extend([
    f"",
    f"## Action Required",
    f"This finding requires manual investigation. The pipeline was unable to produce",
    f"an implementation that passes all enforcement gates and semantic verification",
    f"after {max_attempts} attempts.",
    f"",
    f"---",
    f"Generated by AI Architect Pipeline | retry_orchestrator",
])

print("\n".join(lines))
PYEOF
    )

    local repo_url
    repo_url=$(git -C "$BUILDER_DIR" remote get-url origin 2>/dev/null | sed 's/\.git$//' || echo "")

    if [[ -z "$repo_url" ]]; then
        log "WARN" "Could not determine repo URL — skipping issue creation"
        return
    fi

    local issue_url
    issue_url=$(gh issue create \
        --repo "$repo_url" \
        --title "Pipeline: Failed improvement for ${FINDING_ID} after ${MAX_ATTEMPTS} attempts" \
        --body "$issue_body" \
        --label "pipeline-failure" --label "needs-investigation" 2>&1) || {
        log "WARN" "gh issue create failed: $issue_url"
        return
    }

    log "INFO" "Created failure issue: $issue_url"
    echo "$issue_url"
}

# ---------------------------------------------------------------------------
# Main retry loop
# ---------------------------------------------------------------------------

for (( attempt=1; attempt<=MAX_ATTEMPTS; attempt++ )); do
    log "INFO" "=== Attempt $attempt of $MAX_ATTEMPTS ==="

    ATTEMPT_DIR=$(artifact_attempt_dir "$OUTPUT_DIR" "$FINDING_ID" "$attempt")

    # ─── Branch lifecycle ───────────────────────────────────
    if [[ "$attempt" -gt 1 ]]; then
        # Clean up leftover branch and dirty working tree from previous attempt
        git -C "$BUILDER_DIR" checkout "$BASE_BRANCH" 2>/dev/null || true
        git -C "$BUILDER_DIR" reset --hard HEAD 2>/dev/null || true
        git -C "$BUILDER_DIR" clean -fd 2>/dev/null || true
        local_branch_exists=$(git -C "$BUILDER_DIR" branch --list "$BRANCH_NAME" 2>/dev/null | tr -d ' ')
        if [[ -n "$local_branch_exists" ]]; then
            log "INFO" "Deleting branch $BRANCH_NAME from previous attempt"
            git -C "$BUILDER_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
        fi
    fi

    # ─── Write failure context ──────────────────────────────
    FAILURE_FILE="$ATTEMPT_DIR/failure_context.md"
    write_failure_context_file "$FAILURE_FILE"

    FAILURE_CONTEXT_ARG=""
    if [[ -s "$FAILURE_FILE" ]]; then
        FAILURE_CONTEXT_ARG="--failure-context $FAILURE_FILE"
    fi

    # ─── Stage 7: Implementation (single-finding) ──────────
    emit_progress 7 "start"
    log "INFO" "Running Stage 7 for $FINDING_ID (attempt $attempt)"

    S7_EXIT=0
    # shellcheck disable=SC2086
    "$STAGES_DIR/stage7-implementation.sh" \
        --finding-id "$FINDING_ID" \
        $FAILURE_CONTEXT_ARG \
        --run-dir "$RUN_DIR" \
        --builder-dir "$BUILDER_DIR" \
        --engine-graph "$ENGINE_GRAPH" \
        --config "$CONFIG_PATH" \
        --output "$ATTEMPT_DIR" \
        2>&1 || S7_EXIT=$?

    if [[ "$S7_EXIT" -ne 0 ]]; then
        log "WARN" "Stage 7 exited with $S7_EXIT"
    fi

    # Check Stage 7 result from stage7_summary.json
    S7_RESULT=""
    S7_REASON=""
    if [[ -f "$ATTEMPT_DIR/stage7_summary.json" ]]; then
        S7_RESULT=$(python3 -c "
import json
summary = json.load(open('$ATTEMPT_DIR/stage7_summary.json'))
reports = summary.get('reports', [])
for r in reports:
    if r.get('finding_id') == '$FINDING_ID':
        print(r.get('result', 'FAILED'))
        break
else:
    print('FAILED')
" 2>/dev/null || echo "FAILED")

        S7_REASON=$(python3 -c "
import json
summary = json.load(open('$ATTEMPT_DIR/stage7_summary.json'))
for r in summary.get('reports', []):
    if r.get('finding_id') == '$FINDING_ID':
        print(r.get('reason', ''))
        break
" 2>/dev/null || echo "")
    fi

    if [[ "$S7_RESULT" != "ACCEPTED" ]]; then
        log "WARN" "Stage 7 result: $S7_RESULT — ${S7_REASON:-unknown reason}"
        record_attempt_failure "$attempt" "stage_7" "${S7_REASON:-Stage 7 did not accept implementation}"
        continue
    fi

    log "INFO" "Stage 7 passed for $FINDING_ID"
    emit_progress 7 "complete"

    # ─── Stage 10: Enforcement gates ───────────────────────
    emit_progress 10 "start"
    log "INFO" "Running Stage 10 for $FINDING_ID (attempt $attempt)"

    # Checkout feature branch for gate evaluation
    git -C "$BUILDER_DIR" checkout "$BRANCH_NAME" 2>/dev/null || {
        log "ERROR" "Could not checkout $BRANCH_NAME"
        record_attempt_failure "$attempt" "stage_10" "Could not checkout branch $BRANCH_NAME"
        continue
    }

    S10_EXIT=0
    "$STAGES_DIR/stage10-gates.sh" \
        --builder-dir "$BUILDER_DIR" \
        --config "$CONFIG_PATH" \
        --patterns "${PATTERNS_FILE:-}" \
        --skip-gate 2 \
        --output "$ATTEMPT_DIR" \
        2>&1 || S10_EXIT=$?

    # Return to base branch
    git -C "$BUILDER_DIR" checkout "$BASE_BRANCH" 2>/dev/null || true

    if [[ "$S10_EXIT" -ne 0 ]]; then
        # Parse enforcement_report.json for failure details
        GATE_FAILURES=""
        if [[ -f "$ATTEMPT_DIR/enforcement_report.json" ]]; then
            GATE_FAILURES=$(python3 -c "
import json
report = json.load(open('$ATTEMPT_DIR/enforcement_report.json'))
failures = []
for g in report.get('gates', []):
    if g['result'] == 'FAIL':
        name = g['name']
        gate_num = g['gate']
        details = g.get('details', {})
        viols = details.get('violations', [])
        desc = f'Gate {gate_num} ({name})'
        if viols:
            first = viols[0] if isinstance(viols[0], str) else str(viols[0])
            desc += f': {first[:100]}'
        failures.append(desc)
print('; '.join(failures) if failures else 'Unknown gate failure')
" 2>/dev/null || echo "Unknown gate failure")

            FAILED_GATE=$(python3 -c "
import json
report = json.load(open('$ATTEMPT_DIR/enforcement_report.json'))
for g in report.get('gates', []):
    if g['result'] == 'FAIL':
        print(f\"gate_{g['gate']}\")
        break
" 2>/dev/null || echo "")
        fi

        log "WARN" "Stage 10 failed: $GATE_FAILURES"
        record_attempt_failure "$attempt" "stage_10" "$GATE_FAILURES" "$FAILED_GATE"
        continue
    fi

    log "INFO" "Stage 10 passed for $FINDING_ID"
    emit_progress 10 "complete"

    # ─── Stage 11: Semantic verification ───────────────────
    emit_progress 11 "start"
    log "INFO" "Running Stage 11 for $FINDING_ID (attempt $attempt)"

    S11_EXIT=0
    "$STAGES_DIR/stage11-semantic-verification.sh" \
        --run-dir "$RUN_DIR" \
        --builder-dir "$BUILDER_DIR" \
        --engine-graph "$ENGINE_GRAPH" \
        --config "$CONFIG_PATH" \
        --patterns "${PATTERNS_FILE:-}" \
        --finding-id "$FINDING_ID" \
        --branch "$BRANCH_NAME" \
        --output "$ATTEMPT_DIR" \
        2>&1 || S11_EXIT=$?

    if [[ "$S11_EXIT" -ne 0 ]]; then
        # Parse verification findings
        VERIFICATION_FAILURES=""
        _verif_file=$(artifact_verification11 "$ATTEMPT_DIR" "$FINDING_ID")
        if [[ -f "$_verif_file" ]]; then
            VERIFICATION_FAILURES=$(python3 -c "
import json
result = json.load(open('$_verif_file'))
findings = result.get('findings', [])
lines = []
for f in findings:
    sev = f.get('severity', '?')
    desc = f.get('description', '?')
    cat = f.get('category', '?')
    evidence = f.get('evidence', '')
    if sev in ('CRITICAL', 'WARNING'):
        entry = f'{sev} ({cat}): {desc[:300]}'
        if evidence:
            entry += f' [evidence: {evidence[:200]}]'
        lines.append(entry)
print('; '.join(lines) if lines else 'Semantic verification failed')
" 2>/dev/null || echo "Semantic verification failed")
        fi

        log "WARN" "Stage 11 failed: $VERIFICATION_FAILURES"
        record_attempt_failure "$attempt" "stage_11" "$VERIFICATION_FAILURES"
        continue
    fi

    # ─── SUCCESS ───────────────────────────────────────────
    emit_progress 11 "complete"
    log "INFO" "All stages passed for $FINDING_ID on attempt $attempt"
    write_retry_summary "ACCEPTED" "$attempt"
    log "INFO" "Retry summary written to $(artifact_retry_summary "$OUTPUT_DIR" "$FINDING_ID")"
    exit 0
done

# ─── All attempts exhausted ───────────────────────────────
log "ERROR" "All $MAX_ATTEMPTS attempts exhausted for $FINDING_ID"

ISSUE_URL=""
ISSUE_URL=$(create_failure_issue) || true

write_retry_summary "EXHAUSTED" "$MAX_ATTEMPTS" "$ISSUE_URL"
log "INFO" "Retry summary written to $(artifact_retry_summary "$OUTPUT_DIR" "$FINDING_ID")"

exit 1
