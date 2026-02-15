#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# update-baselines.sh — Refresh benchmark baselines
# ============================================================================
#
# Updates benchmark baselines after an accepted improvement is merged.
# Archives previous baselines before overwriting.
#
# Usage:
#   scripts/update-baselines.sh \
#       --runs-dir runs \
#       --output benchmarks/baselines \
#       [--source-run runs/20260215-120000]
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="update_baselines"

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

RUNS_DIR=""
OUTPUT_DIR=""
SOURCE_RUN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs-dir)
            RUNS_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --source-run)
            SOURCE_RUN="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$RUNS_DIR" ]]; then
    log "ERROR" "Missing required argument: --runs-dir"
    exit 1
fi
if [[ -z "$OUTPUT_DIR" ]]; then
    log "ERROR" "Missing required argument: --output"
    exit 1
fi

# ---------------------------------------------------------------------------
# Find source run
# ---------------------------------------------------------------------------

if [[ -z "$SOURCE_RUN" ]]; then
    log "INFO" "No --source-run specified, finding most recent passing run"

    # Find most recent run with benchmark_report.json where overall_result is PASS
    LATEST_PASS=""
    for run_dir in $(ls -rd "$RUNS_DIR"/*/ 2>/dev/null); do
        report="$run_dir/benchmark_report.json"
        if [[ -f "$report" ]]; then
            result=$(python3 -c "import json; print(json.load(open('$report')).get('overall_result', ''))" 2>/dev/null || echo "")
            if [[ "$result" == "PASS" ]]; then
                LATEST_PASS="$run_dir"
                break
            fi
        fi
    done

    if [[ -z "$LATEST_PASS" ]]; then
        log "ERROR" "No passing run found in $RUNS_DIR"
        exit 1
    fi

    SOURCE_RUN="$LATEST_PASS"
    log "INFO" "Using most recent passing run: $SOURCE_RUN"
else
    if [[ ! -d "$SOURCE_RUN" ]]; then
        log "ERROR" "Source run directory not found: $SOURCE_RUN"
        exit 1
    fi
fi

log "INFO" "Source run: $SOURCE_RUN"

# ---------------------------------------------------------------------------
# Archive existing baselines
# ---------------------------------------------------------------------------

if [[ -d "$OUTPUT_DIR" ]] && [[ "$(ls -A "$OUTPUT_DIR" 2>/dev/null | grep -v .gitkeep)" ]]; then
    ARCHIVE_DIR="$(dirname "$OUTPUT_DIR")/baselines_archive/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ARCHIVE_DIR"
    log "INFO" "Archiving existing baselines to $ARCHIVE_DIR"

    # Copy existing baselines to archive (exclude .gitkeep)
    for item in "$OUTPUT_DIR"/*/; do
        [[ -d "$item" ]] && cp -r "$item" "$ARCHIVE_DIR/"
    done
    if [[ -f "$OUTPUT_DIR/LAST_UPDATED.txt" ]]; then
        cp "$OUTPUT_DIR/LAST_UPDATED.txt" "$ARCHIVE_DIR/"
    fi

    log "INFO" "Archive complete"
fi

# ---------------------------------------------------------------------------
# Copy new baselines from source run
# ---------------------------------------------------------------------------

# Look for generated outputs or direct benchmark outputs
GENERATED_DIR="$SOURCE_RUN/generated"
if [[ -d "$GENERATED_DIR" ]]; then
    SOURCE_BENCHMARKS="$GENERATED_DIR"
else
    SOURCE_BENCHMARKS="$SOURCE_RUN"
fi

COPIED=0
for bench_dir in "$SOURCE_BENCHMARKS"/*/; do
    [[ ! -d "$bench_dir" ]] && continue
    bench_name=$(basename "$bench_dir")

    # Skip non-benchmark directories
    [[ "$bench_name" == "generated" ]] && continue

    # Must have metrics.json
    if [[ ! -f "$bench_dir/metrics.json" ]]; then
        log "WARN" "Skipping $bench_name — no metrics.json"
        continue
    fi

    target_dir="$OUTPUT_DIR/$bench_name"
    mkdir -p "$target_dir"

    # Copy all output files
    cp -r "$bench_dir"/* "$target_dir/"
    COPIED=$((COPIED + 1))
    log "INFO" "Copied baseline: $bench_name"
done

# ---------------------------------------------------------------------------
# Write LAST_UPDATED.txt
# ---------------------------------------------------------------------------

METRICS_SUMMARY=""
for baseline_dir in "$OUTPUT_DIR"/*/; do
    [[ ! -d "$baseline_dir" ]] && continue
    bench_name=$(basename "$baseline_dir")
    if [[ -f "$baseline_dir/metrics.json" ]]; then
        score=$(python3 -c "
import json
m = json.load(open('$baseline_dir/metrics.json'))
v = m.get('verification', {})
print(v.get('overall_score', 'N/A') if v else 'N/A')
" 2>/dev/null || echo "N/A")
        METRICS_SUMMARY="${METRICS_SUMMARY}  ${bench_name}: overall_score=${score}\n"
    fi
done

cat > "$OUTPUT_DIR/LAST_UPDATED.txt" <<EOF
Baselines updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source run: $SOURCE_RUN
Benchmarks copied: $COPIED

Metrics summary:
$(echo -e "$METRICS_SUMMARY")
EOF

log "INFO" "Baselines updated — $COPIED benchmarks copied"
log "INFO" "LAST_UPDATED.txt written to $OUTPUT_DIR"
