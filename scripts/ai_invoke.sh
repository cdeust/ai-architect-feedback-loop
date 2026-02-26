#!/usr/bin/env bash
# ============================================================================
# ai_invoke.sh — Shared AI invocation helper for pipeline stages
# ============================================================================
#
# Provides `ai_invoke` function that replaces direct `claude -p` calls.
# Supports three modes:
#
#   1. Auto mode (PIPELINE_AUTO_MODE=1):
#      Writes the prompt and a structured `pending_stage.json` descriptor
#      to OUTPUT_DIR for the orchestrating Claude Code session to process.
#      The session reads the prompt, produces a response, writes it to the
#      expected path, then re-runs the stage script to validate.
#
#   2. Session mode (PIPELINE_SESSION_MODE=1):
#      Writes the prompt to the output dir for the current Claude Code
#      session to process. Reads the response from a well-known path.
#      The orchestrating session provides responses before the script runs.
#
#   3. CLI mode (default, for nightly unattended runs):
#      Calls `claude -p` via run_with_timeout.
#
# Usage:
#   source scripts/ai_invoke.sh
#   ai_invoke <prompt_file> <output_file> <stage> <finding_id> [claude_args...]
#
# Auto mode file convention:
#   Prompt written to:   $OUTPUT_DIR/prompt_<stage>_<finding_id>.md
#   Descriptor written:  $OUTPUT_DIR/pending_stage.json
#   Response read from:  $OUTPUT_DIR/response_<stage>_<finding_id>.json
#
# Session mode file convention:
#   Prompt written to:   $OUTPUT_DIR/prompt_<stage>_<finding_id>.md
#   Response read from:  $OUTPUT_DIR/response_<stage>_<finding_id>.json
#
# Environment:
#   PIPELINE_AUTO_MODE=1     — enable auto mode (structured descriptor)
#   PIPELINE_SESSION_MODE=1  — enable session mode (skip claude -p)
#   AI_TIMEOUT               — timeout in seconds (default: 300)
# ============================================================================

# Requires run_with_timeout and log to be defined by the sourcing script.

ai_invoke() {
    local prompt_file="$1"
    local output_file="$2"
    local stage="$3"
    local finding_id="$4"
    shift 4
    # Remaining args are passed to claude -p (e.g. --output-format json --max-turns 5)

    local timeout="${AI_TIMEOUT:-${TIMEOUT:-300}}"

    if [[ "${PIPELINE_AUTO_MODE:-}" == "1" ]]; then
        # --- Auto mode (orchestrated by Claude Code session) ---
        local prompt_dest="$OUTPUT_DIR/prompt_${stage}_${finding_id}.md"
        cp "$prompt_file" "$prompt_dest"

        # Ensure finding dir exists for response files
        local finding_dir="$OUTPUT_DIR/findings/${finding_id}"
        mkdir -p "$finding_dir"

        # Check if response was already placed by the orchestrator
        local response_file="$finding_dir/response_${stage}.json"
        if [[ ! -f "$response_file" ]]; then
            response_file="$finding_dir/response_${stage}.txt"
        fi
        # Backward compat: check old flat path
        if [[ ! -f "$response_file" ]]; then
            response_file="$OUTPUT_DIR/response_${stage}_${finding_id}.json"
        fi
        if [[ ! -f "$response_file" ]]; then
            response_file="$OUTPUT_DIR/response_${stage}_${finding_id}.txt"
        fi

        if [[ -f "$response_file" ]]; then
            cp "$response_file" "$output_file"
            log "INFO" "Auto mode: response found for $stage/$finding_id"
            return 0
        fi

        # Write descriptor for the orchestrating Claude session
        python3 -c "
import json
desc = {
    'stage': '$stage',
    'finding_id': '$finding_id',
    'prompt_file': '$prompt_dest',
    'expected_response': '$finding_dir/response_${stage}.json',
    'output_file': '$output_file'
}
with open('$OUTPUT_DIR/pending_stage.json', 'w') as f:
    json.dump(desc, f, indent=2)
"
        log "INFO" "Auto mode: prompt written, pending_stage.json created for $stage/$finding_id"
        return 42  # Special exit code: needs AI response

    elif [[ "${PIPELINE_SESSION_MODE:-}" == "1" ]]; then
        # --- Session mode ---
        # Write prompt to output dir for the orchestrating session
        local prompt_dest="$OUTPUT_DIR/prompt_${stage}_${finding_id}.md"
        cp "$prompt_file" "$prompt_dest"

        # Ensure finding dir exists for response files
        local finding_dir="$OUTPUT_DIR/findings/${finding_id}"
        mkdir -p "$finding_dir"

        # Check if response was pre-placed by the session
        local response_file="$finding_dir/response_${stage}.json"
        if [[ ! -f "$response_file" ]]; then
            response_file="$finding_dir/response_${stage}.txt"
        fi
        # Backward compat: check old flat path
        if [[ ! -f "$response_file" ]]; then
            response_file="$OUTPUT_DIR/response_${stage}_${finding_id}.json"
        fi
        if [[ ! -f "$response_file" ]]; then
            response_file="$OUTPUT_DIR/response_${stage}_${finding_id}.txt"
        fi

        if [[ -f "$response_file" ]]; then
            cp "$response_file" "$output_file"
            log "INFO" "Session mode: using pre-placed response for $finding_id"
            return 0
        else
            log "INFO" "Session mode: prompt written to $prompt_dest — awaiting response"
            # Write a marker file so the orchestrator knows what's pending
            echo "$prompt_dest" >> "$OUTPUT_DIR/pending_prompts.txt"
            return 42  # Special exit code: needs AI response
        fi
    else
        # --- CLI mode ---
        local perm_mode="--permission-mode acceptEdits"
        if [[ "${PIPELINE_DOCKER:-}" == "1" ]]; then
            perm_mode="--dangerously-skip-permissions"
        fi

        # Resolve model from config unless --model already in args
        local model_arg=""
        local has_model=false
        for arg in "$@"; do
            [[ "$arg" == "--model" ]] && has_model=true && break
        done
        if [[ "$has_model" == "false" ]]; then
            local config_dir
            config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
            if [[ -f "$config_dir/pipeline_preferences.json" ]]; then
                local stage_model
                stage_model=$(python3 -c "
import json
with open('$config_dir/pipeline_preferences.json') as f:
    cfg = json.load(f)
models = cfg.get('pipeline',{}).get('claude_model',{})
stage_map = {'stage2':'analysis','stage3':'default','stage5':'prd','stage6':'prd',
             'stage7':'implementation','stage11':'verification','stage12':'benchmark'}
role = stage_map.get('$stage', 'default')
print(models.get(role, models.get('default', '')))
" 2>/dev/null || echo "")
                [[ -n "$stage_model" ]] && model_arg="--model $stage_model"
            fi
        fi

        local claude_exit=0
        run_with_timeout "$timeout" "$output_file" \
            env -u CLAUDECODE claude -p "$(cat "$prompt_file")" \
            $perm_mode $model_arg "$@" \
            || claude_exit=$?

        if [[ "$claude_exit" -ne 0 ]]; then
            log "WARN" "Claude CLI failed for $finding_id (exit=$claude_exit), retrying..."
            claude_exit=0
            run_with_timeout "$timeout" "$output_file" \
                env -u CLAUDECODE claude -p "$(cat "$prompt_file")" \
                $perm_mode "$@" \
                || claude_exit=$?
        fi

        return $claude_exit
    fi
}
