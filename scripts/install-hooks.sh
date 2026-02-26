#!/usr/bin/env bash
# Usage: scripts/install-hooks.sh <target-dir>
set -euo pipefail

TARGET_DIR="$(realpath "$1")"
REPO_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
GIT_DIR="$(git -C "$TARGET_DIR" rev-parse --git-dir)"
# Make absolute if relative
if [[ "$GIT_DIR" != /* ]]; then
    GIT_DIR="$TARGET_DIR/$GIT_DIR"
fi
HOOKS_DIR="$GIT_DIR/hooks"

mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/scripts/hooks/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
echo "Pre-commit hook installed in $HOOKS_DIR"
