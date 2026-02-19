#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage1-parse-findings.sh — Stage 1: Parse Technical Veil findings
# ============================================================================
#
# Triggers Technical Veil output parsing and prepares the run directory.
# Invokes parse_findings.py to filter findings by relevance and score.
#
# Usage (called by Makefile pipeline-stage1):
#   scripts/stage1-parse-findings.sh \
#       --builder-dir /path/to/target-product \
#       --config config/thresholds.json \
#       --output runs/20260211-120000 \
#       --tv-dir /path/to/TechnicalVeil
#
# Optional:
#   --tv-dir PATH      Path to TechnicalVeil markdown directory (date-organized)
#   --tv-date DATE     Date to parse from TV dir (YYYY-MM-DD or 'latest', default: latest)
#   --tv-input PATH    Explicit path to pre-built JSON file
#                      (default: looks in builder-dir/tv_output.json)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage1_parse_findings"

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
TV_INPUT=""
TV_DIR=""
TV_DATE="latest"

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
        --tv-input)
            TV_INPUT="$2"
            shift 2
            ;;
        --tv-dir)
            TV_DIR="$2"
            shift 2
            ;;
        --tv-date)
            TV_DATE="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$BUILDER_DIR" ]]; then
    log "ERROR" "Missing required argument: --builder-dir"
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    log "ERROR" "Missing required argument: --output"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve TV input path
# ---------------------------------------------------------------------------

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

log "INFO" "Stage 1 started"
log "INFO" "Builder dir: $BUILDER_DIR"
log "INFO" "Output dir: $OUTPUT_DIR"

# Priority 1: Convert TV markdown directory → JSON (if --tv-dir provided)
if [[ -n "$TV_DIR" && -d "$TV_DIR" ]]; then
    log "INFO" "Converting Technical Veil markdown from $TV_DIR (date: $TV_DATE)"
    TV_INPUT="$OUTPUT_DIR/tv_raw.json"
    python3 "$SCRIPT_DIR/tv_markdown_to_json.py" \
        --tv-dir "$TV_DIR" \
        --date "$TV_DATE" \
        --output "$TV_INPUT"
    log "INFO" "TV markdown converted to $TV_INPUT"

# Priority 2: Use explicit --tv-input JSON path
elif [[ -n "$TV_INPUT" && -f "$TV_INPUT" ]]; then
    log "INFO" "Using explicit TV input: $TV_INPUT"

# Priority 3: Look for tv_output.json in builder dir
elif [[ -f "$BUILDER_DIR/tv_output.json" ]]; then
    TV_INPUT="$BUILDER_DIR/tv_output.json"
    log "INFO" "Found TV output at $TV_INPUT"

# No TV source found — produce empty findings and exit cleanly
else
    log "INFO" "No TV source found — nothing to process"

    python3 "$SCRIPT_DIR/parse_findings.py" \
        --input <(echo '{"findings": []}') \
        --output "$OUTPUT_DIR/findings.json" \
        ${CONFIG_PATH:+--config "$CONFIG_PATH"}

    FINDINGS_COUNT=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/findings.json'))['stats']['filtered_findings'])")
    log "INFO" "No actionable findings"
    log "INFO" "Stage 1 completed — findings_count: $FINDINGS_COUNT"
    exit 0
fi

log "INFO" "TV input: $TV_INPUT"

# Invoke the adapter to filter by relevance and score
python3 "$SCRIPT_DIR/parse_findings.py" \
    --input "$TV_INPUT" \
    --output "$OUTPUT_DIR/findings.json" \
    ${CONFIG_PATH:+--config "$CONFIG_PATH"}

# Check findings count
FINDINGS_COUNT=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/findings.json'))['stats']['filtered_findings'])")

if [[ "$FINDINGS_COUNT" -eq 0 ]]; then
    log "INFO" "No actionable findings"
else
    log "INFO" "Found $FINDINGS_COUNT actionable findings"
fi

log "INFO" "Stage 1 completed — findings_count: $FINDINGS_COUNT"
