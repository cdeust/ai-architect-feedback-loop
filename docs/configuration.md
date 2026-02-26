# Configuration

The pipeline uses a single `config/pipeline.yml` as the source of truth for **all** settings. A resolver generates the individual config files that scripts expect.

---

## Manual setup

If you prefer to configure manually instead of using `make setup`:

```bash
# 1. Clone the repository
git clone <this-repo-url>
cd feedback-loop

# 2. Install your license key
mkdir -p ~/.aiprd
echo "YOUR_LICENSE_KEY" > ~/.aiprd/license-key

# 3. Set the target product path
export PIPELINE_BUILDER="/absolute/path/to/your-product"

# 4. Configure for your stack
cp config/pipeline.yml.example config/pipeline.yml
vim config/pipeline.yml

# 5. Verify the setup
make pipeline-health
```

The target product repository must be a git repository. If it has a `CLAUDE.md` file describing its architecture, the pipeline uses it to enrich Stages 3, 7, and 11.

---

## How it works

```
pipeline.yml (you edit this one file)
      |
      v
resolve_config.py (generates files scripts already expect)
      |
      +-- config/project.json
      +-- config/architecture.md
      +-- config/engine_graph_overrides.json
      +-- config/category_engine_map.json
      +-- config/thresholds.json
      +-- config/prohibited_patterns.txt
      +-- config/pipeline_preferences.json    (git, PR, pipeline prefs)
      +-- config/com.ai-architect.pipeline-feedback.plist
```

## pipeline.yml sections

`pipeline.yml` has 12 sections. See `config/pipeline.yml.example` for a fully commented reference.

| Section | What it controls |
|---|---|
| `project` | Language, extensions, build/test commands, module structure |
| `license` | License key path and validation toggle |
| `architecture` | Free-form markdown injected into AI prompts |
| `modules` | Module dependency graph (roles, feeds, fed_by) |
| `categories` | Finding category to module mapping |
| `git` | Branch naming patterns, commit message format, remote |
| `pr` | PR title format, labels, engine labeling, PRD line limit |
| `pipeline` | Max findings, max implementations, exclusions, Claude CLI turns/timeouts |
| `notifications` | macOS notification sound, title, enable/disable |
| `thresholds` | Scoring gates for all pipeline stages |
| `patterns` | Prohibited code patterns (regex, one per line) |
| `schedule` | Nightly run hour and minute |

## Sections reference

| Section | Key fields | Defaults |
|---|---|---|
| `project` | `language`, `modules_dir`, `base_branch`, `build_command`, `test_command` | Python, packages, main, make build, make test |
| `license` | `key_file`, `validate_on_run` | ~/.aiprd/license-key, true |
| `git` | `feature_branch_pattern`, `commit_message`, `remote` | pipeline/improvement-{finding_id}, origin |
| `pr` | `title`, `labels`, `label_engines`, `prd_max_lines` | pipeline-generated + improvement labels, 100 lines |
| `pipeline` | `top_n_findings`, `max_implementations`, `claude_max_turns`, `claude_timeout` | 20, 5, 30 turns impl, 1800s impl |
| `notifications` | `enabled`, `sound`, `title` | true, Glass, AI-Architect Pipeline |
| `thresholds` | `stage_2.compound_score_minimum`, `stage_5.prd_quality_minimum`, `retry.max_attempts` | 0.3, 0.85, 3 |
| `schedule` | `hour`, `minute` | 2:00 AM |

## Config management commands

```bash
make setup            # Interactive wizard — generates pipeline.yml from scratch
make resolve-config   # Regenerate individual config files from pipeline.yml
make validate-config  # Validate pipeline.yml without generating files
make migrate-config   # Migrate existing JSON/MD configs to pipeline.yml (one-time)
```

The resolver runs automatically before pipeline targets when `pipeline.yml` is newer than the last resolve. If `pipeline.yml` doesn't exist, the pipeline reads individual config files directly — fully backward compatible.

## Migrating from individual config files

If you already have configured JSON/MD files:

```bash
make migrate-config
```

This reads your existing `project.json`, `thresholds.json`, `engine_graph_overrides.json`, `category_engine_map.json`, `architecture.md`, `prohibited_patterns.txt`, and plist file, then produces a unified `pipeline.yml`. Your original files are not modified.

## Example: changing a setting

To change the maximum findings per run from 20 to 10:

```yaml
# config/pipeline.yml
pipeline:
  top_n_findings: 10    # was 20
```

Then either run `make resolve-config` or let the auto-resolve trigger on the next pipeline run.

## Example: custom branch naming

