#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage10-gates.sh — Stage 10: Deterministic Enforcement Gates
# ============================================================================
#
# Runs 6 deterministic quality gates against the builder project.
# Each gate produces a pass/fail result with timing and details.
# Outputs enforcement_report.json to the run directory.
#
# Gates:
#   1. Prohibited pattern detection (grep against prohibited_patterns.txt)
#   2. Manifest compliance (must-change / must-not-change vs git diff)
#   3. Orphan file detection (new files with unreferenced types)
#   4. Build verification (make build-library)
#   5. Test suite (make test-all)
#   6. Encryption integrity (make distribute)
#
# Usage (called by Makefile pipeline-gates):
#   scripts/stage10-gates.sh \
#       --builder-dir /path/to/target-product \
#       --config config/thresholds.json \
#       --patterns config/prohibited_patterns.txt \
#       --output runs/20260211-120000
#
# Optional:
#   --skip-gate N      Skip gate N (can be repeated)
#   --manifest PATH    Path to manifest.json for Gate 2
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_NAME="stage10_enforcement"

# Resolve base branch from project config
BASE_BRANCH="main"
PROJECT_CONFIG="$SCRIPT_DIR/../config/project.json"
if [[ -f "$PROJECT_CONFIG" ]]; then
    BASE_BRANCH=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG')).get('base_branch', 'main'))" 2>/dev/null || echo "main")
fi

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
PATTERNS_FILE=""
OUTPUT_DIR=""
MANIFEST_PATH=""
SKIP_GATES=()

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
        --patterns)
            PATTERNS_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --manifest)
            MANIFEST_PATH="$2"
            shift 2
            ;;
        --skip-gate)
            SKIP_GATES+=("$2")
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

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Report building helpers
# ---------------------------------------------------------------------------

REPORT_FILE="$OUTPUT_DIR/enforcement_report.json"
GATE_RESULTS_FILE=$(mktemp)
echo '[]' > "$GATE_RESULTS_FILE"
OVERALL_RESULT="PASS"

# Ensure temp file is cleaned up on exit
trap 'rm -f "$GATE_RESULTS_FILE"' EXIT

should_skip() {
    local gate_num="$1"
    for skip in "${SKIP_GATES[@]+"${SKIP_GATES[@]}"}"; do
        if [[ "$skip" == "$gate_num" ]]; then
            return 0
        fi
    done
    return 1
}

add_gate_result() {
    local gate_num="$1" gate_name="$2" result="$3" duration="$4" details_file="$5"
    python3 - "$GATE_RESULTS_FILE" "$details_file" "$gate_num" "$gate_name" "$result" "$duration" <<'PYEOF'
import json, sys
gates_file, details_file, gate_num, gate_name, result, duration = sys.argv[1:7]
with open(gates_file) as f:
    gates = json.load(f)
with open(details_file) as f:
    details = json.load(f)
gates.append({
    "gate": int(gate_num),
    "name": gate_name,
    "result": result,
    "duration_seconds": int(duration),
    "details": details
})
with open(gates_file, 'w') as f:
    json.dump(gates, f)
PYEOF
    if [[ "$result" == "FAIL" ]]; then
        OVERALL_RESULT="FAIL"
    fi
}

