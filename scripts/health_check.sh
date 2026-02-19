#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# health_check.sh — Product Pre-Flight Validation
# ============================================================================
#
# Validates toolchain, product state, and pipeline infrastructure before
# running the nightly improvement cycle. Groups checks by concern and
# accumulates all errors (non-fail-fast) so the operator sees everything
# that needs fixing in a single pass.
#
# Usage:
#   scripts/health_check.sh \
#       --builder-dir /path/to/target-product \
#       [--config config/thresholds.json] \
#       [--output runs/TIMESTAMP]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGE_NAME="health_check"

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

BUILDER_DIR=""
CONFIG_PATH=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --builder-dir)
            BUILDER_DIR="$2"
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
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$BUILDER_DIR" ]]; then
    log "ERROR" "Missing required argument: --builder-dir"
    exit 1
fi

# ---------------------------------------------------------------------------
# Check accumulation (non-fail-fast)
# ---------------------------------------------------------------------------

ERRORS=0
WARNINGS=0
CHECKS=()

check() {
    local level="$1" desc="$2"
    shift 2
    if "$@" > /dev/null 2>&1; then
        log "INFO" "$desc — OK"
        CHECKS+=("{\"check\":\"$desc\",\"result\":\"OK\",\"level\":\"INFO\"}")
    else
        if [[ "$level" == "ERROR" ]]; then
            ERRORS=$((ERRORS + 1))
        fi
        if [[ "$level" == "WARN" ]]; then
            WARNINGS=$((WARNINGS + 1))
        fi
        log "$level" "$desc"
        CHECKS+=("{\"check\":\"$desc\",\"result\":\"FAIL\",\"level\":\"$level\"}")
    fi
}

check_with_msg() {
    local level="$1" desc="$2" fail_msg="$3"
    shift 3
    if "$@" > /dev/null 2>&1; then
        log "INFO" "$desc — OK"
        CHECKS+=("{\"check\":\"$desc\",\"result\":\"OK\",\"level\":\"INFO\"}")
    else
        if [[ "$level" == "ERROR" ]]; then
            ERRORS=$((ERRORS + 1))
        fi
        if [[ "$level" == "WARN" ]]; then
            WARNINGS=$((WARNINGS + 1))
        fi
        log "$level" "$fail_msg"
        CHECKS+=("{\"check\":\"$desc\",\"result\":\"FAIL\",\"level\":\"$level\",\"message\":\"$fail_msg\"}")
    fi
}

log "INFO" "Health check started — builder: $BUILDER_DIR"

# ─── A. Toolchain (required binaries) ────────────────────────────────────

log "INFO" "=== Toolchain checks ==="

# Read required tools from project config
PROJECT_CONFIG="$REPO_DIR/config/project.json"
REQUIRED_TOOLS="python3 git gh jq claude"
if [[ -f "$PROJECT_CONFIG" ]]; then
    REQUIRED_TOOLS=$(python3 -c "import json; print(' '.join(json.load(open('$PROJECT_CONFIG')).get('required_tools', ['python3','git','gh','jq','claude'])))" 2>/dev/null || echo "python3 git gh jq claude")
fi

for tool in $REQUIRED_TOOLS; do
    check_with_msg "ERROR" "$tool" \
        "$tool not found — required by pipeline" \
        command -v "$tool"
done

check_with_msg "ERROR" "gh authenticated" \
    "gh not authenticated — run: gh auth login" \
    gh auth status

# ─── B. Product State (builder repo health) ──────────────────────────────

log "INFO" "=== Product state checks ==="

check_with_msg "ERROR" "Builder dir exists" \
    "Builder directory not found: $BUILDER_DIR" \
    test -d "$BUILDER_DIR"

