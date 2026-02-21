#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# pipeline.sh — Nightly Product Improvement Cycle
# ============================================================================
#
# The product's self-improvement orchestrator. Every stage is product-aware —
# it knows what engines exist, what ports are being modified, and tracks how
# the product changes.
#
# Phases:
#   1. Pre-flight    — health_check.sh
#   2. Discovery     — stage1 + prioritize
#   3. Architecture  — stage2 (impact) + stage3 (integration design)
#   4. PRD Gen       — stage4 (dogfood)
#   5. Implement     — retry_orchestrator per finding (stage5→6→7)
#   6. Quality       — stage8 (benchmark) + stage9 (deployment)
#   7. Delivery      — stage10 (PRs)
#   8. Report        — compose_improvement_report.py + notify.sh
#
# Usage:
#   scripts/pipeline.sh \
#       [--builder-dir /path/to/target-product] \
#       [--tv-dir ~/Downloads/TechnicalVeil] \
#       [--dry-run]
# ============================================================================

STAGE_NAME="pipeline_orchestrator"
PIPELINE_START=$(date +%s)

# Resolve paths relative to this repo
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_DIR/scripts"
CONFIG_DIR="$REPO_DIR/config"

# Defaults
BUILDER_DIR="${BUILDER_DIR:-${PIPELINE_BUILDER:?Set BUILDER_DIR or PIPELINE_BUILDER to the target product repo}}"
TV_DIR="${TV_DIR:-$HOME/Downloads/TechnicalVeil}"
DRY_RUN=false

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --builder-dir) BUILDER_DIR="$2"; shift 2;;
        --tv-dir) TV_DIR="$2"; shift 2;;
        --dry-run) DRY_RUN=true; shift;;
        *) log "WARN" "Unknown argument: $1"; shift;;
    esac
done

# ---------------------------------------------------------------------------
# Derive packages dir from project config
# ---------------------------------------------------------------------------

PROJECT_CONFIG="$CONFIG_DIR/project.json"
MODULES_DIR=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('modules_dir', 'packages'))" 2>/dev/null || echo "packages")
if [[ "$MODULES_DIR" == "." ]]; then
    PACKAGES_DIR="$BUILDER_DIR"
else
    PACKAGES_DIR="$BUILDER_DIR/$MODULES_DIR"
fi

# ---------------------------------------------------------------------------
# Read pipeline preferences (from unified config, with fallbacks)
# ---------------------------------------------------------------------------

PREFS_FILE="${CONFIG_DIR}/pipeline_preferences.json"
if [[ -f "$PREFS_FILE" ]]; then
    TOP_N=$(python3 -c "import json; print(json.load(open('$PREFS_FILE'))['pipeline']['top_n_findings'])" 2>/dev/null || echo "20")
    EXCLUDE_CATS=$(python3 -c "import json; print(' '.join(json.load(open('$PREFS_FILE'))['pipeline']['exclude_categories']))" 2>/dev/null || echo "benchmarks")
else
    TOP_N=20
    EXCLUDE_CATS="benchmarks"
fi

# ---------------------------------------------------------------------------
# Run directory + log setup
# ---------------------------------------------------------------------------

RUN_TS=$(date +%Y%m%d_%H%M%S)
RUN_DIR="$REPO_DIR/runs/$RUN_TS"
LOG_FILE="$REPO_DIR/logs/pipeline-$RUN_TS.log"
mkdir -p "$RUN_DIR" "$REPO_DIR/logs"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

STAGES_COMPLETED=()
CURRENT_STAGE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_stage() {
    local name="$1"; shift
    CURRENT_STAGE="$name"
    local start
    start=$(date +%s)
    log "INFO" "=== $name ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "$name SKIPPED (dry-run)"
        STAGES_COMPLETED+=("$name")
        return 0
    fi

    local rc=0
    "$@" || rc=$?
    local duration=$(( $(date +%s) - start ))
    log "INFO" "$name completed — ${duration}s, exit=$rc"
    STAGES_COMPLETED+=("$name")
    return $rc
}

notify() {
    "$SCRIPTS_DIR/notify.sh" --message "$1" 2>/dev/null || true
}

handle_fatal_failure() {
    write_pipeline_summary 0 0 0
    notify "Pipeline FAILED at $CURRENT_STAGE"
    exit 1
}