```yaml
git:
  feature_branch_pattern: "auto/{finding_id}"
  commit_message: "fix({finding_id}): {description}"
pr:
  title: "[Pipeline] {engines}: {finding_id}"
  labels:
    - automated
    - needs-review
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `PIPELINE_BUILDER` | **Yes** | Absolute path to the target product repository |
| `PIPELINE_REPO` | No | Override the feedback-loop repo path (defaults to `pwd`) |

## Project structure

```
.
├── .claude/
│   └── commands/
│       └── run-pipeline.md          # The /run-pipeline slash command
├── config/
│   ├── pipeline.yml                 # Unified config (single source of truth)
│   ├── pipeline.yml.example         # Fully commented example with all 12 sections
│   ├── project.json                 # Generated — project settings
│   ├── architecture.md              # Generated — architecture description
│   ├── thresholds.json              # Generated — scoring thresholds
│   ├── category_engine_map.json     # Generated — category-to-module mapping
│   ├── engine_graph_overrides.json  # Generated — module dependency graph
│   ├── prohibited_patterns.txt      # Generated — anti-pattern regex rules
│   ├── pipeline_preferences.json    # Generated — git/PR/pipeline preferences
│   └── com.ai-architect.pipeline-feedback.plist  # Generated — launchd schedule
├── prompts/                         # Stage prompt templates
│   ├── impact_analysis.md
│   ├── integration_design.md        # Includes design principles
│   ├── prd_generation.md            # Enforces 64 hard output rules
│   ├── implementation.md            # Solution design quality requirements
│   └── semantic_verification.md     # Genericity & scalability verification
├── scripts/
│   ├── pipeline.sh                  # Main orchestrator
│   ├── resolve_config.py            # pipeline.yml -> individual config files
│   ├── setup_wizard.py              # Interactive setup wizard
│   ├── load_project_config.py       # Shared config loader
│   ├── stage[1-14]-*.sh             # Individual stage scripts
│   ├── validate_*.py                # Output validators
│   └── test_*.{sh,py}              # Test suite
├── benchmarks/
│   ├── baselines/                   # Reference PRDs and metrics
│   └── inputs/                      # Benchmark input fixtures
├── runs/                            # Pipeline run outputs (gitignored)
├── Makefile                         # Make targets for all stages + config management
└── README.md
```

## Prompt templates

The files in `prompts/` use `{{ARCHITECTURE_DESCRIPTION}}` and other placeholders that are populated from your configuration. They are stack-agnostic by default — no language-specific content needs to be changed.

Each prompt template enforces quality standards:
- **Integration design** — Design principles: parameterize, extend abstractions, compose, think one level up, backward compatibility via defaults
- **PRD generation** — 64 hard output rules: SP arithmetic, clean architecture, SOLID compliance, security hardening, data protection, resilience patterns, concurrency safety, observability, and more
- **Implementation** — Solution design quality: no magic constants, general mechanisms, reusable utilities, generic naming
- **Semantic verification** — Adversarial review: solution genericity, scalability, cross-module integration, anti-pattern detection

## Pipeline stages

### Stage 1 — Parse findings
Reads the input JSON, filters findings by relevance category and score threshold, and produces a ranked list for prioritization.

### Stage 2 — Impact analysis
Computes a compound impact score across four dimensions: modules affected, propagation depth, contract impact, and test coverage delta. Findings must score above 0.3 and affect at least 2 modules to proceed.

### Stage 3 — Integration design
Designs architectural modifications respecting the target product's architecture. Enforces [design principles](quality-rules.md#design-principles-in-implementation): parameterization, centralization, composability, backward compatibility. Validates that all referenced files exist and interface changes are consistent.

### Stage 4 — Plan Deliberation (Apple Intelligence only)
Skipped in CLI/Docker mode. On macOS with Apple Intelligence, deliberates on the integration plan.

### Stage 5 — PRD generation
Invokes the **AI PRD Generator** skill to produce four documents: `prd.md`, `prd-verification.md`, `prd-jira.md`, and `prd-tests.md`. Enforces all [64 hard output rules](quality-rules.md). Scope (simple/moderate/complex) is derived automatically from pipeline artifacts.

### Stage 6 — PRD review
An independent AI review of the generated PRD for completeness, consistency, and actionability.

### Stage 7 — Implementation
Creates a feature branch, implements code changes following the PRD and integration plan, builds the project, and runs tests. Enforces [code quality rules](quality-rules.md#architecture--code-quality-rules-18-24), [security rules](quality-rules.md#security-rules-25-32), [resilience rules](quality-rules.md#error-handling--resilience-rules-39-43), and [testing rules](quality-rules.md#comprehensive-testing-rules-53-58).

### Stages 8-9 — Drift Reconciliation & Agreement (Apple Intelligence only)
Skipped in CLI/Docker mode. On macOS with Apple Intelligence, reconciles implementation drift.

### Stage 10 — Quality gates
Runs deterministic checks: prohibited pattern detection, orphan file detection, build verification, test suite, and deployment verification.

### Stage 11 — Semantic verification
An independent verifier analyzes the git diff against the PRD. Checks alignment score (must be >= 0.7), cross-module consistency, anti-patterns, and [solution genericity](quality-rules.md#design-principles-in-implementation) — flags hardcoded constants, single-purpose parameters, and non-extensible designs.

### Stage 12 — Benchmark
Measures quality metrics and compares against baselines. Informational — does not block the pipeline.

### Stage 13 — Deployment simulation
Runs the configured `deploy_command` from `config/project.json`. If no deploy command is configured, the stage passes automatically.

### Stage 14 — Pull request
Creates a pull request per finding with a structured description linking back to the impact analysis and PRD.

## Run individual stages via Make

All Make targets require `BUILDER_DIR` (or `PIPELINE_BUILDER`) to be set:

```bash
export PIPELINE_BUILDER="/path/to/your-product"

make pipeline-stage1          # Parse findings
make pipeline-stage2          # Impact analysis
make pipeline-stage3          # Integration design
make pipeline-stage5          # PRD generation (requires license)
make pipeline-stage6          # PRD review
make pipeline-stage7          # Implementation
make pipeline-gates           # Quality gates (stage 10)
make pipeline-stage11         # Semantic verification
make pipeline-benchmark       # Benchmarking (stage 12)
make pipeline-stage13         # Deployment simulation
make pipeline-stage14         # PR creation
```

## Schedule nightly runs

```bash
make install-scheduler        # Install launchd agent (runs at configured hour)
make uninstall-scheduler      # Remove the scheduler
```

The schedule hour is configurable in `pipeline.yml` under the `schedule` section (default: 2 AM).
