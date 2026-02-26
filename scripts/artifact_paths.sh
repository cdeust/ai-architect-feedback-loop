#!/usr/bin/env bash
# ============================================================================
# artifact_paths.sh — Standardized artifact path helpers
# ============================================================================
#
# Provides functions to resolve artifact paths using the new directory layout:
#
#   $RUN_DIR/findings/$FID/
#     stage2-impact.json
#     stage2-validation.json
#     stage3-integration.json
#     stage3-validation.json
#     stage3-manifest.json
#     stage5-prd/
#     stage5-validation.json
#     stage6-review.json
#     attempts/1/ attempts/2/ ...
#     retry-state.json
#     retry-summary.json
#
# Backward compatibility: if the new path doesn't exist, falls back to old
# flat layout (e.g. $RUN_DIR/impact_report_$FID.json).
#
# Usage:
#   source scripts/artifact_paths.sh
#   dir=$(artifact_dir "$RUN_DIR" "$FID")
#   path=$(artifact_impact "$RUN_DIR" "$FID")
# ============================================================================

# Create and return the finding directory
artifact_dir() {
    local run_dir="$1" fid="$2"
    local d="$run_dir/findings/$fid"
    mkdir -p "$d"
    echo "$d"
}

# Create and return the attempt directory
artifact_attempt_dir() {
    local run_dir="$1" fid="$2" attempt="$3"
    local d="$run_dir/findings/$fid/attempts/$attempt"
    mkdir -p "$d"
    echo "$d"
}

# Resolve a file path: new location first, fall back to old flat path
_resolve() {
    local run_dir="$1" fid="$2" new_name="$3" old_name="$4"
    local new_path="$run_dir/findings/$fid/$new_name"
    local old_path="$run_dir/$old_name"
    if [[ -f "$new_path" ]]; then
        echo "$new_path"
    elif [[ -f "$old_path" ]]; then
        echo "$old_path"
    else
        # Default to new path for writes
        mkdir -p "$(dirname "$new_path")"
        echo "$new_path"
    fi
}

# Resolve a directory path: new location first, fall back to old flat path
_resolve_dir() {
    local run_dir="$1" fid="$2" new_name="$3" old_name="$4"
    local new_path="$run_dir/findings/$fid/$new_name"
    local old_path="$run_dir/$old_name"
    if [[ -d "$new_path" ]]; then
        echo "$new_path"
    elif [[ -d "$old_path" ]]; then
        echo "$old_path"
    else
        mkdir -p "$new_path"
        echo "$new_path"
    fi
}

# Stage 2
artifact_impact()        { _resolve "$1" "$2" "stage2-impact.json" "impact_report_$2.json"; }
artifact_validation2()   { _resolve "$1" "$2" "stage2-validation.json" "validation_stage2_$2.json"; }

# Stage 3
artifact_integration()   { _resolve "$1" "$2" "stage3-integration.json" "integration_plan_$2.json"; }
artifact_validation3()   { _resolve "$1" "$2" "stage3-validation.json" "validation_stage3_$2.json"; }
artifact_manifest()      { _resolve "$1" "$2" "stage3-manifest.json" "manifest_$2.json"; }

# Stage 5 (PRD generation — was stage 4)
artifact_prd_dir() {
    local run_dir="$1" fid="$2"
    local new_path="$run_dir/findings/$fid/stage5-prd"
    local old_numbered="$run_dir/findings/$fid/stage4-prd"
    local old_flat="$run_dir/prd_output_$fid"
    if [[ -d "$new_path" ]]; then echo "$new_path"
    elif [[ -d "$old_numbered" ]]; then echo "$old_numbered"
    elif [[ -d "$old_flat" ]]; then echo "$old_flat"
    else mkdir -p "$new_path"; echo "$new_path"
    fi
}
artifact_validation5()   { _resolve "$1" "$2" "stage5-validation.json" "validation_stage4_$2.json"; }
# Backward compat alias
artifact_validation4()   { artifact_validation5 "$@"; }

# Stage 6 (PRD Review — NEW)
artifact_review6()       { _resolve "$1" "$2" "stage6-review.json" ""; }

# Retry
artifact_retry_state()   { _resolve "$1" "$2" "retry-state.json" "retry_state_$2.json"; }
artifact_retry_summary() { _resolve "$1" "$2" "retry-summary.json" "retry_summary_$2.json"; }

# Stage 11 (Semantic Verification — was stage 7)
artifact_verification11() { _resolve "$1" "$2" "stage11-verification.json" "verification_stage7_$2.json"; }
# Backward compat alias
artifact_verification7()  { artifact_verification11 "$@"; }

# List all finding IDs from the findings/ directory (new layout)
# Falls back to scanning flat files if findings/ doesn't exist
list_finding_dirs() {
    local run_dir="$1"
    local findings_dir="$run_dir/findings"
    if [[ -d "$findings_dir" ]]; then
        ls -1 "$findings_dir" 2>/dev/null | sort
    fi
}
