#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage9-deployment.sh — Stage 9: Deployment Simulation
# ============================================================================
#
# Wraps the prd-builder's existing `make distribute` target which runs:
#   key injection -> build 8 XCFrameworks -> encrypt -> 38 encryption tests
#
# Verifies post-distribute state: placeholder keys restored, exit code 0.
#
# Usage:
#   scripts/stage9-deployment.sh \
#       --builder-dir ../ai-architect-prd-builder \
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
# Run make distribute
# ---------------------------------------------------------------------------

log "INFO" "Stage 9 started — Deployment Simulation"
log "INFO" "Builder dir: $BUILDER_DIR"

START_TIME=$(date +%s)

DIST_OUTPUT=""
DIST_EXIT=0
DIST_OUTPUT=$(make -C "$BUILDER_DIR" distribute 2>&1) || DIST_EXIT=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Save full output for debugging
echo "$DIST_OUTPUT" > "$OUTPUT_DIR/stage9_dist_output.txt"

log "INFO" "make distribute completed in ${DURATION}s with exit code $DIST_EXIT"

# ---------------------------------------------------------------------------
# Parse encryption test count from output
# ---------------------------------------------------------------------------

ENCRYPTION_PASSED=0
ENCRYPTION_TOTAL=0

# Look for patterns like "38/38" or "Test Suite: All tests passed" or "38 tests passed"
if echo "$DIST_OUTPUT" | grep -qE "([0-9]+)/\1"; then
    ENCRYPTION_LINE=$(echo "$DIST_OUTPUT" | grep -oE "[0-9]+/[0-9]+" | tail -1 || echo "")
    if [[ -n "$ENCRYPTION_LINE" ]]; then
        ENCRYPTION_PASSED=$(echo "$ENCRYPTION_LINE" | cut -d/ -f1)
        ENCRYPTION_TOTAL=$(echo "$ENCRYPTION_LINE" | cut -d/ -f2)
    fi
fi

# Fallback: count "Test Suite" lines or "passed" counts
if [[ "$ENCRYPTION_TOTAL" -eq 0 ]]; then
    PASS_COUNT=$(echo "$DIST_OUTPUT" | grep -c "passed" || echo "0")
    if [[ "$PASS_COUNT" -gt 0 ]]; then
        ENCRYPTION_PASSED=$PASS_COUNT
        ENCRYPTION_TOTAL=$PASS_COUNT
    fi
fi

log "INFO" "Encryption tests: $ENCRYPTION_PASSED/$ENCRYPTION_TOTAL"

# ---------------------------------------------------------------------------
# Verify placeholder keys restored
# ---------------------------------------------------------------------------

PLACEHOLDER_RESTORED=true
PLACEHOLDER_KEY="PLACEHOLDER_PUBLIC_KEY_INJECT_AT_BUILD_TIME"

VALIDATOR_FILE="$BUILDER_DIR/packages/AIPRDEncryptionEngine/Sources/Crypto/SecureLicenseValidator.swift"
VALIDATE_SCRIPT="$BUILDER_DIR/scripts/distribution/validate-license.swift"

if [[ -f "$VALIDATOR_FILE" ]]; then
    if ! grep -q "$PLACEHOLDER_KEY" "$VALIDATOR_FILE"; then
        log "ERROR" "Placeholder key NOT restored in SecureLicenseValidator.swift"
        PLACEHOLDER_RESTORED=false
    else
        log "INFO" "Placeholder key verified in SecureLicenseValidator.swift"
    fi
else
    log "WARN" "SecureLicenseValidator.swift not found at expected path"
fi

if [[ -f "$VALIDATE_SCRIPT" ]]; then
    if ! grep -q "$PLACEHOLDER_KEY" "$VALIDATE_SCRIPT"; then
        log "ERROR" "Placeholder key NOT restored in validate-license.swift"
        PLACEHOLDER_RESTORED=false
    else
        log "INFO" "Placeholder key verified in validate-license.swift"
    fi
else
    log "WARN" "validate-license.swift not found at expected path"
fi

# ---------------------------------------------------------------------------
# Determine overall result
# ---------------------------------------------------------------------------

OVERALL_RESULT="PASS"
if [[ "$DIST_EXIT" -ne 0 ]]; then
    OVERALL_RESULT="FAIL"
    log "ERROR" "Deployment simulation FAILED (make distribute exit code: $DIST_EXIT)"
fi
if [[ "$PLACEHOLDER_RESTORED" == "false" ]]; then
    OVERALL_RESULT="FAIL"
    log "ERROR" "Deployment simulation FAILED (placeholder keys not restored)"
fi

# ---------------------------------------------------------------------------
# Write deployment report
# ---------------------------------------------------------------------------

python3 - "$OUTPUT_DIR" "$OVERALL_RESULT" "$DIST_EXIT" "$DURATION" \
    "$ENCRYPTION_PASSED" "$ENCRYPTION_TOTAL" "$PLACEHOLDER_RESTORED" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

output_dir, result, exit_code, duration, enc_passed, enc_total, placeholder = sys.argv[1:8]

report = {
    "stage": "deployment_simulation",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "result": result,
    "distribute_exit_code": int(exit_code),
    "duration_seconds": int(duration),
    "encryption_tests": {
        "passed": int(enc_passed),
        "total": int(enc_total),
    },
    "placeholder_keys_restored": placeholder == "true",
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
    "encryption_tests": f"{enc_passed}/{enc_total}",
    "placeholder_keys_restored": placeholder == "true",
}))
PYEOF

log "INFO" "Stage 9 completed — result: $OVERALL_RESULT"
log "INFO" "Report written to $OUTPUT_DIR/deployment_report.json"

if [[ "$OVERALL_RESULT" == "FAIL" ]]; then
    exit 1
fi
