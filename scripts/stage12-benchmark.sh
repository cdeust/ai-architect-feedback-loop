#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage12-benchmark.sh — Stage 12: Quality Benchmark Gate
# ============================================================================
#
# Two-mode quality gate that uses the product's own verification metrics
# for regression detection.
#
# Mode 1: compare (default, fast)
#   Takes pre-generated PRD outputs and compares against stored baselines.
#
# Mode 2: generate (slow)
#   For each benchmark input, invokes PRD generation via Claude Code CLI,
#   captures outputs, extracts metrics, and compares.
#
# Usage:
#   scripts/stage12-benchmark.sh \
#       --config config/thresholds.json \
#       --baselines benchmarks/baselines \
#       --output runs/20260215-120000 \
#       [--mode compare|generate] \
#       [--current-dir path/to/current/outputs]
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage12_quality_gate"

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------

log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

# Stub run_with_timeout for ai_invoke (stage8 uses its own pattern)
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

CONFIG_PATH=""
BASELINES_DIR=""
OUTPUT_DIR=""
MODE="compare"
CURRENT_DIR=""
INPUTS_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --baselines)
            BASELINES_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --current-dir)
            CURRENT_DIR="$2"
            shift 2
            ;;
        --inputs-dir)
            INPUTS_DIR="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$BASELINES_DIR" ]]; then
    log "ERROR" "Missing required argument: --baselines"
    exit 1
fi
if [[ -z "$OUTPUT_DIR" ]]; then
    log "ERROR" "Missing required argument: --output"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Default inputs dir
if [[ -z "$INPUTS_DIR" ]]; then
    INPUTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/benchmarks/inputs"
fi

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

