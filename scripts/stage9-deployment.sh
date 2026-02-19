#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage9-deployment.sh — Stage 9: Deployment Simulation
# ============================================================================
#
# Runs the project's deploy_command from config/project.json.
# If no deploy_command is configured, the stage passes with SKIP.
#
# Usage:
#   scripts/stage9-deployment.sh \
#       --builder-dir /path/to/target-product \
#       --output runs/20260215-120000
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage9_deployment"

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
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --builder-dir)
            BUILDER_DIR="$2"
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
if [[ -z "$OUTPUT_DIR" ]]; then
    log "ERROR" "Missing required argument: --output"
    exit 1
fi
if [[ ! -d "$BUILDER_DIR" ]]; then
    log "ERROR" "Builder directory not found: $BUILDER_DIR"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Optionally verify prior stages passed
# ---------------------------------------------------------------------------

if [[ -f "$OUTPUT_DIR/enforcement_report.json" ]]; then
    prior_result=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/enforcement_report.json')).get('overall_result', 'UNKNOWN'))")
    if [[ "$prior_result" == "FAIL" ]]; then
        log "WARN" "Prior enforcement gates FAILED — proceeding with deployment simulation anyway"
    fi
fi

# ---------------------------------------------------------------------------
# Read deploy command from project config
# ---------------------------------------------------------------------------

PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
DEPLOY_CMD=""
if [[ -f "$PROJECT_CONFIG" ]]; then
    DEPLOY_CMD=$(python3 -c "import json; v=json.load(open('$PROJECT_CONFIG')).get('deploy_command'); print(v if v else '')" 2>/dev/null || echo "")
fi

log "INFO" "Stage 9 started — Deployment Simulation"
log "INFO" "Builder dir: $BUILDER_DIR"

# ---------------------------------------------------------------------------
# Skip if no deploy command configured
# ---------------------------------------------------------------------------

if [[ -z "$DEPLOY_CMD" ]]; then
    log "INFO" "No deploy_command configured in project.json — PASS (skipped)"

    python3 - "$OUTPUT_DIR" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

output_dir = sys.argv[1]

report = {
    "stage": "deployment_simulation",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "result": "PASS",
    "reason": "no deploy_command configured — skipped",
    "distribute_exit_code": 0,
    "duration_seconds": 0,
}

report_path = f"{output_dir}/deployment_report.json"
with open(report_path, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')

print(json.dumps({
    "stage": "stage9_deployment",
    "result": "PASS",
    "reason": "skipped — no deploy_command",
}))
PYEOF

    log "INFO" "Stage 9 completed — result: PASS (skipped)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Run deploy command
# ---------------------------------------------------------------------------

START_TIME=$(date +%s)

DEPLOY_OUTPUT=""
DEPLOY_EXIT=0
DEPLOY_OUTPUT=$(cd "$BUILDER_DIR" && eval "$DEPLOY_CMD" 2>&1) || DEPLOY_EXIT=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Save full output for debugging
echo "$DEPLOY_OUTPUT" > "$OUTPUT_DIR/stage9_deploy_output.txt"

log "INFO" "Deploy command completed in ${DURATION}s with exit code $DEPLOY_EXIT"

# ---------------------------------------------------------------------------
# Determine overall result
# ---------------------------------------------------------------------------

OVERALL_RESULT="PASS"
if [[ "$DEPLOY_EXIT" -ne 0 ]]; then
    OVERALL_RESULT="FAIL"
    log "ERROR" "Deployment simulation FAILED (exit code: $DEPLOY_EXIT)"
fi

# ---------------------------------------------------------------------------
# Write deployment report
# ---------------------------------------------------------------------------

python3 - "$OUTPUT_DIR" "$OVERALL_RESULT" "$DEPLOY_EXIT" "$DURATION" "$DEPLOY_CMD" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

output_dir, result, exit_code, duration, deploy_cmd = sys.argv[1:6]

report = {
    "stage": "deployment_simulation",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "result": result,
    "distribute_exit_code": int(exit_code),
    "duration_seconds": int(duration),
    "deploy_command": deploy_cmd,
}

report_path = f"{output_dir}/deployment_report.json"
with open(report_path, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')

print(json.dumps({
    "stage": "stage9_deployment",
    "result": result,
    "exit_code": int(exit_code),
    "duration_seconds": int(duration),
}))
PYEOF

log "INFO" "Stage 9 completed — result: $OVERALL_RESULT"
log "INFO" "Report written to $OUTPUT_DIR/deployment_report.json"

if [[ "$OVERALL_RESULT" == "FAIL" ]]; then
    exit 1
fi
