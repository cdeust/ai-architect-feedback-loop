#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# notify.sh — Product-Aware macOS Notification
# ============================================================================
#
# Reports what improved in the product, not just "pipeline ran."
# Reads the improvement report to compose a notification with engine names,
# quality deltas, and failure counts.
#
# Usage:
#   # From improvement report:
#   scripts/notify.sh --run-dir runs/TIMESTAMP
#
#   # Or quick message:
#   scripts/notify.sh --message "No findings today"
# ============================================================================

STAGE_NAME="notify"

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
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir)
            RUN_DIR="$2"
            shift 2
            ;;
        --message)
            MESSAGE="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Compose notification
# ---------------------------------------------------------------------------

# Read notification preferences
_PREFS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/pipeline_preferences.json"
NOTIF_ENABLED=true
NOTIF_SOUND="Glass"
TITLE="AI-Architect Pipeline"
if [[ -f "$_PREFS_FILE" ]]; then
    NOTIF_ENABLED=$(python3 -c "import json; print(str(json.load(open('$_PREFS_FILE'))['notifications'].get('enabled', True)).lower())" 2>/dev/null || echo "true")
    NOTIF_SOUND=$(python3 -c "import json; print(json.load(open('$_PREFS_FILE'))['notifications'].get('sound', 'Glass'))" 2>/dev/null || echo "Glass")
    TITLE=$(python3 -c "import json; print(json.load(open('$_PREFS_FILE'))['notifications'].get('title', 'AI-Architect Pipeline'))" 2>/dev/null || echo "AI-Architect Pipeline")
fi

if [[ "$NOTIF_ENABLED" == "false" ]]; then
    log "INFO" "Notifications disabled in preferences"
    exit 0
fi

SUBTITLE=""
BODY=""

if [[ -n "$MESSAGE" ]]; then
    # Direct message mode
    BODY="$MESSAGE"
    SUBTITLE="Status"
    log "INFO" "Notification (direct): $MESSAGE"

elif [[ -n "$RUN_DIR" && -f "$RUN_DIR/improvement_report.json" ]]; then
    # Read improvement report
    REPORT="$RUN_DIR/improvement_report.json"

    IMPLEMENTED=$(python3 -c "import json; print(json.load(open('$REPORT'))['findings_summary']['implemented'])" 2>/dev/null || echo "0")
    FAILED=$(python3 -c "import json; print(json.load(open('$REPORT'))['findings_summary']['failed'])" 2>/dev/null || echo "0")
    PRS=$(python3 -c "import json; print(json.load(open('$REPORT'))['findings_summary']['prs_created'])" 2>/dev/null || echo "0")
    TOTAL=$(python3 -c "import json; print(json.load(open('$REPORT'))['findings_summary']['total_found'])" 2>/dev/null || echo "0")

    # Get improved engine names
    ENGINES=$(python3 -c "
import json
r = json.load(open('$REPORT'))
engines = list(r.get('engines_improved', {}).keys())
print(', '.join(engines) if engines else 'none')
" 2>/dev/null || echo "none")

    # Get quality deltas
    QUALITY_DELTAS=$(python3 -c "
import json
r = json.load(open('$REPORT'))
dims = r.get('quality_impact', {}).get('dimensions', {})
deltas = []
for dim, vals in dims.items():
    d = float(vals.get('delta', '0'))
    if d != 0:
        deltas.append(f'{dim} {d*100:+.0f}%')
print(', '.join(deltas) if deltas else 'no change')
" 2>/dev/null || echo "unknown")

    if [[ "$TOTAL" -eq 0 ]]; then
        SUBTITLE="Product is healthy"
        BODY="No findings — product is healthy"
    elif [[ "$IMPLEMENTED" -gt 0 && "$FAILED" -eq 0 ]]; then
        SUBTITLE="$IMPLEMENTED engine(s) improved"
        BODY="Pipeline: $PRS PRs ($ENGINES). Quality: $QUALITY_DELTAS."
    elif [[ "$IMPLEMENTED" -gt 0 && "$FAILED" -gt 0 ]]; then
        SUBTITLE="$IMPLEMENTED improved, $FAILED failed"
        BODY="Pipeline: $PRS PRs ($ENGINES). $FAILED failure(s) filed. Quality: $QUALITY_DELTAS."
    else
        SUBTITLE="$FAILED failure(s)"
        BODY="Pipeline: $FAILED finding(s) failed implementation. Quality: $QUALITY_DELTAS."
    fi

    log "INFO" "Notification (report): $BODY"

elif [[ -n "$RUN_DIR" ]]; then
    # Run dir exists but no improvement report
    SUBTITLE="Run complete"
    BODY="Pipeline run finished (no improvement report generated)"
    log "WARN" "No improvement_report.json found in $RUN_DIR"

else
    log "ERROR" "Either --run-dir or --message is required"
    exit 1
fi

# ---------------------------------------------------------------------------
# Send macOS notification
# ---------------------------------------------------------------------------

osascript -e "display notification \"$BODY\" with title \"$TITLE\" subtitle \"$SUBTITLE\" sound name \"$NOTIF_SOUND\"" 2>/dev/null \
    && log "INFO" "Notification sent" \
    || log "WARN" "osascript notification failed — non-fatal"

exit 0
