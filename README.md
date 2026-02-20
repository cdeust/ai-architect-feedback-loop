# AI Architect Feedback Loop

A fully autonomous 10-stage product improvement pipeline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It analyzes code findings, generates PRDs, implements fixes, enforces quality gates, and delivers pull requests — all through a single `/run-pipeline` slash command with zero human intervention.

Works with **any tech stack** — Python, TypeScript, Go, Rust, Java, Kotlin, Swift, and more — through configuration alone.

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

## Quality enforcement

The pipeline enforces **64 hard output rules** across PRD generation, implementation, and verification. These rules are stack-agnostic and ensure every generated artifact meets production-quality standards expected by senior engineers, compliance officers, and security teams.

### Core PRD rules (1-17)

Rules enforced during Stage 4 PRD generation:

| Rule | What it enforces |
|---|---|
| 1. SP Arithmetic | Story points must add up across stories, epics, and totals |
| 2. No Self-Referencing Deps | No item depends on itself |
| 3. AC Numbering | Acceptance criteria numbered consistently across all files |
| 4. No Orphan DDL | Every CREATE TYPE must be referenced by a table |
| 5. No NOW() in Indexes | Volatile functions forbidden in partial index predicates |
| 6. No AnyCodable | Concrete types only — no type-erased wrappers |
| 7. No Placeholder Tests | Every test must have a real implementation body |
| 8. SP Not in FR Table | Story points belong in roadmap and JIRA only |
| 9. Uneven SP Distribution | Sprints must reflect real complexity differences |
| 10. Metrics Disclaimer | Verification metrics labeled as "projected" |
| 11. FR Traceability | Every requirement traces to a concrete source |
| 12. Clean Architecture | Technical spec must show module structure and real file paths |
| 13. Self-Check | Post-generation verification of all 64 rules |
| 14. Codebase Analysis | Must reference actual files from integration plan |
| 15. Honest Verdicts | 5-level taxonomy (STRONG_PASS / PASS / MARGINAL / WEAK / FAIL) |
| 16. Port Compliance | Code examples use injected interfaces, not framework globals |
| 17. Test Traceability | Every test in the matrix must exist with a real body |

### Architecture & code quality rules (18-24)

| Rule | What it enforces |
|---|---|
| 18. Generic Over Specific | Solutions must be parameterized and scalable, not single-purpose |
| 19. No Nested Types | Every struct/class/enum must be a top-level declaration |
| 20. Single Responsibility | Each class has one reason to change, max ~50 lines in examples |
| 21. Explicit Access Control | Visibility modifiers required, minimal public API surface |
| 22. Factory-Based Injection | Dependencies wired through factories/DI, not direct instantiation |
| 23. SOLID Compliance | Single responsibility, open/closed, and dependency inversion enforced |
| 24. Code Reusability | Shared utilities over duplication, consistent naming conventions |

### Security rules (25-32)

| Rule | What it enforces |
|---|---|
| 25. No Hardcoded Secrets | No credentials, API keys, or tokens in code — use env vars, vault, or secret managers |
| 26. Input Validation | Validate and sanitize every external input at system boundaries |
| 27. Injection Prevention | Parameterized queries only, output encoding for XSS, no string concatenation in queries |
| 28. Auth on Every Endpoint | Every operation specifies authentication method, roles, and permission checks |
| 29. Security-Safe Errors | Error responses never leak stack traces, internal paths, or DB schemas |
| 30. Cryptographic Standards | AES-256+ encryption, bcrypt/argon2 for passwords, no MD5/SHA-1/DES |
| 31. Rate Limiting | Throttling strategy for all public-facing endpoints |
| 32. Secure Communication | TLS requirements, certificate management, encrypted data in transit |

### Data protection & compliance rules (33-38)

| Rule | What it enforces |
|---|---|
| 33. Data Classification | Every data entity classified by sensitivity (public/internal/confidential/restricted) |
| 34. PII & Sensitive Data Protection | Encryption at rest, masking in non-prod, anonymization — at least 2 of 3 strategies |
| 35. No Sensitive Data in Logs | PII, credentials, and tokens never appear in log output, error responses, or URLs |
| 36. Data Minimization | Collect only what's necessary, justify each sensitive field with a clear purpose |
| 37. Audit Trail | Who/what/when logging for all security-sensitive operations |
| 38. Consent & Erasure | Data model supports consent tracking, deletion cascades, GDPR/CCPA compliance |

### Error handling & resilience rules (39-43)

| Rule | What it enforces |
|---|---|
| 39. Structured Error Handling | Domain-specific error types, no swallowed exceptions, explicit propagation strategy |
| 40. Resilience Patterns | Circuit breaker, retry with exponential backoff, timeout on every external call |
| 41. Graceful Degradation | Fallback behavior when dependencies fail, no cascading failures |
| 42. Transaction Boundaries | Scope, isolation level, rollback strategy for multi-step operations |
| 43. Consistent Error Format | Standardized error response structure (RFC 7807 or equivalent) |

### Concurrency & state management rules (44-46)

