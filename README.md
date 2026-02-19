# AI Architect Feedback Loop

A fully autonomous 10-stage product improvement pipeline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It analyzes code findings, generates PRDs, implements fixes, enforces quality gates, and delivers pull requests — all through a single `/run-pipeline` slash command with zero human intervention.

**Author:** Clement DEUST — [ai-architect.tools](https://ai-architect.tools)

## License

This pipeline command (`/run-pipeline`) is **free to use**.

The pipeline depends on the **AI PRD Generator** skill (`ai-prd-generator`) at Stage 4 to produce product requirement documents. The PRD Generator is a licensed product by Clement DEUST / [ai-architect.tools](https://ai-architect.tools) and **requires a valid license key** to operate.

You can obtain a license at [ai-architect.tools](https://ai-architect.tools). The key must be placed at:

```
~/.aiprd/license-key
```

The pipeline validates the license once at startup (Step 0.1) and reuses that validation for the entire run.

## Prerequisites

| Requirement | Notes |
|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | CLI must be installed and authenticated |
| Python 3.10+ | Used by validators and scoring scripts |
| `jq` | JSON processing in stage scripts |
| `gh` | GitHub CLI — for PR creation (Stage 10) |
| `git` | Repository operations |
| AI PRD Generator license | See [License](#license) above |

### Target project

The pipeline operates on a **target repository** (the product being improved). By default it expects the target as a sibling directory named via the `PIPELINE_BUILDER` environment variable. See [Configuration — Paths](#paths) for details.

```
parent/
  feedback-loop/    # this repo
  your-product/     # the target project
```

## Setup

### 1. Clone the repository

```bash
git clone <this-repo-url>
```

### 2. Install your license key

```bash
mkdir -p ~/.aiprd
echo "YOUR_LICENSE_KEY" > ~/.aiprd/license-key
```

### 3. Install the `/run-pipeline` command

The command is defined in `.claude/commands/run-pipeline.md` and is automatically available when you open Claude Code from within this project directory:

```bash
cd feedback-loop
claude
```

Type `/run-pipeline` in the Claude Code session to invoke it.

#### Using it in another project

To make the command available outside this repository, copy the command file into your target project:

```bash
mkdir -p /path/to/your-project/.claude/commands
cp .claude/commands/run-pipeline.md /path/to/your-project/.claude/commands/
```

Or install it as a personal command available across all projects:

```bash
mkdir -p ~/.claude/commands
cp .claude/commands/run-pipeline.md ~/.claude/commands/
```

### 4. Verify the setup

Run the health check to confirm all dependencies are in place:

```bash
make pipeline-health-check
```

## Usage

### Run the full pipeline

From a Claude Code session inside the project:

```
/run-pipeline
```

The pipeline executes 10 stages autonomously:

| Phase | Stages | Description |
|---|---|---|
| Discovery | 1 | Parse and prioritize Technical Veil findings |
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

```bash
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

## Pipeline stages

### Stage 1 — Parse findings
Reads Technical Veil output, normalizes findings into a ranked list scored by relevance and cross-engine impact.

### Stage 2 — Impact analysis
Computes a compound impact score across four dimensions: engines affected, propagation depth, contract impact, and test coverage delta. Findings must score above 0.3 and affect at least 2 engines to proceed.

### Stage 3 — Integration design
Designs architectural modifications respecting the port/adapter architecture. Validates that all referenced files exist and protocol changes are consistent.

### Stage 4 — PRD generation
Invokes the **AI PRD Generator** skill to produce four documents: `prd.md`, `prd-verification.md`, `prd-jira.md`, and `prd-tests.md`. Scope (simple/moderate/complex) is derived automatically from pipeline artifacts.

### Stage 5 — Implementation
Creates a feature branch, implements code changes following the PRD and integration plan, builds the project, and runs tests.

### Stage 6 — Quality gates
Runs deterministic checks: prohibited pattern detection, orphan file detection, and build verification.

### Stage 7 — Semantic verification
An independent verifier analyzes the git diff against the PRD. Checks alignment score (must be >= 0.7), cross-engine consistency, and anti-patterns.

### Stage 8 — Benchmark
Measures quality metrics and compares against baselines. Informational — does not block the pipeline.

### Stage 9 — Deployment simulation
Simulates deployment readiness: key injection verification, package resolution, and signing checks.

### Stage 10 — Pull request
Creates a pull request per finding with a structured description linking back to the impact analysis and PRD.

## Project structure

```
.
├── .claude/
│   └── commands/
│       └── run-pipeline.md        # The /run-pipeline slash command
├── config/
│   ├── thresholds.json            # Scoring thresholds for all stages
│   ├── category_engine_map.json   # Finding category to engine mapping
│   ├── engine_graph_overrides.json# Engine dependency graph
│   └── prohibited_patterns.txt    # Anti-pattern regex rules
├── prompts/                       # Stage prompt templates
│   ├── impact_analysis.md
│   ├── integration_design.md
│   ├── prd_generation.md
│   ├── implementation.md
│   └── semantic_verification.md
├── scripts/                       # Stage scripts, validators, processors
│   ├── pipeline.sh                # Main orchestrator
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

### Paths

The pipeline resolves paths dynamically at runtime. Override them with environment variables if your layout differs from the default:

| Variable | Default | Description |
|---|---|---|
| `PIPELINE_REPO` | Current working directory | Root of this feedback-loop repository |
| `PIPELINE_BUILDER` | `../` sibling directory | Root of the target product repository |

Example:

```bash
export PIPELINE_REPO="/path/to/feedback-loop"
export PIPELINE_BUILDER="/path/to/your-product"
```

### Thresholds and rules

Key configuration files in `config/`:

- **`thresholds.json`** — Scoring minimums, retry limits, and gate parameters for every stage.
- **`category_engine_map.json`** — Maps finding categories (retrieval, prompting, security, etc.) to affected engines and ports.
- **`engine_graph_overrides.json`** — Defines the engine dependency graph with roles, feeds, and fed-by relationships.
- **`prohibited_patterns.txt`** — Regex patterns rejected by Stage 6 (TODO, FIXME, HACK, stubs, etc.).

## Troubleshooting

| Issue | Fix |
|---|---|
| `[FAIL] License key not found` | Place your key at `~/.aiprd/license-key` |
| `[FAIL] License invalid` | Verify your key at [ai-architect.tools](https://ai-architect.tools) |
| Stage 4 fails with "skill not found" | Ensure the `ai-prd-generator` skill is installed |
| Build failures in Stage 5 | Confirm the target product repo is present and builds (`PIPELINE_BUILDER`) |
| `gh` errors in Stage 10 | Run `gh auth login` to authenticate the GitHub CLI |

## About

Built by [Clement DEUST](https://ai-architect.tools) as part of the **AI Architect** toolchain — a suite of AI-powered developer tools for product engineering.

The `/run-pipeline` command is free and open source. The [AI PRD Generator](https://ai-architect.tools) it depends on is a licensed product.