write_report() {
    python3 - "$GATE_RESULTS_FILE" "$REPORT_FILE" "$OVERALL_RESULT" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
gates_file, report_file, overall = sys.argv[1:4]
with open(gates_file) as f:
    gates = json.load(f)
report = {
    "stage": "enforcement",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "overall_result": overall,
    "gates": gates
}
with open(report_file, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')
PYEOF
}

# ---------------------------------------------------------------------------
# Gate 1: Prohibited Pattern Detection
# ---------------------------------------------------------------------------

run_gate_1() {
    log "INFO" "Gate 1: Prohibited pattern detection (delta-only)"
    local start_time
    start_time=$(date +%s)

    local patterns_file="${PATTERNS_FILE:-}"
    local details_file
    details_file=$(mktemp)

    if [[ -z "$patterns_file" || ! -f "$patterns_file" ]]; then
        log "WARN" "Gate 1: No patterns file found, skipping"
        echo '{"reason":"no patterns file"}' > "$details_file"
        local duration=$(( $(date +%s) - start_time ))
        add_gate_result 1 "prohibited_patterns" "SKIP" "$duration" "$details_file"
        rm -f "$details_file"
        return
    fi

    # Determine changed files for delta checking (only scan files touched by this branch)
    local current_branch
    current_branch=$(git -C "$BUILDER_DIR" branch --show-current 2>/dev/null || echo "")
    local changed_files=""
    if [[ -n "$current_branch" && "$current_branch" != "$BASE_BRANCH" ]]; then
        changed_files=$(git -C "$BUILDER_DIR" diff --name-only "${BASE_BRANCH}...$current_branch" -- packages/ library/ 2>/dev/null || echo "")
    fi

    # If no changed files (or on main), skip pattern check — no delta to verify
    if [[ -z "$changed_files" ]]; then
        log "INFO" "Gate 1: No changed files to check — PASS (on base branch or no delta)"
        echo '{"reason":"no changed files (delta-only mode)","patterns_checked":0,"violations_found":0,"files_scanned":0,"violations":[]}' > "$details_file"
        local duration=$(( $(date +%s) - start_time ))
        add_gate_result 1 "prohibited_patterns" "PASS" "$duration" "$details_file"
        rm -f "$details_file"
        return
    fi

    local violations=0
    local files_scanned=0
    local patterns_checked=0
    local violations_file
    violations_file=$(mktemp)
    echo '[]' > "$violations_file"

    # Read source extensions from project config
    local project_config="$SCRIPT_DIR/../config/project.json"
    local source_exts=".py"
    if [[ -f "$project_config" ]]; then
        source_exts=$(python3 -c "import json; print(' '.join(json.load(open('$project_config')).get('source_extensions', ['.py'])))" 2>/dev/null || echo ".py")
    fi

    # Only check patterns in changed source files (delta-only)
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        [[ -z "$pattern" ]] && continue
        [[ "$pattern" == \#* ]] && continue
        patterns_checked=$((patterns_checked + 1))

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local full_path="$BUILDER_DIR/$file"
            [[ -f "$full_path" ]] || continue
            # Check if file matches any configured source extension
            local matches_ext=false
            for ext in $source_exts; do
                if [[ "$file" == *"$ext" ]]; then
                    matches_ext=true
                    break
                fi
            done
            [[ "$matches_ext" == "false" ]] && continue
            # Skip test files and build artifacts
            [[ "$file" == */Tests/* ]] && continue
            [[ "$file" == */.build/* ]] && continue
            [[ "$file" == */test/* ]] && continue
            [[ "$file" == */tests/* ]] && continue
            [[ "$file" == */node_modules/* ]] && continue
            [[ "$file" == */__pycache__/* ]] && continue

            if grep -qE "$pattern" "$full_path" 2>/dev/null; then
                local match_lines
                match_lines=$(grep -nE "$pattern" "$full_path" 2>/dev/null || true)
                local match_count
                match_count=$(echo "$match_lines" | grep -c . || echo "0")
                violations=$((violations + match_count))

                # Capture violations for the report (first 3 per pattern per file)
                python3 - "$violations_file" "$file" "$pattern" "$match_lines" <<'PYEOF'
import json, sys
viol_file, filepath, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
match_lines = sys.argv[4] if len(sys.argv) > 4 else ""
with open(viol_file) as f:
    existing = json.load(f)
for line in match_lines.strip().split("\n")[:3]:
    if line.strip():
        existing.append({"pattern": pattern, "location": f"{filepath}:{line.strip()}"[:200]})
with open(viol_file, 'w') as f:
    json.dump(existing, f)
PYEOF
            fi
        done <<< "$changed_files"
    done < "$patterns_file"

    # Count scanned source files
    files_scanned=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        for ext in $source_exts; do
            if [[ "$file" == *"$ext" ]]; then
                files_scanned=$((files_scanned + 1))
                break
            fi
        done
    done <<< "$changed_files"

    local result="PASS"
    if [[ "$violations" -gt 0 ]]; then
        result="FAIL"
        log "WARN" "Gate 1: $violations violations found in $files_scanned changed files across $patterns_checked patterns"
    else
        log "INFO" "Gate 1: Clean — $patterns_checked patterns checked, $files_scanned changed files scanned (delta-only)"
    fi

    # Build details JSON
    python3 - "$details_file" "$violations_file" "$patterns_checked" "$violations" "$files_scanned" <<'PYEOF'
import json, sys
details_file, viol_file = sys.argv[1], sys.argv[2]
patterns_checked, violations_found, files_scanned = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
with open(viol_file) as f:
    viols = json.load(f)
details = {
    "mode": "delta_only",
    "patterns_checked": patterns_checked,
    "violations_found": violations_found,
    "files_scanned": files_scanned,
    "violations": viols
}
with open(details_file, 'w') as f:
    json.dump(details, f)
PYEOF
    rm -f "$violations_file"

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 1 "prohibited_patterns" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Gate 2: Manifest Compliance
# ---------------------------------------------------------------------------

run_gate_2() {
    log "INFO" "Gate 2: Manifest compliance (advisory)"
    local start_time
    start_time=$(date +%s)

    local manifest="${MANIFEST_PATH:-}"
    local details_file
    details_file=$(mktemp)

    # If no manifest provided, check for one in the run directory or config
    if [[ -z "$manifest" || ! -f "$manifest" ]]; then
        log "INFO" "Gate 2: No manifest constraints defined — passing by default"
        echo '{"reason":"no manifest constraints defined","advised_changes_files":0,"not_advised_changes_files":0}' > "$details_file"
        local duration=$(( $(date +%s) - start_time ))
        add_gate_result 2 "manifest_compliance" "PASS" "$duration" "$details_file"
        rm -f "$details_file"
        return
    fi

    # Get changed files from git diff in the builder project
    local changed_files_file
    changed_files_file=$(mktemp)
    (cd "$BUILDER_DIR" && git diff --name-only HEAD~1 2>/dev/null || true) > "$changed_files_file"

    # Advisory manifest check — drift is reported but does not fail the gate
    python3 - "$manifest" "$changed_files_file" "$details_file" <<'PYEOF'
import json, sys
manifest_path, changed_file, details_file = sys.argv[1:4]
with open(manifest_path) as f:
    manifest = json.load(f)
with open(changed_file) as f:
    changed = set(line.strip() for line in f if line.strip())

advised = manifest.get("advised_changes", [])
not_advised = manifest.get("not_advised_changes", [])
drift = []
advised_satisfied = 0
not_advised_satisfied = 0

for path in advised:
    if path in changed:
        advised_satisfied += 1
    else:
        drift.append({"type": "advised_not_changed", "file": path})

for path in not_advised:
    if path in changed:
        drift.append({"type": "not_advised_changed", "file": path})
    else:
        not_advised_satisfied += 1

details = {
    "advised_changes_files": len(advised),
    "advised_changes_satisfied": advised_satisfied,
    "not_advised_changes_files": len(not_advised),
    "not_advised_changes_satisfied": not_advised_satisfied,
    "drift": drift
}
with open(details_file, 'w') as f:
    json.dump(details, f)
PYEOF
    rm -f "$changed_files_file"

    local drift_count
    drift_count=$(python3 -c "import json; print(len(json.load(open('$details_file')).get('drift', [])))")

    # Advisory: always PASS, but log drift for visibility
    local result="PASS"
    if [[ "$drift_count" -gt 0 ]]; then
        log "WARN" "Gate 2: $drift_count manifest drift items (advisory — not blocking)"
    else
        log "INFO" "Gate 2: Manifest compliance verified"
    fi

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 2 "manifest_compliance" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Gate 3: Orphan File Detection
# ---------------------------------------------------------------------------

run_gate_3() {
    log "INFO" "Gate 3: Orphan file detection"
    local start_time
    start_time=$(date +%s)

    # Get new/added files from git status in builder project
    local new_files
    new_files=$(cd "$BUILDER_DIR" && git diff --name-only --diff-filter=A HEAD~1 2>/dev/null || \
                cd "$BUILDER_DIR" && git status --porcelain 2>/dev/null | grep "^?" | awk '{print $2}' || echo "")

    local orphans_file
    orphans_file=$(mktemp)
    echo '[]' > "$orphans_file"
    local files_checked=0
    local orphan_count=0

    # Read source extensions and modules dir from project config
    local gate3_project_config="$SCRIPT_DIR/../config/project.json"
    local gate3_source_exts=".py"
    local gate3_modules_dir="packages"
    if [[ -f "$gate3_project_config" ]]; then
        gate3_source_exts=$(python3 -c "import json; print(' '.join(json.load(open('$gate3_project_config')).get('source_extensions', ['.py'])))" 2>/dev/null || echo ".py")
        gate3_modules_dir=$(python3 -c "import json; print(json.load(open('$gate3_project_config')).get('modules_dir', 'packages'))" 2>/dev/null || echo "packages")
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Only check source files matching configured extensions
        local gate3_matches=false
        for ext in $gate3_source_exts; do
            if [[ "$file" == *"$ext" ]]; then
                gate3_matches=true
                break
            fi
        done
        [[ "$gate3_matches" == "false" ]] && continue
        [[ "$file" == */Tests/* ]] && continue
        [[ "$file" == */tests/* ]] && continue
        [[ "$file" == */.build/* ]] && continue
        [[ "$file" == */node_modules/* ]] && continue
        [[ "$file" == */__pycache__/* ]] && continue

        files_checked=$((files_checked + 1))
        local full_path="$BUILDER_DIR/$file"
        [[ ! -f "$full_path" ]] && continue

        # Extract declared type names (class, struct, enum, protocol, interface, type, def)
        local types
        types=$(grep -oE '(public |open |internal |export )?(class|struct|enum|protocol|interface|type)\s+[A-Z][A-Za-z0-9_]+' "$full_path" 2>/dev/null | \
                grep -oE '[A-Z][A-Za-z0-9_]+$' || true)

        if [[ -z "$types" ]]; then
            continue
        fi

        # Check if any declared type is referenced in other source files
        local referenced=false
        while IFS= read -r type_name; do
            [[ -z "$type_name" ]] && continue
            local refs=""
            for ext in $gate3_source_exts; do
                refs=$(grep -rl --include="*${ext}" "$type_name" "$BUILDER_DIR/$gate3_modules_dir/" 2>/dev/null | \
                       grep -v "$full_path" | grep -v "/Tests/" | grep -v "/tests/" | grep -v "/.build/" | head -1 || true)
                if [[ -n "$refs" ]]; then
                    break
                fi
            done
            if [[ -n "$refs" ]]; then
                referenced=true
                break
            fi
        done <<< "$types"

        if [[ "$referenced" == "false" ]]; then
            orphan_count=$((orphan_count + 1))
            python3 - "$orphans_file" "$file" <<'PYEOF'
import json, sys
ofile, filepath = sys.argv[1], sys.argv[2]
with open(ofile) as f:
    orphans = json.load(f)
orphans.append(filepath)
with open(ofile, 'w') as f:
    json.dump(orphans, f)
PYEOF
        fi
    done <<< "$new_files"

    local result="PASS"
    if [[ "$orphan_count" -gt 0 ]]; then
        result="FAIL"
        log "WARN" "Gate 3: $orphan_count orphan files detected"
    else
        log "INFO" "Gate 3: No orphans — $files_checked new files checked"
    fi

    # Build details JSON
    local details_file
    details_file=$(mktemp)
    python3 - "$details_file" "$orphans_file" "$files_checked" "$orphan_count" <<'PYEOF'
import json, sys
details_file, orphans_file = sys.argv[1], sys.argv[2]
files_checked, orphan_count = int(sys.argv[3]), int(sys.argv[4])
with open(orphans_file) as f:
    orphans = json.load(f)
details = {"files_checked": files_checked, "orphans_found": orphan_count, "orphans": orphans}
with open(details_file, 'w') as f:
    json.dump(details, f)
PYEOF
    rm -f "$orphans_file"

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 3 "orphan_detection" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Gate 4: Build Verification
# ---------------------------------------------------------------------------

run_gate_4() {
    log "INFO" "Gate 4: Build verification"
    local start_time
    start_time=$(date +%s)

    # Read build command from project config
    local gate4_project_config="$SCRIPT_DIR/../config/project.json"
    local build_cmd="make build"
    if [[ -f "$gate4_project_config" ]]; then
        build_cmd=$(python3 -c "import json; print(json.load(open('$gate4_project_config')).get('build_command', 'make build'))" 2>/dev/null || echo "make build")
    fi

    local build_output
    local build_exit=0
    build_output=$(cd "$BUILDER_DIR" && eval "$build_cmd" 2>&1) || build_exit=$?

    local result="PASS"
    if [[ "$build_exit" -ne 0 ]]; then
        result="FAIL"
        log "ERROR" "Gate 4: Build failed with exit code $build_exit"
    else
        log "INFO" "Gate 4: Build succeeded"
    fi

    # Save build output for debugging
    echo "$build_output" > "$OUTPUT_DIR/gate4_build_output.txt"

    local details_file
    details_file=$(mktemp)
    python3 -c "import json; json.dump({'exit_code':$build_exit,'output_file':'gate4_build_output.txt'},open('$details_file','w'))"

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 4 "build_verification" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Gate 5: Test Suite
# ---------------------------------------------------------------------------

run_gate_5() {
    log "INFO" "Gate 5: Test suite"
    local start_time
    start_time=$(date +%s)

    # Read test command from project config
    local gate5_project_config="$SCRIPT_DIR/../config/project.json"
    local test_cmd="make test"
    if [[ -f "$gate5_project_config" ]]; then
        test_cmd=$(python3 -c "import json; print(json.load(open('$gate5_project_config')).get('test_command', 'make test'))" 2>/dev/null || echo "make test")
    fi

    local result="PASS"
    local test_output
    local test_exit=0
    local test_timeout=300  # 5 minutes

    # Use gtimeout (macOS coreutils) or timeout (Linux), fallback to plain execution
    local timeout_bin=""
    if command -v gtimeout &>/dev/null; then
        timeout_bin="gtimeout"
    elif command -v timeout &>/dev/null; then
        timeout_bin="timeout"
    fi

    if [[ -n "$timeout_bin" ]]; then
        test_output=$(cd "$BUILDER_DIR" && "$timeout_bin" "$test_timeout" bash -c "$test_cmd" 2>&1) || test_exit=$?
    else
        test_output=$(cd "$BUILDER_DIR" && bash -c "$test_cmd" 2>&1) || test_exit=$?
    fi

    if [[ "$test_exit" -eq 124 ]]; then
        log "WARN" "Gate 5: TIMEOUT after ${test_timeout}s"
        test_exit=1
    fi

    if [[ "$test_exit" -ne 0 ]]; then
        result="FAIL"
        log "WARN" "Gate 5: Tests FAILED (exit=$test_exit)"
        echo "$test_output" > "$OUTPUT_DIR/gate5_test_output.txt"
    else
        log "INFO" "Gate 5: Tests passed"
    fi

    local details_file
    details_file=$(mktemp)
    python3 -c "import json; json.dump({'mode':'single_command','test_command':'$test_cmd','exit_code':$test_exit,'output_file':'gate5_test_output.txt' if $test_exit != 0 else ''},open('$details_file','w'))"

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 5 "test_suite" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Gate 6: Encryption Integrity
# ---------------------------------------------------------------------------

run_gate_6() {
    log "INFO" "Gate 6: Deployment verification"
    local start_time
    start_time=$(date +%s)

    # Read deploy command from project config
    local gate6_project_config="$SCRIPT_DIR/../config/project.json"
    local deploy_cmd=""
    if [[ -f "$gate6_project_config" ]]; then
        deploy_cmd=$(python3 -c "import json; v=json.load(open('$gate6_project_config')).get('deploy_command'); print(v if v else '')" 2>/dev/null || echo "")
    fi

    if [[ -z "$deploy_cmd" ]]; then
        log "INFO" "Gate 6: No deploy_command configured — PASS (skipped)"
        local details_file
        details_file=$(mktemp)
        echo '{"reason":"no deploy_command configured","skipped":true}' > "$details_file"
        local duration=$(( $(date +%s) - start_time ))
        add_gate_result 6 "deployment_verification" "PASS" "$duration" "$details_file"
        rm -f "$details_file"
        return
    fi

    local dist_output
    local dist_exit=0
    dist_output=$(cd "$BUILDER_DIR" && eval "$deploy_cmd" 2>&1) || dist_exit=$?

    local result="PASS"
    if [[ "$dist_exit" -ne 0 ]]; then
        result="FAIL"
        log "ERROR" "Gate 6: Deploy command failed with exit code $dist_exit"
    else
        log "INFO" "Gate 6: Deploy command succeeded"
    fi

    echo "$dist_output" > "$OUTPUT_DIR/gate6_deploy_output.txt"

    local details_file
    details_file=$(mktemp)
    python3 -c "import json; json.dump({'exit_code':$dist_exit,'deploy_command':'$deploy_cmd','output_file':'gate6_deploy_output.txt'},open('$details_file','w'))"

    local duration=$(( $(date +%s) - start_time ))
    add_gate_result 6 "deployment_verification" "$result" "$duration" "$details_file"
    rm -f "$details_file"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

log "INFO" "Stage 10 started — Deterministic Enforcement Gates"
log "INFO" "Builder dir: $BUILDER_DIR"
log "INFO" "Output dir: $OUTPUT_DIR"
if [[ ${#SKIP_GATES[@]} -gt 0 ]]; then
    log "INFO" "Skipping gates: ${SKIP_GATES[*]}"
fi

GATE_FUNCTIONS=(run_gate_1 run_gate_2 run_gate_3 run_gate_4 run_gate_5 run_gate_6)

SKIP_DETAILS_FILE=""
for i in "${!GATE_FUNCTIONS[@]}"; do
    gate_num=$((i + 1))
    if should_skip "$gate_num"; then
        log "INFO" "Gate $gate_num: SKIPPED (--skip-gate)"
        SKIP_DETAILS_FILE=$(mktemp)
        echo '{"reason":"skipped by user"}' > "$SKIP_DETAILS_FILE"
        add_gate_result "$gate_num" "skipped" "SKIP" "0" "$SKIP_DETAILS_FILE"
        rm -f "$SKIP_DETAILS_FILE"
    else
        ${GATE_FUNCTIONS[$i]}
    fi
done

# Write the final report
write_report

log "INFO" "Stage 10 completed — overall result: $OVERALL_RESULT"
log "INFO" "Report written to $REPORT_FILE"

# Exit with failure if any gate failed
if [[ "$OVERALL_RESULT" == "FAIL" ]]; then
    exit 1
fi
