# AI Architect Feedback Loop

A fully autonomous 10-stage product improvement pipeline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It analyzes code findings, generates PRDs, implements fixes, enforces quality gates, and delivers pull requests — all through a single `/run-pipeline` slash command with zero human intervention.

Works with **any tech stack** — Python, TypeScript, Go, Rust, Java, Swift, and more — through configuration alone.

**Author:** Clement DEUST — [ai-architect.tools](https://ai-architect.tools)

## License

This pipeline command (`/run-pipeline`) is **free to use**.

The pipeline depends on the **AI PRD Generator** skill (`ai-prd-generator`) at Stage 4 to produce product requirement documents. The PRD Generator is a licensed product by Clement DEUST / [ai-architect.tools](https://ai-architect.tools) and **requires a valid license key** to operate.

You can obtain a license at [ai-architect.tools](https://ai-architect.tools). The pipeline validates the license once at startup (Step 0.1) and reuses that validation for the entire run.

## Quick start

```bash
# 1. Clone
git clone <this-repo-url>
cd feedback-loop

# 2. Install your AI PRD Generator license key
mkdir -p ~/.aiprd
echo "YOUR_LICENSE_KEY" > ~/.aiprd/license-key

# 3. Point the pipeline at your target product
export PIPELINE_BUILDER="/absolute/path/to/your-product"

# 4. Configure for your stack (see Configuration below)
# Edit config/project.json and config/architecture.md

# 5. Verify everything is ready
make pipeline-health-check

# 6. Run the pipeline
claude                  # launch Claude Code
/run-pipeline           # type this in the Claude Code session
```

## Prerequisites

| Requirement | Notes |
|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | CLI must be installed and authenticated |
| Python 3.10+ | Used by validators and scoring scripts |
| `jq` | JSON processing in stage scripts |
| `gh` | GitHub CLI — for PR creation (Stage 10). Run `gh auth login` first. |
| `git` | Repository operations |
| AI PRD Generator license | See [License](#license) above |

## Setup

### 1. Clone the repository

```bash
git clone <this-repo-url>
cd feedback-loop
```

### 2. Install your license key

Get a key from [ai-architect.tools](https://ai-architect.tools), then:

```bash
mkdir -p ~/.aiprd
echo "YOUR_LICENSE_KEY" > ~/.aiprd/license-key
```

### 3. Set the target product path

The pipeline needs to know where your target product repository lives. Set the `PIPELINE_BUILDER` environment variable to its **absolute path**:

```bash
export PIPELINE_BUILDER="/absolute/path/to/your-product"
```

To make this persistent, add it to your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
export PIPELINE_BUILDER="/absolute/path/to/your-product"
```

The target product repository must:
- Be a git repository
- Optionally have a `CLAUDE.md` file describing its architecture (enriches Stages 3, 5, and 7)

### 4. Configure for your stack

The pipeline is stack-agnostic. Configure it for your project through two files:

#### `config/project.json` — Project settings

This file tells the pipeline about your language, build tools, and project structure:

```json
{
  "language": "python",
  "source_extensions": [".py"],
  "test_file_patterns": ["**/test_*.py", "**/*_test.py"],
  "test_dir_name": "tests",
  "module_prefix": "",
  "modules_dir": "packages",
  "domain_module": null,
  "interface_suffix": null,
  "base_branch": "main",
  "build_command": "make build",
  "test_command": "make test",
  "deploy_command": null,
  "required_tools": ["python3", "git", "gh", "jq", "claude"],
  "contract_extractor": null
}
```

| Field | Description |
|---|---|
| `language` | Primary language (`python`, `typescript`, `swift`, `go`, `kotlin`, `java`, etc.) |
| `source_extensions` | File extensions to scan (e.g. `[".py"]`, `[".ts", ".tsx"]`, `[".kt", ".kts"]`) |
| `test_file_patterns` | Glob patterns for test files |
| `test_dir_name` | Test directory name convention |
| `module_prefix` | Prefix stripped from directory names for module discovery |
| `modules_dir` | Directory containing modules/packages relative to repo root. Use `"."` if modules are at the repo root (e.g. multi-module Android/Gradle projects) |
| `domain_module` | Name of shared/domain module (if any) |
| `interface_suffix` | Suffix for interface types (if any) |
| `base_branch` | Main/default branch name (default: `"main"`). Use `"develop"`, `"develop-ui"`, etc. if your project uses a different base branch |
| `build_command` | Single build command to run in the target project |
| `test_command` | Single test command to run in the target project |
| `deploy_command` | Deployment command or `null` to skip deployment stage |
| `required_tools` | Binaries to check in health check |
| `contract_extractor` | Custom script path for extracting interfaces (`null` = built-in) |

#### `config/architecture.md` — Architecture description

Write a markdown description of your product's architecture. This text is injected into AI prompts so Claude understands your codebase structure:

```markdown
# Project Architecture

## Module Structure
- auth/ — Authentication and authorization
- api/ — REST API endpoints
- core/ — Business logic and domain models

## Key Patterns
- Layered architecture with dependency inversion
- All cross-module communication through defined interfaces

## Constraints
- core/ must have zero framework imports
- New features must include tests
```

### 5. Adapt module configuration

**`config/engine_graph_overrides.json`** — Define your product's module dependency graph:

```json
{
  "description": "Module dependency graph",
  "engines": {
    "core": {
      "role": "shared_infrastructure",
      "feeds": ["api", "worker"],
      "fed_by": []
    }
  }
}
```

**`config/category_engine_map.json`** — Map finding categories to your modules.

**`config/thresholds.json`** — Tune scoring thresholds.

**`config/prohibited_patterns.txt`** — Regex patterns that Stage 6 rejects.

### 6. Install the `/run-pipeline` command

The command is defined in `.claude/commands/run-pipeline.md` and is **automatically available** when you open Claude Code from within this project directory:

```bash
cd feedback-loop
claude
```

Type `/run-pipeline` in the Claude Code session to invoke it.

#### Using it in another project

Copy the command file into your target project:

```bash
mkdir -p /path/to/your-project/.claude/commands
cp .claude/commands/run-pipeline.md /path/to/your-project/.claude/commands/
```

Or install it as a personal command available across all projects:

```bash
mkdir -p ~/.claude/commands
cp .claude/commands/run-pipeline.md ~/.claude/commands/
```

### 7. Verify the setup

```bash
make pipeline-health-check
```

This validates: toolchain (configured tools), target product accessibility, configuration file presence, and license key.

## Usage

### Run the full pipeline

From a Claude Code session inside the project:

```
/run-pipeline
```

The pipeline executes 10 stages autonomously:

| Phase | Stages | Description |
|---|---|---|
| Discovery | 1 | Parse and prioritize findings |
| Analysis | 2 – 4 | Impact analysis, integration design, PRD generation |
| Implementation | 5 – 7 | Code changes, quality gates, semantic verification |
| Delivery | 8 – 10 | Benchmarking, deployment simulation, PR creation |

Each stage prints a status line:

```
[PASS] Step 2.1: Impact analysis — compound_score=0.72, engines=4
[FAIL] Step 6.1: Gate 1 — prohibited pattern found (FIXME in line 42)
```

Failed stages retry up to 3 times before moving on. A summary report is generated at the end of the run.

### Run individual stages via Make

All Make targets require `BUILDER_DIR` (or `PIPELINE_BUILDER`) to be set:

```bash
export PIPELINE_BUILDER="/path/to/your-product"

make pipeline-stage1          # Parse findings
make pipeline-stage2          # Impact analysis
make pipeline-stage3          # Integration design
make pipeline-stage4          # PRD generation (requires license)
make pipeline-stage5          # Implementation
make pipeline-gates           # Quality gates
make pipeline-stage7          # Semantic verification
make pipeline-benchmark       # Benchmarking
make pipeline-stage9          # Deployment simulation
make pipeline-stage10         # PR creation
```

### Schedule nightly runs

```bash
make install-scheduler        # Install launchd agent (runs at 2 AM)
make uninstall-scheduler      # Remove the scheduler
```

## Findings input format

The pipeline consumes **findings** — structured items describing issues, improvements, or changes to analyze and implement. Findings can come from any source: code analysis tools, draft specs, design reviews, bug reports, or manual entries.

The pipeline accepts any JSON input that matches the schema below.

### Input JSON schema

Place a JSON file at one of these locations (checked in order by `/run-pipeline`):
1. `~/Downloads/TechnicalVeil/` directory (legacy TV format)
2. `runs/findings_input.json` in the pipeline repo
3. `tv_output.json` in the target product repo

Or pass `--tv-input <path>` directly to `stage1-parse-findings.sh`:

```json
{
  "source": "your-tool-name",
  "findings": [
    {
      "id": "spec-001",
      "title": "Short title of the finding or draft spec",
      "description": "Detailed description of the issue, improvement, or spec. Max 500 chars used by the pipeline.",
      "source_url": "https://optional-link-to-source",
      "relevance_category": "api_change",
      "relevance_score": 0.8,
      "raw_data": {}
    }
  ]
}
```

### Required fields per finding

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier (used in branch names, file names, PR titles) |
| `title` | string | Short summary — becomes the PRD title |
| `description` | string | Detailed context — fed into Stage 2 impact analysis |
| `relevance_category` | string | Must match a key in `config/category_engine_map.json` |
| `relevance_score` | float | 0.0 – 1.0 relevance weight (filtered by `thresholds.json` minimum, default 0.5) |

### Optional fields

| Field | Type | Description |
|---|---|---|
| `source_url` | string | Link to the original source (included in PRs) |
| `raw_data` | object | Arbitrary metadata passed through to reports |

### Valid relevance categories

These are the default categories defined in `config/thresholds.json` and mapped to modules in `config/category_engine_map.json`:

`api_change` · `behavior_change` · `dependency_change` · `config_change` · `schema_change` · `performance_change` · `security_change`

Add or remove categories by editing both `thresholds.json` (stage_1.relevance_categories) and `category_engine_map.json` (mappings).

### Using draft specs as findings

Findings don't have to come from a code analysis tool. You can use the pipeline to process **draft specs**, **RFCs**, or **improvement proposals**:

```json
{
  "source": "draft_specs",
  "findings": [
    {
      "id": "spec-auth-refresh",
      "title": "Add token refresh to authentication flow",
      "description": "The current auth flow requires full re-login when tokens expire. Add silent refresh using the refresh_token grant type. Must handle concurrent requests during refresh and queue them until the new token is available.",
      "relevance_category": "api_change",
      "relevance_score": 0.9
    }
  ]
}
```

## Pipeline stages

### Stage 1 — Parse findings
Reads the input JSON, filters findings by relevance category and score threshold, and produces a ranked list for prioritization.

### Stage 2 — Impact analysis
Computes a compound impact score across four dimensions: modules affected, propagation depth, contract impact, and test coverage delta. Findings must score above 0.3 and affect at least 2 modules to proceed.

### Stage 3 — Integration design
Designs architectural modifications respecting the target product's architecture. Validates that all referenced files exist and interface changes are consistent.

### Stage 4 — PRD generation
Invokes the **AI PRD Generator** skill to produce four documents: `prd.md`, `prd-verification.md`, `prd-jira.md`, and `prd-tests.md`. Scope (simple/moderate/complex) is derived automatically from pipeline artifacts.

### Stage 5 — Implementation
Creates a feature branch, implements code changes following the PRD and integration plan, builds the project, and runs tests.

### Stage 6 — Quality gates
Runs deterministic checks: prohibited pattern detection, orphan file detection, build verification, test suite, and deployment verification.

### Stage 7 — Semantic verification
An independent verifier analyzes the git diff against the PRD. Checks alignment score (must be >= 0.7), cross-module consistency, and anti-patterns.

### Stage 8 — Benchmark
Measures quality metrics and compares against baselines. Informational — does not block the pipeline.

### Stage 9 — Deployment simulation
Runs the configured `deploy_command` from `config/project.json`. If no deploy command is configured, the stage passes automatically.

### Stage 10 — Pull request
Creates a pull request per finding with a structured description linking back to the impact analysis and PRD.

## Project structure

```
.
├── .claude/
│   └── commands/
│       └── run-pipeline.md        # The /run-pipeline slash command
├── config/
│   ├── project.json               # Project-specific settings (language, build, test)
│   ├── architecture.md            # Architecture description (injected into prompts)
│   ├── thresholds.json            # Scoring thresholds for all stages
│   ├── category_engine_map.json   # Finding category → module mapping
│   ├── engine_graph_overrides.json# Module dependency graph
│   └── prohibited_patterns.txt    # Anti-pattern regex rules
├── prompts/                       # Stage prompt templates
│   ├── impact_analysis.md
│   ├── integration_design.md
│   ├── prd_generation.md
│   ├── implementation.md
│   └── semantic_verification.md
├── scripts/                       # Stage scripts, validators, processors
│   ├── pipeline.sh                # Main orchestrator
│   ├── load_project_config.py     # Shared config loader
│   ├── stage[1-10]-*.sh           # Individual stage scripts
│   ├── validate_*.py              # Output validators
│   └── test_*.{sh,py}            # Test suite
├── benchmarks/
│   ├── baselines/                 # Reference PRDs and metrics
│   └── inputs/                    # Benchmark input fixtures
├── runs/                          # Pipeline run outputs (gitignored)
├── Makefile                       # Make targets for all stages
└── README.md
```

## Configuration

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `PIPELINE_BUILDER` | **Yes** | Absolute path to the target product repository |
| `PIPELINE_REPO` | No | Override the feedback-loop repo path (defaults to `pwd`) |

### Config files

Customize these files in `config/` to match your product:

| File | Purpose | Must customize? |
|---|---|---|
| `project.json` | Language, build/test commands, module structure | **Yes** |
| `architecture.md` | Free-form architecture description for AI prompts | **Yes** |
| `engine_graph_overrides.json` | Module dependency graph (roles, feeds, fed_by) | **Yes** |
| `category_engine_map.json` | Maps finding categories to affected modules | **Yes** |
| `thresholds.json` | Scoring minimums, retry limits, gate parameters | Recommended |
| `prohibited_patterns.txt` | Regex patterns rejected by Stage 6 | Optional |

### Prompt templates

The files in `prompts/` use `{{ARCHITECTURE_DESCRIPTION}}` and other placeholders that are populated from your configuration. They are stack-agnostic by default — no language-specific content needs to be changed.

## Troubleshooting

| Issue | Fix |
|---|---|
| `PIPELINE_BUILDER` not set | `export PIPELINE_BUILDER="/path/to/your-product"` |
| `[FAIL] License key not found` | Place your key at `~/.aiprd/license-key` |
| `[FAIL] License invalid` | Verify your key at [ai-architect.tools](https://ai-architect.tools) |
| Stage 4 fails with "skill not found" | Ensure the `ai-prd-generator` skill is installed |
| Build failures in Stage 5 | Verify `build_command` in `config/project.json` works in your target repo |
| Test failures in Stage 5 | Verify `test_command` in `config/project.json` works in your target repo |
| `gh` errors in Stage 10 | Run `gh auth login` to authenticate the GitHub CLI |
| Health check fails on tools | Add missing tools to your PATH or update `required_tools` in `config/project.json` |

## About

Built by [Clement DEUST](https://ai-architect.tools) as part of the **AI Architect** toolchain — a suite of AI-powered developer tools for product engineering.

The `/run-pipeline` command is free and open source. The [AI PRD Generator](https://ai-architect.tools) it depends on is a licensed product.