# Only check git state if builder dir exists
if [[ -d "$BUILDER_DIR" ]]; then
    # Git clean check
    if [[ -n "$(git -C "$BUILDER_DIR" status --porcelain 2>/dev/null)" ]]; then
        ERRORS=$((ERRORS + 1))
        log "ERROR" "Uncommitted changes in builder — pipeline modifies code, must start clean"
        CHECKS+=("{\"check\":\"Git clean\",\"result\":\"FAIL\",\"level\":\"ERROR\"}")
    else
        log "INFO" "Git clean — OK"
        CHECKS+=("{\"check\":\"Git clean\",\"result\":\"OK\",\"level\":\"INFO\"}")
    fi

    # On base branch check (configurable via project.json base_branch, defaults to "main")
    BASE_BRANCH="main"
    if [[ -f "$PROJECT_CONFIG" ]]; then
        BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('base_branch', 'main'))" 2>/dev/null || echo "main")
    fi
    CURRENT_BRANCH=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
        ERRORS=$((ERRORS + 1))
        log "ERROR" "Builder not on $BASE_BRANCH (current: $CURRENT_BRANCH) — pipeline creates branches from $BASE_BRANCH"
        CHECKS+=("{\"check\":\"On $BASE_BRANCH branch\",\"result\":\"FAIL\",\"level\":\"ERROR\"}")
    else
        log "INFO" "On $BASE_BRANCH branch — OK"
        CHECKS+=("{\"check\":\"On $BASE_BRANCH branch\",\"result\":\"OK\",\"level\":\"INFO\"}")
    fi

    # Stale pipeline branches (warning only)
    STALE_BRANCHES=$(git -C "$BUILDER_DIR" branch --list 'pipeline/improvement-*' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$STALE_BRANCHES" -gt 0 ]]; then
        WARNINGS=$((WARNINGS + 1))
        log "WARN" "WARN: $STALE_BRANCHES stale pipeline branches found — consider cleanup"
        CHECKS+=("{\"check\":\"Stale pipeline branches\",\"result\":\"WARN\",\"level\":\"WARN\"}")
    else
        log "INFO" "No stale pipeline branches — OK"
        CHECKS+=("{\"check\":\"Stale pipeline branches\",\"result\":\"OK\",\"level\":\"INFO\"}")
    fi
fi

# ─── C. Pipeline Infrastructure ──────────────────────────────────────────

log "INFO" "=== Pipeline infrastructure checks ==="

# Engine graph
ENGINE_GRAPH="$REPO_DIR/config/engine_graph.json"
check_with_msg "ERROR" "Engine graph exists" \
    "Engine graph not found — run: make update-engine-graph" \
    test -f "$ENGINE_GRAPH"

if [[ -f "$ENGINE_GRAPH" ]]; then
    ENGINE_COUNT=$(python3 -c "import json; print(len(json.load(open('$ENGINE_GRAPH'))['engines']))" 2>/dev/null || echo "0")
    if [[ "$ENGINE_COUNT" -ge 1 ]]; then
        log "INFO" "Engine graph has $ENGINE_COUNT module(s) — OK"
        CHECKS+=("{\"check\":\"Engine graph engine count\",\"result\":\"OK\",\"level\":\"INFO\"}")
    else
        ERRORS=$((ERRORS + 1))
        log "ERROR" "Engine graph empty — expected >= 1 module, got $ENGINE_COUNT"
        CHECKS+=("{\"check\":\"Engine graph engine count\",\"result\":\"FAIL\",\"level\":\"ERROR\"}")
    fi
fi

# Category map
check_with_msg "ERROR" "Category engine map" \
    "Category engine map missing" \
    test -f "$REPO_DIR/config/category_engine_map.json"

# Baselines
BASELINES_DIR="$REPO_DIR/benchmarks/baselines"
BASELINE_COUNT=$(ls -1d "$BASELINES_DIR"/*/metrics.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "$BASELINE_COUNT" -ge 1 ]]; then
    log "INFO" "Baselines exist ($BASELINE_COUNT with metrics.json) — OK"
    CHECKS+=("{\"check\":\"Baselines exist\",\"result\":\"OK\",\"level\":\"INFO\"}")
else
    ERRORS=$((ERRORS + 1))
    log "ERROR" "No baselines found — run: make pipeline-generate-baselines"
    CHECKS+=("{\"check\":\"Baselines exist\",\"result\":\"FAIL\",\"level\":\"ERROR\"}")
fi

# Baseline freshness (warning only)
LAST_UPDATED="$BASELINES_DIR/LAST_UPDATED.txt"
if [[ -f "$LAST_UPDATED" ]]; then
    LAST_DATE=$(cat "$LAST_UPDATED" | head -1 | tr -d '[:space:]')
    if [[ -n "$LAST_DATE" ]]; then
        LAST_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_DATE" "+%s" 2>/dev/null || date -d "$LAST_DATE" "+%s" 2>/dev/null || echo "0")
        NOW_EPOCH=$(date "+%s")
        if [[ "$LAST_EPOCH" -gt 0 ]]; then
            DAYS_OLD=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
            if [[ "$DAYS_OLD" -gt 30 ]]; then
                WARNINGS=$((WARNINGS + 1))
                log "WARN" "WARN: Baselines stale (${DAYS_OLD} days old) — consider: make update-baselines"
                CHECKS+=("{\"check\":\"Baseline freshness\",\"result\":\"WARN\",\"level\":\"WARN\"}")
            else
                log "INFO" "Baselines fresh (${DAYS_OLD} days old) — OK"
                CHECKS+=("{\"check\":\"Baseline freshness\",\"result\":\"OK\",\"level\":\"INFO\"}")
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Health report output
# ---------------------------------------------------------------------------

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    CHECKS_JSON=$(printf '%s\n' "${CHECKS[@]}" | python3 -c "
import sys, json
checks = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            checks.append(json.loads(line))
        except json.JSONDecodeError:
            pass
report = {
    'stage': 'health_check',
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'builder_dir': '$BUILDER_DIR',
    'errors': $ERRORS,
    'warnings': $WARNINGS,
    'result': 'FAIL' if $ERRORS > 0 else 'PASS',
    'checks': checks
}
json.dump(report, sys.stdout, indent=2)
")
    echo "$CHECKS_JSON" > "$OUTPUT_DIR/health_report.json"
    log "INFO" "Health report written to $OUTPUT_DIR/health_report.json"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log "INFO" "Health check complete — errors: $ERRORS, warnings: $WARNINGS"

if [[ "$ERRORS" -gt 0 ]]; then
    log "ERROR" "Health check FAILED — $ERRORS error(s) must be resolved"
    exit 1
fi

if [[ "$WARNINGS" -gt 0 ]]; then
    log "WARN" "Health check PASSED with $WARNINGS warning(s)"
fi

exit 0
