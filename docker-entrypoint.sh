#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Docker Entrypoint for AI Architect Feedback Loop
# ============================================================================
# Startup flow:
#   1. Validate /workspace/target exists and has .git
#   2. Configure git safe directories
#   3. Clone target repo → /workspace/build (local clone, independent branches)
#   4. Run setup wizard if no config/pipeline.yml
#   5. Resolve config to generate individual config files
#   6. Install pre-commit hooks in clone
#   7. Dispatch on command argument
# ============================================================================

TARGET_DIR="/workspace/target"
BUILD_DIR="/workspace/build"
PIPELINE_REPO="${PIPELINE_REPO:-/app}"
CONFIG_DIR="$PIPELINE_REPO/config"

log() {
    echo "[entrypoint] $*"
}

# ---------------------------------------------------------------------------
# Step 1: Validate target repo
# ---------------------------------------------------------------------------
if [[ ! -d "$TARGET_DIR/.git" ]]; then
    echo "ERROR: /workspace/target must be a git repository."
    echo ""
    echo "Usage:"
    echo "  docker run --rm -it \\"
    echo "    -v /path/to/your-repo:/workspace/target:ro \\"
    echo "    ai-architect-pipeline:latest"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1.5: Make ~/.claude writable for Claude Code CLI
# ---------------------------------------------------------------------------
# The host's ~/.claude is mounted read-only at /home/pipeline/.claude-host.
# Claude CLI needs to write debug logs, todos, and plugin state.
# Copy essential config files into the writable home directory.
CLAUDE_HOME="/home/pipeline/.claude"
CLAUDE_MOUNT="/home/pipeline/.claude-host"
mkdir -p "$CLAUDE_HOME/debug" "$CLAUDE_HOME/todos" "$CLAUDE_HOME/plugins"

if [[ -d "$CLAUDE_MOUNT" ]]; then
    log "Setting up writable Claude config from host mount..."
    # Copy config files (not debug/history/cache which are huge)
    for f in settings.json stats-cache.json .credentials.json; do
        [[ -f "$CLAUDE_MOUNT/$f" ]] && cp "$CLAUDE_MOUNT/$f" "$CLAUDE_HOME/$f"
    done
    [[ -d "$CLAUDE_MOUNT/skills" ]] && cp -r "$CLAUDE_MOUNT/skills" "$CLAUDE_HOME/skills"
    [[ -f "$CLAUDE_MOUNT/plugins/blocklist.json" ]] && cp "$CLAUDE_MOUNT/plugins/blocklist.json" "$CLAUDE_HOME/plugins/"
fi

# Copy ~/.claude.json (account config) — required for Claude CLI to recognize the session.
# Without it, Claude CLI treats the session as a fresh install and prompts for login.
CLAUDE_JSON_MOUNT="/home/pipeline/.claude-host-json/.claude.json"
CLAUDE_JSON_HOME="/home/pipeline/.claude.json"
if [[ -f "$CLAUDE_JSON_MOUNT" && ! -f "$CLAUDE_JSON_HOME" ]]; then
    log "Copying .claude.json from host mount..."
    cp "$CLAUDE_JSON_MOUNT" "$CLAUDE_JSON_HOME"
    chmod 600 "$CLAUDE_JSON_HOME"
fi

# Write credentials for Claude CLI from CLAUDE_CODE_OAUTH_TOKEN.
# Accepts either:
#   - Full JSON: {"claudeAiOauth": {"accessToken": "...", "refreshToken": "...", ...}}
#   - Plain token string: sk-ant-oat01-... (used by community Docker setups)
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" && ! -f "$CLAUDE_HOME/.credentials.json" ]]; then
    log "Writing OAuth credentials from CLAUDE_CODE_OAUTH_TOKEN..."
    if echo "$CLAUDE_CODE_OAUTH_TOKEN" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        # Full JSON credentials object — write as-is
        echo "$CLAUDE_CODE_OAUTH_TOKEN" > "$CLAUDE_HOME/.credentials.json"
    else
        # Plain token string — wrap in expected format
        python3 -c "
