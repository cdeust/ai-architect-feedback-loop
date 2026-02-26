# ============================================================================
# AI Architect Feedback Loop — Docker Image
# Multi-stage build: Python 3.12 + Node.js 20 + Claude Code CLI + gh CLI
# ============================================================================

# ---------------------------------------------------------------------------
# Builder stage
# ---------------------------------------------------------------------------
FROM python:3.12-slim-bookworm AS builder

# Node.js 20 LTS via NodeSource
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# gh CLI from GitHub's apt repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies
RUN pip install --no-cache-dir pyyaml

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM python:3.12-slim-bookworm

# Runtime system packages (ripgrep needed by Claude Code CLI)
RUN apt-get update && apt-get install -y --no-install-recommends \
        git jq make curl ca-certificates ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Copy Node.js runtime and Claude Code CLI from builder
COPY --from=builder /usr/bin/node /usr/bin/node
COPY --from=builder /usr/lib/node_modules /usr/lib/node_modules
COPY --from=builder /usr/bin/claude /usr/bin/claude
RUN ln -sf /usr/bin/node /usr/bin/nodejs

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages

# Copy gh CLI
COPY --from=builder /usr/bin/gh /usr/bin/gh

# Claude Code CLI expects ripgrep at a vendor path — create symlink
RUN ARCH=$(dpkg --print-architecture) && \
    ARCH_MAP="amd64:x64-linux arm64:arm64-linux" && \
    for pair in $ARCH_MAP; do \
        if [ "${pair%%:*}" = "$ARCH" ]; then \
            RG_DIR="/usr/bin/vendor/ripgrep/${pair##*:}"; \
            mkdir -p "$RG_DIR"; \
            ln -sf /usr/bin/rg "$RG_DIR/rg"; \
        fi; \
    done

# Create non-root pipeline user
RUN useradd -m -u 1000 -s /bin/bash pipeline \
    && mkdir -p /workspace/target /workspace/build /app \
    && chown -R pipeline:pipeline /workspace /app

# Copy pipeline repo
COPY --chown=pipeline:pipeline . /app

# Make all scripts executable
RUN chmod +x /app/scripts/*.sh /app/docker-entrypoint.sh \
    && chmod +x /app/scripts/hooks/*

# Environment
ENV PIPELINE_DOCKER=1
ENV PIPELINE_REPO=/app

USER pipeline
WORKDIR /app

ENTRYPOINT ["/app/docker-entrypoint.sh"]
