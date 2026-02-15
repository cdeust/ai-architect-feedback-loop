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
#       --builder-dir ../ai-architect-prd-builder \
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

check_with_msg "ERROR" "claude CLI" \
    "claude CLI not found — required for Stages 2-5, 7" \
    command -v claude

check_with_msg "ERROR" "gh CLI" \
    "gh CLI not found — required for Stage 10 PR creation" \
    command -v gh

check_with_msg "ERROR" "gh authenticated" \
    "gh not authenticated — run: gh auth login" \
    gh auth status

check_with_msg "ERROR" "swift" \
    "swift not found — required for product build verification" \
    command -v swift

check_with_msg "ERROR" "swiftc" \
    "swiftc not found — required for product build" \
    command -v swiftc

check_with_msg "ERROR" "make" \
    "make not found — required for build-library, test-all, distribute" \
    command -v make

check_with_msg "ERROR" "python3" \
    "python3 not found — required for metric extraction and validation" \
    command -v python3

check_with_msg "ERROR" "jq" \
    "jq not found — required for JSON processing" \
    command -v jq

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

    # On main branch check
    CURRENT_BRANCH=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        ERRORS=$((ERRORS + 1))
        log "ERROR" "Builder not on main (current: $CURRENT_BRANCH) — pipeline creates branches from main"
        CHECKS+=("{\"check\":\"On main branch\",\"result\":\"FAIL\",\"level\":\"ERROR\"}")
    else
        log "INFO" "On main branch — OK"
        CHECKS+=("{\"check\":\"On main branch\",\"result\":\"OK\",\"level\":\"INFO\"}")
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
    if [[ "$ENGINE_COUNT" -eq 9 ]]; then
        log "INFO" "Engine graph has 9 engines — OK"
        CHECKS+=("{\"check\":\"Engine graph engine count\",\"result\":\"OK\",\"level\":\"INFO\"}")
    else
        ERRORS=$((ERRORS + 1))
        log "ERROR" "Engine graph incomplete — expected 9 engines, got $ENGINE_COUNT"
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
