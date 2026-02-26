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
if [[ -d "$CLAUDE_MOUNT" ]]; then
    log "Setting up writable Claude config from host mount..."
    mkdir -p "$CLAUDE_HOME/debug" "$CLAUDE_HOME/todos" "$CLAUDE_HOME/plugins"
    # Copy only config files (not debug/history/cache which are huge)
    for f in settings.json stats-cache.json; do
        [[ -f "$CLAUDE_MOUNT/$f" ]] && cp "$CLAUDE_MOUNT/$f" "$CLAUDE_HOME/$f"
    done
    [[ -d "$CLAUDE_MOUNT/skills" ]] && cp -r "$CLAUDE_MOUNT/skills" "$CLAUDE_HOME/skills"
    [[ -f "$CLAUDE_MOUNT/plugins/blocklist.json" ]] && cp "$CLAUDE_MOUNT/plugins/blocklist.json" "$CLAUDE_HOME/plugins/"
fi

# ---------------------------------------------------------------------------
# Step 2: Git safe directories
# ---------------------------------------------------------------------------
git config --global --add safe.directory "$TARGET_DIR"
git config --global --add safe.directory "$BUILD_DIR"

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
# Step 6: Install pre-commit hooks in clone
# ---------------------------------------------------------------------------
if [[ -f "$PIPELINE_REPO/scripts/install-hooks.sh" ]]; then
    log "Installing pre-commit hooks..."
    bash "$PIPELINE_REPO/scripts/install-hooks.sh" "$BUILD_DIR"
fi

# ---------------------------------------------------------------------------
# Step 7: Export and dispatch
# ---------------------------------------------------------------------------
export PIPELINE_BUILDER="$BUILD_DIR"

COMMAND="${1:-run}"
shift || true

case "$COMMAND" in
    run)
        log "Starting pipeline..."
        exec "$PIPELINE_REPO/scripts/pipeline.sh" \
            --builder-dir "$BUILD_DIR" "$@"
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