import json, sys, time
token = sys.argv[1]
creds = {'claudeAiOauth': {
    'accessToken': token, 'refreshToken': '',
    'expiresAt': int(time.time() * 1000) + 28800000
}}
with open('$CLAUDE_HOME/.credentials.json', 'w') as f:
    json.dump(creds, f)
" "$CLAUDE_CODE_OAUTH_TOKEN"
    fi
    chmod 600 "$CLAUDE_HOME/.credentials.json"
fi

# Verify Claude CLI has credentials
if [[ ! -f "$CLAUDE_HOME/.credentials.json" && -z "${ANTHROPIC_API_KEY:-}" && -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    log "WARNING: No Claude credentials found. Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY,"
    log "WARNING: or mount credentials at /home/pipeline/.claude-host/.credentials.json"
fi

# ---------------------------------------------------------------------------
# Step 2: Git safe directories and identity
# ---------------------------------------------------------------------------
git config --global --add safe.directory "$TARGET_DIR"
git config --global --add safe.directory "$BUILD_DIR"

# Git identity — required for commits (Claude auto-commit, pipeline branches)
git config --global user.email "${GIT_USER_EMAIL:-pipeline@ai-architect.local}"
git config --global user.name "${GIT_USER_NAME:-AI Architect Pipeline}"

# Git credential helper — use GH_TOKEN for HTTPS push/pull (Stage 14)
if [[ -n "${GH_TOKEN:-}" ]]; then
    CRED_SCRIPT="/home/pipeline/.git-credential-helper.sh"
    cat > "$CRED_SCRIPT" <<CREDEOF
#!/bin/sh
echo "username=x-access-token"
echo "password=${GH_TOKEN}"
CREDEOF
    chmod +x "$CRED_SCRIPT"
    git config --global credential.helper "$CRED_SCRIPT"
fi

# ---------------------------------------------------------------------------
# Step 3: Clone target repo → /workspace/build
# ---------------------------------------------------------------------------
if [[ ! -d "$BUILD_DIR/.git" ]]; then
    log "Cloning target repo into $BUILD_DIR..."

    # Get the real remote URL from the target repo
    REMOTE_URL=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || echo "")

    # Local clone (uses hardlinks, fast)
    git clone "$TARGET_DIR" "$BUILD_DIR"

    # Fix remote URL to point to the real GitHub remote (not the local mount)
    if [[ -n "$REMOTE_URL" ]]; then
        git -C "$BUILD_DIR" remote set-url origin "$REMOTE_URL"
        log "Remote URL set to: $REMOTE_URL"
    fi

    # Ensure clone is on the configured base branch
    if [[ -f "$CONFIG_DIR/project.json" ]]; then
        BASE_BRANCH=$(python3 -c "
import json, sys
with open('$CONFIG_DIR/project.json') as f:
    cfg = json.load(f)
print(cfg.get('base_branch', 'main'))
" 2>/dev/null || echo "main")

        CURRENT_BRANCH=$(git -C "$BUILD_DIR" branch --show-current)
        if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
            log "Switching clone to base branch: $BASE_BRANCH"
            git -C "$BUILD_DIR" checkout "$BASE_BRANCH" 2>/dev/null \
                || git -C "$BUILD_DIR" checkout -b "$BASE_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null \
                || log "WARN: Could not switch to $BASE_BRANCH, staying on $CURRENT_BRANCH"
        fi
    fi

    log "Clone ready at $BUILD_DIR"
else
    log "Clone already exists at $BUILD_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4: Run setup wizard if no pipeline.yml
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_DIR/pipeline.yml" ]]; then
    log "No pipeline.yml found — running setup wizard..."
    if [[ -t 0 ]]; then
        # Interactive TTY attached
        python3 "$PIPELINE_REPO/scripts/setup_wizard.py" \
            --builder-dir "$TARGET_DIR" \
            --output "$CONFIG_DIR/pipeline.yml"
    else
        # Non-interactive mode
        python3 "$PIPELINE_REPO/scripts/setup_wizard.py" \
            --builder-dir "$TARGET_DIR" \
            --output "$CONFIG_DIR/pipeline.yml" \
            --non-interactive
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Resolve config
# ---------------------------------------------------------------------------
if [[ -f "$CONFIG_DIR/pipeline.yml" ]]; then
    log "Resolving configuration..."
    python3 "$PIPELINE_REPO/scripts/resolve_config.py" \
        --config "$CONFIG_DIR/pipeline.yml" \
        --output-dir "$CONFIG_DIR" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 5.5: Ensure clone is on the base branch (config now available)
# ---------------------------------------------------------------------------
if [[ -f "$CONFIG_DIR/project.json" ]]; then
    BASE_BRANCH=$(python3 -c "
import json
with open('$CONFIG_DIR/project.json') as f:
    cfg = json.load(f)
print(cfg.get('base_branch', 'main'))
" 2>/dev/null || echo "main")

    CURRENT_BRANCH=$(git -C "$BUILD_DIR" branch --show-current)
    if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
        log "Switching clone to base branch: $BASE_BRANCH"
        git -C "$BUILD_DIR" checkout "$BASE_BRANCH" 2>/dev/null \
            || git -C "$BUILD_DIR" checkout -b "$BASE_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null \
            || log "WARN: Could not switch to $BASE_BRANCH, staying on $CURRENT_BRANCH"
    fi
fi

# ---------------------------------------------------------------------------
# Step 5.6: Generate engine graph from source + overrides
# ---------------------------------------------------------------------------
if [[ -f "$CONFIG_DIR/engine_graph_overrides.json" && -f "$CONFIG_DIR/project.json" ]]; then
    log "Generating engine graph..."
    PACKAGES_DIR=$(python3 -c "
import json
cfg = json.load(open('$CONFIG_DIR/project.json'))
mdir = cfg.get('modules_dir', 'packages')
if mdir == '.':
    print('$BUILD_DIR')
else:
    print('$BUILD_DIR/' + mdir)
" 2>/dev/null || echo "$BUILD_DIR")
    python3 "$PIPELINE_REPO/scripts/generate_engine_graph.py" \
        --packages-dir "$PACKAGES_DIR" \
        --overrides "$CONFIG_DIR/engine_graph_overrides.json" \
        --output "$CONFIG_DIR/engine_graph.json" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 6: Pre-commit hooks — skipped in Docker pipeline mode
# Stage 10 (enforcement gates) runs as a separate pipeline stage with retry
# logic, so the pre-commit hook is redundant and blocks Claude's commits.
# ---------------------------------------------------------------------------
log "Skipping pre-commit hooks (Docker mode — Stage 10 gates run separately)"

# ---------------------------------------------------------------------------
# Step 7: Export and dispatch
# ---------------------------------------------------------------------------
export PIPELINE_BUILDER="$BUILD_DIR"

COMMAND="${1:-run}"
shift || true

case "$COMMAND" in
    run)
        log "Starting pipeline..."
        PIPELINE_ARGS=(--builder-dir "$BUILD_DIR")
        # Pass --tv-input if TV_INPUT env var is set (Docker findings file)
        [[ -n "${TV_INPUT:-}" ]] && PIPELINE_ARGS+=(--tv-input "$TV_INPUT")
        exec "$PIPELINE_REPO/scripts/pipeline.sh" \
            "${PIPELINE_ARGS[@]}" "$@"
        ;;
    setup)
        log "Running setup wizard..."
        exec python3 "$PIPELINE_REPO/scripts/setup_wizard.py" \
            --builder-dir "$TARGET_DIR" \
            --output "$CONFIG_DIR/pipeline.yml" "$@"
        ;;
    health)
        log "Running health check..."
        exec "$PIPELINE_REPO/scripts/health_check.sh" \
            --builder-dir "$BUILD_DIR" \
            --config "$CONFIG_DIR/thresholds.json" \
            --output "/tmp/health" "$@"
        ;;
    shell)
        log "Opening shell..."
        exec /bin/bash "$@"
        ;;
    claude)
        log "Starting Claude Code..."
        cd "$BUILD_DIR"
        exec claude --dangerously-skip-permissions "$@"
        ;;
    *)
        log "Unknown command: $COMMAND — running as pipeline"
        exec "$PIPELINE_REPO/scripts/pipeline.sh" \
            --builder-dir "$BUILD_DIR" "$@"
        ;;
esac