| Rule | What it enforces |
|---|---|
| 44. Concurrency Safety | Shared mutable state protected, thread safety guarantees, race condition prevention |
| 45. Immutability by Default | Prefer immutable data structures, mutable state explicitly justified |
| 46. Atomic Operations | Multi-step state changes must be atomic with defined isolation |

### Senior code quality rules (47-52)

| Rule | What it enforces |
|---|---|
| 47. No Magic Numbers | All literal values in code must be named constants |
| 48. Defensive Coding | Guard clauses, preconditions, null safety, fail fast on invalid state |
| 49. Method Size Limits | No function exceeds ~30 lines in code examples |
| 50. Consistent Naming | Established casing style, descriptive names, no abbreviations in public APIs |
| 51. API Contract Documentation | Every endpoint has typed request/response schemas, status codes, error responses |
| 52. Deprecation Strategy | Breaking changes specify migration path, sunset timeline, versioning approach |

### Comprehensive testing rules (53-58)

| Rule | What it enforces |
|---|---|
| 53. Mandatory Test Coverage | Every public method/endpoint has test specifications with coverage targets |
| 54. Security Testing | SAST/DAST, dependency vulnerability scanning, penetration test plan, OWASP test cases |
| 55. Performance Testing | Load test scenarios, stress thresholds, baseline comparisons, latency percentile targets |
| 56. No Production Data in Tests | All test data must be synthetic/anonymized — no real PII in test fixtures |
| 57. Edge Case & Negative Tests | Tests cover failure scenarios, boundary values, invalid inputs, concurrent operations |
| 58. Test Isolation | No shared mutable state between tests, proper setup/teardown, independent execution |

### Observability & monitoring rules (59-62)

| Rule | What it enforces |
|---|---|
| 59. Structured Logging | JSON format, log levels (DEBUG/INFO/WARN/ERROR), what to log at each level |
| 60. Distributed Tracing | Correlation IDs, trace context propagation across services |
| 61. No PII in Observability | Logs, metrics, and traces must not contain sensitive personal data |
| 62. Alerting Thresholds | Alert triggers, severity levels, escalation paths, on-call routing |

### Dependency & supply chain rules (63-64)

| Rule | What it enforces |
|---|---|
| 63. Dependency Vulnerability Scanning | SCA tooling (Snyk, Dependabot, Trivy) required in CI/CD pipeline |
| 64. Minimal Dependency Principle | New dependencies justified, prefer standard library, license compliance verified |

### Design principles in implementation

Stage 5 (Implementation) and Stage 7 (Verification) enforce scalable design:

- **Parameterize, don't hardcode** — caller-specific values belong in the caller, not in shared code
- **Centralize decisions** — one change should propagate everywhere, not require editing 500 files
- **Compose over specialize** — prefer composable building blocks over single-purpose parameters
- **Backward compatibility via defaults** — new parameters must default to existing behavior
- **Scalability test** — "If three more teams hit a similar problem, would this design handle their cases without changes?"

Stage 7 independently flags violations: hardcoded constants in shared code, single-purpose parameters, bug-specific naming, code duplication, and non-extensible shared components.

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
Designs architectural modifications respecting the target product's architecture. Enforces [design principles](#design-principles-in-implementation): parameterization, centralization, composability, backward compatibility. Validates that all referenced files exist and interface changes are consistent.

### Stage 4 — PRD generation
Invokes the **AI PRD Generator** skill to produce four documents: `prd.md`, `prd-verification.md`, `prd-jira.md`, and `prd-tests.md`. Enforces all [64 hard output rules](#quality-enforcement). Scope (simple/moderate/complex) is derived automatically from pipeline artifacts.

### Stage 5 — Implementation
Creates a feature branch, implements code changes following the PRD and integration plan, builds the project, and runs tests. Enforces [code quality rules](#architecture--code-quality-rules-18-24), [security rules](#security-rules-25-32), [resilience rules](#error-handling--resilience-rules-39-43), and [testing rules](#comprehensive-testing-rules-53-58).

### Stage 6 — Quality gates
Runs deterministic checks: prohibited pattern detection, orphan file detection, build verification, test suite, and deployment verification.

### Stage 7 — Semantic verification
An independent verifier analyzes the git diff against the PRD. Checks alignment score (must be >= 0.7), cross-module consistency, anti-patterns, and [solution genericity](#design-principles-in-implementation) — flags hardcoded constants, single-purpose parameters, and non-extensible designs.

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
│   ├── integration_design.md      # Includes design principles (parameterization, genericity)
│   ├── prd_generation.md          # Enforces 64 hard output rules
│   ├── implementation.md          # Solution design quality requirements
│   └── semantic_verification.md   # Genericity & scalability verification
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

Each prompt template enforces quality standards:
- **Integration design** — Design principles: parameterize, extend abstractions, compose, think one level up, backward compatibility via defaults
- **PRD generation** — 64 hard output rules: SP arithmetic, clean architecture, SOLID compliance, security hardening, data protection, resilience patterns, concurrency safety, observability, and more
- **Implementation** — Solution design quality: no magic constants, general mechanisms, reusable utilities, generic naming
- **Semantic verification** — Adversarial review: solution genericity, scalability, cross-module integration, anti-pattern detection

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
