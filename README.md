# AI Architect Feedback Loop

A fully autonomous 14-stage product improvement pipeline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Feed it findings, get back pull requests.

Works with **any tech stack** — Python, TypeScript, Go, Rust, Java, Kotlin, Swift, and more.

## What it does

- **Feed it issues, specs, or findings** from any source — code analysis tools, draft RFCs, design reviews, bug reports
- **It analyzes impact, writes PRDs, implements code, and runs tests** — with 64 quality rules enforced automatically
- **You get reviewed pull requests** with production-quality changes, one per finding

```
  Findings ──> [ Analysis ] ──> [ Implementation ] ──> Pull Requests
                 impact           code + tests          structured PR
                 design           quality gates         per finding
                 PRD gen          verification
```

## Quick start

```bash
# Requires: Claude Code, Python 3.10+, gh CLI (authenticated), git, jq, PyYAML
git clone <this-repo-url> && cd feedback-loop
export PIPELINE_BUILDER="/absolute/path/to/your-product"
make setup        # wizard auto-detects your stack, installs license
make pipeline-health  # verify everything is ready
claude            # then type: /run-pipeline
```

The setup wizard detects your project language, module structure, build/test commands, and git conventions. It generates `config/pipeline.yml` — the single source of truth for all settings. If your target repo has a `CLAUDE.md` describing its architecture, the pipeline uses it to enrich analysis and implementation.

## Docker quickstart

Run the pipeline in a container — zero dependencies to install:

```bash
make docker-build                                            # one-time
TARGET_REPO=/path/to/your-product make docker-setup          # first time
TARGET_REPO=/path/to/your-product make docker-run            # run pipeline
```

The container creates a **local clone** of your repo (original is mounted read-only), installs pre-commit hooks for quality gates, and runs Claude Code with `--dangerously-skip-permissions` (safe inside the container).

Requires: Docker, `CLAUDE_CODE_OAUTH_TOKEN` (run `claude setup-token`), `GH_TOKEN` (GitHub auth), `~/.aiprd/license-key`.

## What you get

A summary like this at the end of every run:

```
=== Pipeline Complete: 20260221_020000 ===
Findings analyzed: 3
  [PASS] tv-042: PR #187 — improve core, api
  [PASS] tv-051: PR #188 — improve worker
  [FAIL] tv-063: Stage 7 build failure (3 attempts)
PRs created: 2
```

Each PR includes: impact analysis, integration plan, PRD excerpt, quality enforcement results, semantic verification results, and retry history.

## How it works

| Phase | Stages | What happens |
|---|---|---|
| Discovery | 1 | Parse findings, filter by relevance, prioritize by multi-module impact |
| Analysis | 2-6 | Impact scoring, integration design, PRD generation + review ([64 quality rules](docs/quality-rules.md) enforced) |
| Implementation | 7-11 | Feature branch, code changes, build + test, quality gates, semantic verification |
| Delivery | 12-14 | Benchmark, deployment simulation, PR creation per finding |

Each finding retries up to 3 times. Failed findings are skipped so the pipeline keeps moving.

Full stage details: [docs/configuration.md](docs/configuration.md#pipeline-stages)

## Configuration

The setup wizard handles everything. To customize later:

```bash
# Edit the single config file
vim config/pipeline.yml

# Or see the fully commented example
cat config/pipeline.yml.example
```

What you can customize:
- Build/test commands, language, module structure
- Branch naming, commit format, PR labels
- Quality thresholds, max findings per run
- Notification sound, nightly schedule

Full reference: [docs/configuration.md](docs/configuration.md)

## Feeding findings to the pipeline

Findings are structured JSON items — issues, specs, or improvements for the pipeline to analyze and implement. Minimal example:

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

Full schema and field reference: [docs/findings-format.md](docs/findings-format.md)

## Troubleshooting

| Issue | Fix |
|---|---|
| `PIPELINE_BUILDER` not set | `export PIPELINE_BUILDER="/path/to/your-product"` |
| `[FAIL] License key not found` | Run `make setup` or place your key at `~/.aiprd/license-key` |
| `[FAIL] License invalid` | Verify your key at [ai-architect.tools](https://ai-architect.tools) |
| `pipeline.yml` validation errors | Run `make validate-config` for detailed error messages |
| PyYAML not installed | `pip install pyyaml` |
| Stage 5 fails with "skill not found" | Ensure the `ai-prd-generator` skill is installed |
| Build failures in Stage 7 | Verify `build_command` in `pipeline.yml` works in your target repo |
| Test failures in Stage 7 | Verify `test_command` in `pipeline.yml` works in your target repo |
| `gh` errors in Stage 14 | Run `gh auth login` to authenticate the GitHub CLI |
| Health check fails on tools | Add missing tools to your PATH or update `required_tools` in `pipeline.yml` |
| Docker: `/workspace/target must be a git repository` | Set `TARGET_REPO` to a valid git repo path |
| Docker: clone fails or wrong branch | Ensure your target repo has the `base_branch` configured in `project.json` |
| Docker: permission denied on volumes | Check that `~/.claude`, `~/.config/gh`, and `~/.aiprd` exist and are readable |

## License

The `/run-pipeline` command is **free to use**.

The pipeline depends on the **AI PRD Generator** skill at Stage 5. The PRD Generator is a licensed product and **requires a valid license key** from [ai-architect.tools](https://ai-architect.tools). The pipeline validates the license once at startup and reuses that validation for the entire run.

---

Built by [Clement DEUST](https://ai-architect.tools) as part of the **AI Architect** toolchain — AI-powered developer tools for product engineering.