REGRESSION_THRESHOLD=0.05
if [[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]]; then
    REGRESSION_THRESHOLD=$(python3 -c "
import json
with open('$CONFIG_PATH') as f:
    c = json.load(f)
print(c.get('stage_12', {}).get('regression_threshold', c.get('stage_8', {}).get('regression_threshold', 0.05)))
")
fi

log "INFO" "Stage 12 started — mode=$MODE, threshold=$REGRESSION_THRESHOLD"
log "INFO" "Baselines: $BASELINES_DIR"
log "INFO" "Output: $OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Compare mode: compare current metrics against baselines
# ---------------------------------------------------------------------------

run_compare() {
    local current_dir="$1"
    local baselines_dir="$2"
    local output_dir="$3"
    local threshold="$4"

    python3 - "$current_dir" "$baselines_dir" "$output_dir" "$threshold" <<'PYEOF'
import json
import os
import sys
from datetime import datetime, timezone

current_dir, baselines_dir, output_dir, threshold_str = sys.argv[1:5]
threshold = float(threshold_str)

benchmarks_result = []
total_checks = 0
improved = 0
maintained = 0
regressed = 0
overall_result = "PASS"

# Find all baseline directories
if not os.path.isdir(baselines_dir):
    print(json.dumps({"error": "Baselines directory not found"}), file=sys.stderr)
    sys.exit(1)

baseline_dirs = []
for entry in sorted(os.listdir(baselines_dir)):
    entry_path = os.path.join(baselines_dir, entry)
    if os.path.isdir(entry_path) and os.path.isfile(os.path.join(entry_path, "metrics.json")):
        baseline_dirs.append(entry)

if not baseline_dirs:
    print(json.dumps({"error": "No baseline metrics found"}), file=sys.stderr)
    sys.exit(1)

for bench_name in baseline_dirs:
    baseline_metrics_path = os.path.join(baselines_dir, bench_name, "metrics.json")
    current_metrics_path = os.path.join(current_dir, bench_name, "metrics.json")

    with open(baseline_metrics_path) as f:
        baseline = json.load(f)

    if not os.path.isfile(current_metrics_path):
        # No current metrics for this benchmark - skip
        continue

    with open(current_metrics_path) as f:
        current = json.load(f)

    # Extract dimension values
    dimensions = {}

    # Dimension 1: verification_score (from verification.overall_score)
    b_vscore = (baseline.get("verification", {}) or {}).get("overall_score")
    c_vscore = (current.get("verification", {}) or {}).get("overall_score")
    if b_vscore is not None and c_vscore is not None:
        delta = c_vscore - b_vscore
        if delta < -threshold:
            result = "REGRESSED"
            regressed += 1
            overall_result = "FAIL"
        elif delta > threshold:
            result = "IMPROVED"
            improved += 1
        else:
            result = "MAINTAINED"
            maintained += 1
        total_checks += 1
        dimensions["verification_score"] = {
            "baseline": round(b_vscore, 4),
            "current": round(c_vscore, 4),
            "delta": round(delta, 4),
            "result": result,
        }

    # Dimension 2: completeness (from verification.completeness.coverage)
    b_comp = (baseline.get("verification", {}) or {}).get("completeness", {}).get("coverage")
    c_comp = (current.get("verification", {}) or {}).get("completeness", {}).get("coverage")
    if b_comp is not None and c_comp is not None:
        delta = c_comp - b_comp
        if delta < -threshold:
            result = "REGRESSED"
            regressed += 1
            overall_result = "FAIL"
        elif delta > threshold:
            result = "IMPROVED"
            improved += 1
        else:
            result = "MAINTAINED"
            maintained += 1
        total_checks += 1
        dimensions["completeness"] = {
            "baseline": round(b_comp, 4),
            "current": round(c_comp, 4),
            "delta": round(delta, 4),
            "result": result,
        }

    # Dimension 3: cross_ref_integrity (from traceability)
    b_xref = (baseline.get("traceability", {}) or {}).get("cross_ref_integrity")
    c_xref = (current.get("traceability", {}) or {}).get("cross_ref_integrity")
    if b_xref is not None and c_xref is not None:
        delta = c_xref - b_xref
        if delta < -threshold:
            result = "REGRESSED"
            regressed += 1
            overall_result = "FAIL"
        elif delta > threshold:
            result = "IMPROVED"
            improved += 1
        else:
            result = "MAINTAINED"
            maintained += 1
        total_checks += 1
        dimensions["cross_ref_integrity"] = {
            "baseline": round(b_xref, 4),
            "current": round(c_xref, 4),
            "delta": round(delta, 4),
            "result": result,
        }

    # Dimension 4: ac_coverage (from traceability or verification)
    b_ac = (baseline.get("traceability", {}) or {}).get("ac_to_test_coverage")
    c_ac = (current.get("traceability", {}) or {}).get("ac_to_test_coverage")
    if b_ac is not None and c_ac is not None:
        delta = c_ac - b_ac
        if delta < -threshold:
            result = "REGRESSED"
            regressed += 1
            overall_result = "FAIL"
        elif delta > threshold:
            result = "IMPROVED"
            improved += 1
        else:
            result = "MAINTAINED"
            maintained += 1
        total_checks += 1
        dimensions["ac_coverage"] = {
            "baseline": round(b_ac, 4),
            "current": round(c_ac, 4),
            "delta": round(delta, 4),
            "result": result,
        }

    if dimensions:
        benchmarks_result.append({
            "input": bench_name,
            "dimensions": dimensions,
        })

report = {
    "stage": "quality_gate",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "overall_result": overall_result,
    "mode": "compare",
    "regression_threshold": threshold,
    "benchmarks": benchmarks_result,
    "summary": {
        "total_checks": total_checks,
        "improved": improved,
        "maintained": maintained,
        "regressed": regressed,
    },
}

report_path = os.path.join(output_dir, "benchmark_report.json")
with open(report_path, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')

print(json.dumps({
    "stage": "stage12_quality_gate",
    "mode": "compare",
    "overall_result": overall_result,
    "total_checks": total_checks,
    "improved": improved,
    "maintained": maintained,
    "regressed": regressed,
}))

if overall_result == "FAIL":
    sys.exit(1)
PYEOF
}

# ---------------------------------------------------------------------------
# Generate mode: generate PRDs then compare
# ---------------------------------------------------------------------------

run_generate() {
    local inputs_dir="$1"
    local baselines_dir="$2"
    local output_dir="$3"
    local threshold="$4"

    log "INFO" "Generate mode: processing benchmark inputs from $inputs_dir"

    local gen_dir="$output_dir/generated"
    mkdir -p "$gen_dir"

    # Process each benchmark input
    for input_file in "$inputs_dir"/*.json; do
        [[ ! -f "$input_file" ]] && continue
        local bench_name
        bench_name=$(basename "$input_file" .json)
        local bench_output_dir="$gen_dir/$bench_name"
        mkdir -p "$bench_output_dir"

        log "INFO" "Generating PRD for benchmark: $bench_name"

        # Extract prompt components from benchmark input
        local title description context requirements
        title=$(python3 -c "import json; print(json.load(open('$input_file'))['title'])")
        description=$(python3 -c "import json; print(json.load(open('$input_file'))['description'])")
        context=$(python3 -c "import json; print(json.load(open('$input_file'))['context'])")
        requirements=$(python3 -c "
import json
reqs = json.load(open('$input_file')).get('requirements', [])
print('; '.join(r['description'] for r in reqs))
")

        # Invoke AI for PRD generation
        local prompt="Generate a PRD for: ${title}. ${description}. Context type: ${context}. Requirements: ${requirements}"

        # Write prompt to file for ai_invoke
        local prompt_file="$bench_output_dir/prompt.md"
        echo "$prompt" > "$prompt_file"

        local gen_exit=0
        ai_invoke "$prompt_file" "$bench_output_dir/prd.md" "stage12" "$bench_name" \
            --output-format text --max-turns 15 \
            || gen_exit=$?

        if [[ $gen_exit -eq 42 ]]; then
            log "INFO" "Session mode: skipping $bench_name (prompt written, awaiting response)"
            continue
        elif [[ $gen_exit -ne 0 ]]; then
            log "WARN" "Generation failed for $bench_name (exit=$gen_exit)"
            continue
        fi

        # Look for companion files in the output directory
        # (Claude Code may produce them alongside)

        # Extract metrics from whatever was generated
        local metrics_args="--output $bench_output_dir/metrics.json"
        if [[ -f "$bench_output_dir/prd.md" ]]; then
            metrics_args="$metrics_args --prd $bench_output_dir/prd.md"
        fi
        if [[ -f "$bench_output_dir/prd-verification.md" ]]; then
            metrics_args="$metrics_args --verification $bench_output_dir/prd-verification.md"
        fi
        if [[ -f "$bench_output_dir/prd-tests.md" ]]; then
            metrics_args="$metrics_args --tests $bench_output_dir/prd-tests.md"
        fi

        python3 "$SCRIPT_DIR/extract_prd_metrics.py" $metrics_args \
            --input "$input_file" || true

        log "INFO" "Metrics extracted for $bench_name"
    done

    # Now compare generated metrics against baselines
    if [[ -d "$baselines_dir" ]]; then
        run_compare "$gen_dir" "$baselines_dir" "$output_dir" "$threshold"
    else
        log "WARN" "No baselines directory found — skipping comparison"
    fi
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

case "$MODE" in
    compare)
        if [[ -z "$CURRENT_DIR" ]]; then
            log "ERROR" "Compare mode requires --current-dir"
            exit 1
        fi
        run_compare "$CURRENT_DIR" "$BASELINES_DIR" "$OUTPUT_DIR" "$REGRESSION_THRESHOLD"
        ;;
    generate)
        run_generate "$INPUTS_DIR" "$BASELINES_DIR" "$OUTPUT_DIR" "$REGRESSION_THRESHOLD"
        ;;
    *)
        log "ERROR" "Unknown mode: $MODE (expected: compare|generate)"
        exit 1
        ;;
esac

RESULT=$?
if [[ $RESULT -eq 0 ]]; then
    log "INFO" "Stage 12 completed — PASS"
else
    log "ERROR" "Stage 12 completed — FAIL"
fi

exit $RESULT
