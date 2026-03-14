# AI Architect Feedback Loop

**Feed it findings, get back pull requests.** A 14-stage autonomous pipeline for Claude Code that takes issues, specs, or research findings and turns them into production-ready PRs — with impact analysis, verified PRDs, tested implementations, and quality gates.

```
/plugin marketplace add cdeust/ai-architect-feedback-loop
/plugin install ai-architect-feedback-loop
```

Then run `/run-pipeline` from your project. Free, open source, works with any tech stack.

---

## What You Get

A summary like this at the end of every run:

```
=== Pipeline Complete: 20260221_020000 ===
Findings analyzed: 3
  [PASS] tv-042: PR #187 — improve core, api
  [PASS] tv-051: PR #188 — improve worker
  [FAIL] tv-063: Stage 7 build failure (3 attempts)
PRs created: 2
```

Each PR includes: impact analysis, integration plan, PRD excerpt, quality enforcement results, semantic verification, and retry history.

## How It Works

| Phase | Stages | What happens |
|---|---|---|
| **Discovery** | 1 | Parse findings, filter by relevance, prioritize by multi-module impact |
| **Analysis** | 2-6 | Impact scoring, integration design, PRD generation + review ([64 quality rules](docs/quality-rules.md) enforced) |
| **Implementation** | 7-11 | Feature branch, code changes, build + test, quality gates, semantic verification |
| **Delivery** | 12-14 | Benchmark, deployment simulation, PR creation per finding |

Each finding retries up to 3 times. Failed findings are skipped so the pipeline keeps moving. Full stage details: [docs/configuration.md](docs/configuration.md#pipeline-stages)

## Why This Exists

Most AI coding tools generate code from a prompt. This one:

- **Starts from findings, not prompts** — feed it output from code analysis tools, design reviews, bug reports, or research papers
- **Generates verified specs before code** — [9-file PRDs](https://github.com/cdeust/ai-prd-generator-plugin) with claim-by-claim verification, JIRA tickets, test cases
- **Implements and tests autonomously** — feature branches, build + test cycles, quality gates, up to 3 retries
- **Opens real PRs** — structured pull requests with full context, one per finding

## Quick Start

### Via Claude Code Marketplace

```
/plugin marketplace add cdeust/ai-architect-feedback-loop
/plugin install ai-architect-feedback-loop
```

### Manual Setup

```bash
git clone https://github.com/cdeust/ai-architect-feedback-loop.git
cd ai-architect-feedback-loop
export PIPELINE_BUILDER="/absolute/path/to/your-product"
make setup            # wizard auto-detects your stack
make pipeline-health  # verify everything is ready
claude                # then type: /run-pipeline
```

The setup wizard detects your project language, module structure, build/test commands, and git conventions. It generates `config/pipeline.yml` — the single source of truth for all settings.

### Docker (zero dependencies)

```bash
make docker-build                                    # one-time
TARGET_REPO=/path/to/your-product make docker-setup  # first time
TARGET_REPO=/path/to/your-product make docker-run   # run pipeline
```

The container clones your repo (original mounted read-only), installs quality gate hooks, and runs Claude Code in sandbox mode.

Requires: Docker, `CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`. Details: [docs/docker.md](docs/docker.md)

## Feeding Findings

Findings are structured JSON — issues, specs, or improvements for the pipeline to analyze and implement:

```json
{
  "source": "your-tool-name",
  "findings": [
    {
      "id": "spec-001",
      "title": "Add token refresh to auth flow",
      "description": "Silent refresh using refresh_token grant type",
      "relevance_category": "api_change",
      "relevance_score": 0.9
    }
  ]
}
```

Full schema: [docs/findings-format.md](docs/findings-format.md)

## Configuration

The setup wizard handles everything. To customize later:

```bash
vim config/pipeline.yml
```

What you can customize: build/test commands, branch naming, commit format, PR labels, quality thresholds, max findings per run, notification sound, nightly schedule.

Full reference: [docs/configuration.md](docs/configuration.md)

## The PRD Generator

Stage 5 uses the **[AI PRD Generator](https://github.com/cdeust/ai-prd-generator-plugin)** — a standalone plugin you can also use independently. It produces 9 verified files per PRD: overview, requirements, user stories, technical spec, acceptance criteria, roadmap, JIRA tickets, test cases, and a verification report.

If you only need PRD generation (no pipeline), install that plugin directly:

```
/plugin marketplace add cdeust/ai-prd-generator-plugin
/plugin install ai-prd-generator
```

## Troubleshooting

| Issue | Fix |
|---|---|
| `PIPELINE_BUILDER` not set | `export PIPELINE_BUILDER="/path/to/your-product"` |
| `pipeline.yml` validation errors | `make validate-config` for details |
| Stage 5 fails with "skill not found" | Install the `ai-prd-generator` plugin |
| Build failures in Stage 7 | Verify `build_command` in `pipeline.yml` works in your target repo |
| `gh` errors in Stage 14 | `gh auth login` to authenticate |
| Docker clone fails | Set `TARGET_REPO` to a valid git repo path |

## System Requirements

- Python 3.10+, `gh` CLI (authenticated), git, jq, PyYAML
- Claude Code (Anthropic)
- Docker (optional, for containerized runs)

---

Built by [Clement Deust](https://ai-architect.tools)
