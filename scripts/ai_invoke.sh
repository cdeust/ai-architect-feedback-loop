#!/usr/bin/env bash
# ============================================================================
# ai_invoke.sh — Shared AI invocation helper for pipeline stages
# ============================================================================
#
# Provides `ai_invoke` function that replaces direct `claude -p` calls.
# Supports two modes:
#
#   1. CLI mode (default, for nightly unattended runs):
#      Calls `claude -p` via run_with_timeout.
#
#   2. Session mode (PIPELINE_SESSION_MODE=1):
#      Writes the prompt to the output dir for the current Claude Code
#      session to process. Reads the response from a well-known path.
#      The orchestrating session provides responses before the script runs.
#
# Usage:
#   source scripts/ai_invoke.sh
#   ai_invoke <prompt_file> <output_file> <stage> <finding_id> [claude_args...]
#
# Session mode file convention:
#   Prompt written to:   $OUTPUT_DIR/prompt_<stage>_<finding_id>.md
#   Response read from:  $OUTPUT_DIR/response_<stage>_<finding_id>.json
#
# Environment:
#   PIPELINE_SESSION_MODE=1  — enable session mode (skip claude -p)
#   AI_TIMEOUT              — timeout in seconds (default: 300)
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

    if [[ "${PIPELINE_SESSION_MODE:-}" == "1" ]]; then
        # --- Session mode ---
        # Write prompt to output dir for the orchestrating session
        local prompt_dest="$OUTPUT_DIR/prompt_${stage}_${finding_id}.md"
        cp "$prompt_file" "$prompt_dest"

        # Check if response was pre-placed by the session
        local response_file="$OUTPUT_DIR/response_${stage}_${finding_id}.json"
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
        local claude_exit=0
        run_with_timeout "$timeout" "$output_file" \
            env -u CLAUDECODE claude -p "$(cat "$prompt_file")" "$@" \
            || claude_exit=$?

        if [[ "$claude_exit" -ne 0 ]]; then
            log "WARN" "Claude CLI failed for $finding_id (exit=$claude_exit), retrying..."
            claude_exit=0
            run_with_timeout "$timeout" "$output_file" \
                env -u CLAUDECODE claude -p "$(cat "$prompt_file")" "$@" \
                || claude_exit=$?
        fi

        return $claude_exit
    fi
}