write_pipeline_summary() {
    local findings_processed="${1:-0}"
    local prs_created="${2:-0}"
    local failures="${3:-0}"
    local duration="${4:-$(( $(date +%s) - PIPELINE_START ))}"

    python3 -c "
import json
from datetime import datetime, timezone

summary = {
    'stage': 'pipeline_orchestrator',
    'run_id': '$RUN_TS',
    'findings_processed': $findings_processed,
    'prs_created': $prs_created,
    'failures': $failures,
    'stages_completed': $(python3 -c "import json; print(json.dumps([$(printf '"%s",' "${STAGES_COMPLETED[@]}" | sed 's/,$//')]))" 2>/dev/null || echo '[]'),
    'duration_seconds': $duration,
    'timestamp': datetime.now(timezone.utc).isoformat()
}
with open('$RUN_DIR/pipeline_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
"
    log "INFO" "Pipeline summary written"
}

log "INFO" "Pipeline started — run: $RUN_TS, builder: $BUILDER_DIR"

# ─── PHASE 1: Pre-flight ──────────────────────────────────────────────────

run_stage "health_check" \
    "$SCRIPTS_DIR/health_check.sh" \
        --builder-dir "$BUILDER_DIR" \
        --config "$CONFIG_DIR/thresholds.json" \
        --output "$RUN_DIR" \
    || { notify "Pipeline FAILED: health check"; write_pipeline_summary 0 0 0; exit 1; }

# ─── PHASE 2: Discovery ───────────────────────────────────────────────────

run_stage "stage1_parse_findings" \
    "$SCRIPTS_DIR/stage1-parse-findings.sh" \
        --builder-dir "$BUILDER_DIR" \
        --config "$CONFIG_DIR/thresholds.json" \
        --tv-dir "$TV_DIR" \
        --output "$RUN_DIR"

FINDINGS_COUNT=$(python3 -c "import json; print(json.load(open('$RUN_DIR/findings.json'))['stats']['filtered_findings'])" 2>/dev/null || echo "0")

if [[ "$FINDINGS_COUNT" -eq 0 ]]; then
    log "INFO" "No actionable findings — product is healthy"
    write_pipeline_summary 0 0 0
    "$SCRIPTS_DIR/notify.sh" --message "No findings — product is healthy" 2>/dev/null || true
    exit 0
fi

log "INFO" "Found $FINDINGS_COUNT findings — analyzing product impact"

run_stage "prioritize" \
    python3 "$SCRIPTS_DIR/prioritize_findings.py" \
        --findings "$RUN_DIR/findings.json" \
        --category-map "$CONFIG_DIR/category_engine_map.json" \
        --engine-graph "$CONFIG_DIR/engine_graph.json" \
        --output "$RUN_DIR/prioritized_findings.json" \
        --top-n "$TOP_N" \
        --exclude-categories $EXCLUDE_CATS

# Check if any actionable findings survived prioritization
PRIORITIZED_COUNT=$(python3 -c "import json; print(json.load(open('$RUN_DIR/prioritized_findings.json'))['total_output'])" 2>/dev/null || echo "0")

if [[ "$PRIORITIZED_COUNT" -eq 0 ]]; then
    log "INFO" "No actionable findings after prioritization — product is healthy"
    write_pipeline_summary 0 0 0
    "$SCRIPTS_DIR/notify.sh" --message "No actionable findings — product is healthy" 2>/dev/null || true
    exit 0
fi

log "INFO" "$PRIORITIZED_COUNT actionable findings prioritized for implementation"

# ─── PHASE 3: Architecture Analysis ───────────────────────────────────────

run_stage "stage2_impact_analysis" \
    "$SCRIPTS_DIR/stage2-impact-analysis.sh" \
        --findings "$RUN_DIR/prioritized_findings.json" \
        --engine-graph "$CONFIG_DIR/engine_graph.json" \
        --category-map "$CONFIG_DIR/category_engine_map.json" \
        --packages-dir "$PACKAGES_DIR" \
        --config "$CONFIG_DIR/thresholds.json" \
        --output "$RUN_DIR" \
    || { log "ERROR" "Impact analysis failed — cannot assess product impact"; handle_fatal_failure; }

run_stage "stage3_integration_design" \
    "$SCRIPTS_DIR/stage3-integration-design.sh" \
        --impact-dir "$RUN_DIR" \
        --packages-dir "$PACKAGES_DIR" \
        --claude-md "${BUILDER_DIR}/CLAUDE.md" \
        --output "$RUN_DIR" \
    || { log "ERROR" "Integration design failed"; handle_fatal_failure; }

# ─── PHASE 4: PRD Generation (dogfood) ────────────────────────────────────

run_stage "stage4_prd_generation" \
    "$SCRIPTS_DIR/stage4-prd-generation.sh" \
        --run-dir "$RUN_DIR" \
        --packages-dir "$PACKAGES_DIR" \
        --builder-dir "$BUILDER_DIR" \
        --engine-graph "$CONFIG_DIR/engine_graph.json" \
        --category-map "$CONFIG_DIR/category_engine_map.json" \
        --config "$CONFIG_DIR/thresholds.json" \
        --output "$RUN_DIR" \
    || { log "ERROR" "PRD generation failed"; handle_fatal_failure; }

# ─── PHASE 5: Implementation + Verification (per-finding) ─────────────────

# Find which findings made it through Stages 2-4
ACCEPTED_FIDS=()
for vf in "$RUN_DIR"/validation_stage4_*.json; do
    [[ -f "$vf" ]] || continue
    result=$(python3 -c "import json; d=json.load(open('$vf')); print(d.get('result',''))" 2>/dev/null || echo "")
    fid=$(python3 -c "import json; d=json.load(open('$vf')); print(d.get('finding_id',''))" 2>/dev/null || echo "")
    [[ "$result" == "ACCEPTED" && -n "$fid" ]] && ACCEPTED_FIDS+=("$fid")
done

log "INFO" "${#ACCEPTED_FIDS[@]} findings accepted for implementation"

SUCCESS_FIDS=()
FAILED_FIDS=()

for FID in "${ACCEPTED_FIDS[@]}"; do
    log "INFO" "Implementing improvement: $FID"
    FINDING_START=$(date +%s)

    retry_exit=0
    "$SCRIPTS_DIR/retry_orchestrator.sh" \
        --run-dir "$RUN_DIR" \
        --builder-dir "$BUILDER_DIR" \
        --engine-graph "$CONFIG_DIR/engine_graph.json" \
        --config "$CONFIG_DIR/thresholds.json" \
        --patterns "$CONFIG_DIR/prohibited_patterns.txt" \
        --finding-id "$FID" \
        --output "$RUN_DIR" \
        || retry_exit=$?

    FINDING_DURATION=$(( $(date +%s) - FINDING_START ))

    if [[ "$retry_exit" -eq 0 ]]; then
        SUCCESS_FIDS+=("$FID")
        log "INFO" "Finding $FID: ACCEPTED in ${FINDING_DURATION}s"
    else
        FAILED_FIDS+=("$FID")
        log "WARN" "Finding $FID: FAILED after ${FINDING_DURATION}s"
    fi

    # Record per-finding timing
    echo "{\"finding_id\":\"$FID\",\"duration_seconds\":$FINDING_DURATION,\"result\":\"$([ $retry_exit -eq 0 ] && echo ACCEPTED || echo FAILED)\"}" >> "$RUN_DIR/finding_timings.jsonl"
done

# ─── PHASE 6: Quality Assurance ───────────────────────────────────────────

if [[ ${#SUCCESS_FIDS[@]} -gt 0 ]]; then

    run_stage "stage8_benchmark" \
        "$SCRIPTS_DIR/stage8-benchmark.sh" \
            --config "$CONFIG_DIR/thresholds.json" \
            --baselines "$REPO_DIR/benchmarks/baselines" \
            --output "$RUN_DIR" \
        || log "WARN" "Benchmark regression detected — PRs still created for review"

    run_stage "stage9_deployment" \
        "$SCRIPTS_DIR/stage9-deployment.sh" \
            --builder-dir "$BUILDER_DIR" \
            --output "$RUN_DIR" \
        || log "WARN" "Deployment simulation failed — PRs created but need review"
fi

# ─── PHASE 7: Delivery ───────────────────────────────────────────────────

PRS_CREATED=0
for FID in "${SUCCESS_FIDS[@]}"; do
    if [[ -f "$PREFS_FILE" ]]; then
        BRANCH=$(python3 -c "import json; print(json.load(open('$PREFS_FILE'))['git']['feature_branch_pattern'].format(finding_id='$FID'))" 2>/dev/null || echo "pipeline/improvement-${FID}")
    else
        BRANCH="pipeline/improvement-${FID}"
    fi
    run_stage "stage10_pr_$FID" \
        "$SCRIPTS_DIR/stage10-pull-request.sh" \
            --run-dir "$RUN_DIR" \
            --builder-dir "$BUILDER_DIR" \
            --engine-graph "$CONFIG_DIR/engine_graph.json" \
            --finding-id "$FID" \
            --branch "$BRANCH" \
            --output "$RUN_DIR" \
        && PRS_CREATED=$((PRS_CREATED + 1)) \
        || log "WARN" "PR creation failed for $FID"
done

# ─── PHASE 8: Product Improvement Report ─────────────────────────────────

DURATION=$(( $(date +%s) - PIPELINE_START ))
write_pipeline_summary "${#ACCEPTED_FIDS[@]}" "$PRS_CREATED" "${#FAILED_FIDS[@]}" "$DURATION"

python3 "$SCRIPTS_DIR/compose_improvement_report.py" \
    --run-dir "$RUN_DIR" \
    --engine-graph "$CONFIG_DIR/engine_graph.json" \
    --category-map "$CONFIG_DIR/category_engine_map.json" \
    --baselines "$REPO_DIR/benchmarks/baselines" \
    --output "$RUN_DIR/improvement_report.json" \
    || log "WARN" "Improvement report generation failed"

# ─── Summary + Notification ──────────────────────────────────────────────

"$SCRIPTS_DIR/notify.sh" --run-dir "$RUN_DIR" 2>/dev/null || true

log "INFO" "Pipeline complete — ${PRS_CREATED} PRs, ${#FAILED_FIDS[@]} failures, ${DURATION}s"
