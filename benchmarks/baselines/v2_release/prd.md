# PRD: AI-Architect Pipeline Feedback

**Document Type:** Full Scope Overview (All Epics)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Repository:** ai-architect-pipeline-feedback
**Ecosystem:** ai-architect (alongside ai-prd-generator, technical-veil)
**License Tier:** Licensed (Full verification engine + all 15 strategies)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Goals & Success Metrics](#2-goals--success-metrics)
3. [Requirements](#3-requirements)
4. [Epic Breakdown & T-Shirt Sizing](#4-epic-breakdown--t-shirt-sizing)
5. [Epic Dependencies & Sequencing](#5-epic-dependencies--sequencing)
6. [High-Level Architecture](#6-high-level-architecture)
7. [Risks & Open Questions](#7-risks--open-questions)

---

## 1. Overview

### 1.1 Problem

The ai-architect ecosystem has three systems that operate independently:

| System | Function | Current State |
|--------|----------|---------------|
| **Technical Veil** | Daily AI landscape monitoring (30 companies, papers, APIs, benchmarks) | Operational, produces scored findings (needs output adapter) |
| **AI-PRD Generator** | 9-engine verified PRD generation with Ed25519 licensing | Production, 38/38 encryption tests passing, marketplace-ready |
| **Human judgment** | Decides what to improve, when, and how | Manual, rate-limited by available hours |

The bottleneck: Technical Veil surfaces relevant findings daily, but converting a finding into an integrated product improvement requires manual analysis, specification, implementation, testing, and deployment. The product improves at human pace, not at field pace.

Worse, manual improvements tend to be shallow — affecting one engine without evaluating compound impact across the full 9-engine dependency graph. This leads to bolt-on features that fragment the system instead of integrated improvements that strengthen it.

### 1.2 Solution

A 10-stage automated pipeline that connects Technical Veil intelligence directly to AI-PRD Generator improvements, enforced by deterministic gates that no AI model can bypass:

1. **Trigger** — Parse Technical Veil output, filter by AI-PRD relevance
2. **Cross-Engine Impact Analysis** — Map findings to the 9-engine dependency graph, score compound impact
3. **Integration Design** — Design how improvements fit inside existing engines (reject bolt-ons)
4. **PRD Generation (Dogfood)** — Use AI-PRD Generator to spec its own upgrade
5. **Implementation** — Claude Code CLI session follows the PRD spec
6. **Deterministic Enforcement** — 6 hard gates: prohibited patterns, manifest compliance, dead code, compilation, tests, encryption
7. **Semantic Verification** — Independent Claude Code session verifies PRD-to-code alignment
8. **Quality Gate** — Multi-dimensional benchmark comparison (old vs new output)
9. **Deployment Simulation** — Full `make distribute` pipeline integrity check
10. **Pull Request** — Auto-create PR with full audit trail, then `make sync-public`

**Zero marginal cost**: Claude Code CLI (Max subscription), local Mac hardware, existing Makefile pipeline. No API costs, no cloud infrastructure.

### 1.3 Key Constraints

| Constraint | Enforcement |
|------------|-------------|
| Improvements must affect 2+ engines | Stage 2 rejection gate (compound score threshold) |
| No standalone modules or bolt-on features | Stage 3 integration validation |
| No TODO, FIXME, placeholder, dead code | Stage 6 Gate 1 (prohibited patterns) |
| Implementation and verification are separate sessions | Stage 5 vs Stage 7 (independent Claude Code sessions) |
| Pipeline integrates with existing Makefile | Uses `make distribute`, `make test-all`, `make sync-public` |
| Private repo is source of truth | Pipeline targets ai-architect-prd-builder, Stage 10 runs sync-public |
| CLI-only, no API fallback | Strict zero-cost operation |
| Batch processing | All passing findings in a single run, potentially multiple PRs |

### 1.4 Non-Goals

- Replacing human PR review (pipeline produces PR, human approves)
- Modifying Technical Veil's monitoring scope or schedule
- Supporting non-macOS platforms (xcFramework pipeline is Mac-only)
- Real-time processing (nightly batch is sufficient)

---

## 2. Goals & Success Metrics

### 2.1 Business Goals

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| BG-001 | Reduce finding-to-improvement cycle time | ~1-2 weeks (manual analysis → implementation → testing → deployment) | < 2 hours (automated end-to-end) | Pipeline run duration from trigger to PR creation |
| BG-002 | Increase product improvement frequency | ~1-2 improvements/month (human-paced) | Daily improvement candidates (field-paced) | PRs created per week |
| BG-003 | Improve integration quality of changes | Single-engine changes (~60% of improvements) | 100% multi-engine integrated changes | Stage 2 compound analysis: engines_affected >= 2 for all accepted findings |
| BG-004 | Eliminate manual specification overhead | 4-8 hours per improvement spec (manual PRD writing) | 0 hours (dogfood PRD generation) | Human time spent on specs post-pipeline |
| BG-005 | Maintain zero-regression quality | N/A (new capability) | 0% quality regression across benchmarks | Stage 8 multi-dimensional scoring: no benchmark drops |

### 2.2 Technical Goals

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| TG-001 | Pipeline completion rate | N/A (new system) | > 80% (runs that produce PR or clean "no findings") | Completed runs / total runs |
| TG-002 | False positive rate | N/A | < 20% (PRs rejected by human reviewer) | Rejected PRs / total PRs over 30-day rolling window |
| TG-003 | Deterministic gate reliability | N/A | 100% (gates never produce false negatives) | Gate bypass incidents = 0 |
| TG-004 | Build pipeline integrity | 38/38 encryption tests passing | 38/38 maintained after every improvement | `make distribute` pass rate |
| TG-005 | Benchmark suite coverage | N/A (no benchmarks exist yet) | 6+ benchmark inputs covering all PRD types | Benchmark count in benchmarks/inputs/ |

### 2.3 Key Performance Indicators

| KPI | How Measured | Reporting |
|-----|-------------|-----------|
| Findings processed per day | Count of findings passing Stage 1 filter | Morning summary (macOS notification) |
| Compound impact score distribution | Histogram of Stage 2 compound_score values | Weekly aggregate |
| Gate failure rate by gate type | Stage 6 gate-level pass/fail counts | Per-run enforcement report |
| Quality delta per benchmark | Stage 8 old vs new scores per benchmark input | Per-PR quality comparison |
| End-to-end pipeline duration | Timestamp diff: Stage 1 start → Stage 10 PR creation | Per-run log |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement |
|----|----------|-------------|
| FR-001 | P0 | Pipeline parses Technical Veil JSON output and filters findings by AI-PRD relevance categories (prompting, retrieval, verification, embeddings, inference, cost_optimization, benchmarks) |
| FR-002 | P0 | Technical Veil output adapter transforms raw findings into pipeline-compatible `findings.json` format with relevance scores |
| FR-003 | P0 | Cross-engine impact analysis maps each finding to the 9-engine dependency graph and traces first/second-order propagation paths |
| FR-004 | P0 | Findings affecting fewer than 2 engines are rejected with an explanation of why deeper analysis failed to find cross-engine impact |
| FR-005 | P0 | Integration design produces a plan specifying which existing files change, which contracts modify, and how changes propagate through the engine graph |
| FR-006 | P0 | Integration plans that create new standalone modules or files (non-test) are rejected |
| FR-007 | P0 | Pipeline uses the AI-PRD Generator (SKILL.md and/or Swift library) to generate an upgrade PRD for each accepted finding |
| FR-008 | P0 | Implementation runs as a Claude Code CLI session with structured context (PRD, integration plan, manifest) |
| FR-009 | P0 | Deterministic enforcement gates run as shell scripts with zero AI involvement: prohibited patterns, manifest compliance, dead code, compilation, test suite, encryption integrity |
| FR-010 | P0 | Semantic verification runs as an independent Claude Code CLI session (separate from implementation session) |
| FR-011 | P0 | Quality gate compares benchmark outputs using multi-dimensional scoring: verification score, section completeness, consistency, requirement coverage |
| FR-012 | P0 | Deployment simulation runs `make distribute` (build + encrypt + test all 38 validation tests) |
| FR-013 | P0 | Pipeline auto-creates GitHub PR with audit trail: impact report, integration plan, PRD, enforcement report, quality comparison |
| FR-014 | P1 | Stage 10 runs `make sync-public` to push validated changes to ai-prd-generator |
| FR-015 | P1 | Retry logic: Stage 5→6→7 loop with max 3 retries, appending failure details to subsequent attempt prompts |
| FR-016 | P1 | After all retries exhausted, pipeline auto-creates a GitHub issue with failure details for manual investigation |
| FR-017 | P1 | Engine dependency graph is auto-generated from Package.swift files with manual semantic override support |
| FR-018 | P1 | Benchmarks test both SKILL.md prompt flow and Swift library direct invocation |
| FR-019 | P1 | Batch processing: all findings passing Stage 2 are processed in a single run |
| FR-020 | P2 | Morning summary delivered via macOS notification with pipeline results |
| FR-021 | P2 | Pipeline run history stored in timestamped directories under `runs/` |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-001 | P0 | End-to-end pipeline duration per finding | < 90 minutes |
| NFR-002 | P0 | Marginal cost per pipeline run | $0 (Claude Code Max + local compute) |
| NFR-003 | P0 | Deterministic gate false negative rate | 0% (gates never pass code that violates constraints) |
| NFR-004 | P0 | Build pipeline integrity after improvement | 38/38 encryption tests passing |
| NFR-005 | P1 | Pipeline must not modify files outside the ai-architect-prd-builder working tree during Stages 1-9 | Sandboxed execution |
| NFR-006 | P1 | All pipeline scripts must be POSIX-compatible bash (macOS default shell) | No zsh-specific features |
| NFR-007 | P1 | Pipeline artifacts (runs/, logs/) must not be committed to git | .gitignore enforcement |
| NFR-008 | P2 | Benchmark suite execution time (all inputs, both paths) | < 30 minutes |

---

## 4. Epic Breakdown & T-Shirt Sizing

### Epic 1: Deterministic Foundation (Stages 1, 6, 8, 9)

**Size: L (5-8 weeks)**

The foundation everything else depends on. Shell scripts, Makefile targets, benchmark harness — no AI involvement. These gates must be rock-solid before any intelligence layer is built on top.

| Component | What It Does | Integration Point |
|-----------|-------------|-------------------|
| **Stage 1: Trigger & Parse** | Shell script that watches for Technical Veil output, filters by relevance, produces `findings.json` | Reads from Technical Veil output directory, writes to `runs/<timestamp>/` |
| **Technical Veil Adapter** | Python script that transforms raw TV output into pipeline-compatible JSON schema | Bridges Technical Veil's existing format to pipeline's expected `findings.json` |
| **Stage 6: Enforcement Gates** | 6 deterministic gates in a single shell script: prohibited patterns, manifest compliance, dead code detection, `make build-library`, `make test-all`, `make distribute` | Wraps existing Makefile targets; adds manifest-based file constraint checking |
| **Stage 8: Quality Gate** | Benchmark runner that executes PRD generation on fixed inputs, compares multi-dimensional scores (old vs new) | Integrates with SKILL.md prompt flow AND direct Swift library invocation |
| **Stage 9: Deployment Simulation** | Runs `make distribute` (build 9 xcFrameworks + encrypt + 38 validation tests) | Direct integration with existing Makefile `distribute` target |
| **Benchmark Suite** | 6+ curated PRD inputs covering all PRD types (feature, bug, mvp, etc.) with baseline outputs | Stored in `benchmarks/inputs/` with golden baselines in `benchmarks/baselines/` |
| **Engine Graph Generator** | Script that parses `Package.swift` files to auto-generate `engine_graph.json` with manual override support | Reads from `packages/*/Package.swift`, produces config in `config/engine_graph.json` |

**Key deliverables:**
- `scripts/pipeline/stage_1_trigger.sh`
- `scripts/pipeline/stage_6_enforcement.sh`
- `scripts/pipeline/stage_8_quality_gate.sh`
- `scripts/pipeline/stage_9_deployment.sh`
- `scripts/pipeline/generate_engine_graph.py`
- `scripts/pipeline/parse_findings.py` (Technical Veil adapter)
- `config/engine_graph.json` (auto-generated + overrides)
- `config/prohibited_patterns.txt`
- `config/thresholds.json`
- `benchmarks/inputs/*.json` (6+ benchmark inputs)
- `benchmarks/baselines/` (golden outputs for comparison)

**Risks:**
- Benchmark golden baselines need to be established manually before automation can detect regressions
- Prohibited patterns list may need tuning to avoid false positives on legitimate code

---

### Epic 2: Intelligence Layer (Stages 2, 3)

**Size: L (5-8 weeks)**

The brain of the pipeline. Claude Code CLI sessions analyze findings for cross-engine compound impact and design integration plans. This is where bolt-on features get rejected.

| Component | What It Does | Integration Point |
|-----------|-------------|-------------------|
| **Stage 2: Cross-Engine Impact Analysis** | Claude Code CLI session that maps findings to engine dependency graph, traces propagation paths, scores compound impact | Reads `findings.json` + `engine_graph.json` + engine source code; produces `impact_report.json` |
| **Stage 2 Validator** | Shell script that enforces engines_affected >= 2 and compound_score >= 0.3 thresholds | Deterministic post-processing of Claude Code output |
| **Stage 3: Integration Design** | Claude Code CLI session that designs how improvements fit inside existing engines: which files change, which contracts modify, cross-engine touchpoints | Reads `impact_report.json` + engine source code; produces `integration_plan.json` |
| **Stage 3 Validator** | Shell script that rejects plans with new non-test source files, missing touchpoints, or zero cross-engine connections | Deterministic validation against file system state |
| **Manifest Generator** | Python script that converts `integration_plan.json` into hard enforcement `manifest.json` for Stage 6 | Bridge between intelligence layer and deterministic gates |
| **Claude Code Prompt Templates** | Structured prompts for Stages 2 and 3 with engine graph context, contract definitions, and rejection rules | Stored in `prompts/impact_analysis.md` and `prompts/integration_design.md` |

**Key deliverables:**
- `prompts/impact_analysis.md`
- `prompts/integration_design.md`
- `scripts/pipeline/stage_2_impact_analysis.sh` (orchestrates Claude Code CLI)
- `scripts/pipeline/stage_3_integration_design.sh`
- `scripts/pipeline/validate_impact_report.sh`
- `scripts/pipeline/validate_integration_plan.sh`
- `scripts/pipeline/generate_manifest.py`

**Risks:**
- Claude Code CLI session quality depends on prompt engineering — prompts need iterative refinement
- Engine contract definitions must be extracted programmatically from source for accurate analysis
- Compound scoring formula needs calibration against manual improvement decisions

---

### Epic 3: Dogfood & Implementation (Stages 4, 5)

**Size: M (3-4 weeks)**

The self-improving loop. The AI-PRD Generator writes its own upgrade PRD, then a Claude Code CLI session implements it. This is where the product improves itself.

| Component | What It Does | Integration Point |
|-----------|-------------|-------------------|
| **Stage 4: PRD Generation (Dogfood)** | Composes input from finding + integration plan, runs AI-PRD Generator against it | Invokes SKILL.md via Claude Code CLI AND Swift library; validates output quality score >= 80% |
| **PRD Input Composer** | Python script that assembles finding description + integration plan + engine contracts into a coherent PRD input document | Reads `impact_report.json` + `integration_plan.json` + engine contract sources |
| **Stage 5: Implementation** | Claude Code CLI session that implements the upgrade from PRD spec on a feature branch | Reads upgrade PRD + integration plan + manifest + CLAUDE.md; produces git branch with code changes |
| **Implementation Prompt Template** | Structured prompt with PRD as primary input, integration plan as constraints, manifest as hard limits | Stored in `prompts/implementation.md` |

**Key deliverables:**
- `scripts/pipeline/stage_4_dogfood.sh`
- `scripts/pipeline/stage_5_implementation.sh`
- `scripts/pipeline/compose_prd_input.py`
- `prompts/implementation.md`

**Risks:**
- PRD quality from dogfood step may be lower for self-referential improvements (the tool speccing changes to itself)
- Implementation session may struggle with complex cross-engine refactors that touch many files

---

### Epic 4: Verification & Delivery (Stages 7, 10, Retry Logic)

**Size: M (3-4 weeks)**

Independent verification and PR creation. The verification agent is intentionally separate from the implementation agent to prevent self-confirming bias.

| Component | What It Does | Integration Point |
|-----------|-------------|-------------------|
| **Stage 7: Semantic Verification** | Independent Claude Code CLI session that checks PRD-to-code alignment, cross-engine integration, and anti-pattern detection | Reads upgrade PRD + git diff + integration plan; produces `verification_result.json` |
| **Verification Prompt Template** | Structured prompt focused on finding misalignment, not confirming correctness | Stored in `prompts/semantic_verification.md` |
| **Stage 10: Pull Request** | Creates GitHub PR via `gh` CLI with full audit trail attachments | Uses `gh pr create`, attaches all stage outputs as PR description |
| **PR Description Composer** | Python script that assembles all stage outputs into a structured PR description | Reads impact report, integration plan, PRD, enforcement report, quality results |
| **Retry Orchestrator** | Shell script that manages Stage 5→6→7 retry loop with max 3 attempts, appending failure context | Coordinates between Stages 5, 6, 7; tracks attempt count |
| **Failure Issue Creator** | Script that auto-creates GitHub issue with failure details after all retries exhausted | Uses `gh issue create` with structured failure report |
| **Auto-Sync** | Runs `make sync-public` after successful PR creation | Direct integration with existing Makefile target |

**Key deliverables:**
- `scripts/pipeline/stage_7_semantic_verification.sh`
- `scripts/pipeline/stage_10_pull_request.sh`
- `scripts/pipeline/retry_orchestrator.sh`
- `scripts/pipeline/compose_pr.py`
- `prompts/semantic_verification.md`

**Risks:**
- Verification agent may be too lenient or too strict — needs calibration
- Retry loop could thrash if failures are systemic rather than fixable

---

### Epic 5: Operational Maturity (Scheduling, Monitoring, Hardening)

**Size: M (3-4 weeks)**

Pipeline runs nightly, self-heals on failure, reports results in the morning. This is the "set it and forget it" phase.

| Component | What It Does | Integration Point |
|-----------|-------------|-------------------|
| **Pipeline Orchestrator** | Main `pipeline.sh` script that sequences all 10 stages with error handling | Entry point for cron/launchd; coordinates all stage scripts |
| **Scheduler** | launchd plist (macOS) or cron job that triggers pipeline after Technical Veil completes | Watches for Technical Veil output file or runs on fixed schedule |
| **macOS Notifications** | Morning summary via `osascript` notification with pipeline results | Triggered after pipeline completion or on cron morning schedule |
| **Run History** | Timestamped directories under `runs/` with all stage artifacts | File-based storage, no database |
| **Log Aggregation** | Structured logging across all stages with searchable format | Writes to `logs/pipeline.log` with structured JSON entries |
| **Benchmark Maintenance** | Process for updating golden baselines when improvements are accepted | Manual trigger after PR merge |
| **Health Checks** | Pre-flight validation that all dependencies are available (Claude Code CLI, gh, make, swift) | Runs at pipeline start before any stage |

**Key deliverables:**
- `pipeline.sh` (main orchestrator)
- `com.ai-architect.pipeline-feedback.plist` (launchd scheduler)
- `scripts/pipeline/notify.sh` (macOS notifications)
- `scripts/pipeline/health_check.sh`
- `scripts/pipeline/update_baselines.sh`

**Risks:**
- launchd scheduling on macOS requires the machine to be awake — no cloud backup
- Long-running pipeline may conflict with other heavy processes on the same machine

---

## 5. Epic Dependencies & Sequencing

### 5.1 Dependency Graph

```
Epic 1: Deterministic Foundation
    │
    ├──▶ Epic 2: Intelligence Layer (needs engine graph + enforcement gates)
    │       │
    │       └──▶ Epic 3: Dogfood & Implementation (needs impact analysis + integration design)
    │               │
    │               └──▶ Epic 4: Verification & Delivery (needs implementation output to verify)
    │
    └──▶ Epic 5: Operational Maturity (needs all stages working to orchestrate)
            ▲
            │
            Epic 4 ──┘ (needs delivery pipeline complete before scheduling)
```

### 5.2 Sequencing & Milestones

| Phase | Epic | Duration | Milestone |
|-------|------|----------|-----------|
| **Phase 1** | Epic 1: Deterministic Foundation | 5-8 weeks | All deterministic gates operational; benchmark suite established; engine graph auto-generated |
| **Phase 2** | Epic 2: Intelligence Layer | 5-8 weeks | Claude Code CLI sessions produce impact reports and integration plans; bolt-on rejection working |
| **Phase 3** | Epic 3: Dogfood & Implementation | 3-4 weeks | Product generates its own upgrade PRDs; implementation sessions produce compilable code |
| **Phase 4** | Epic 4: Verification & Delivery | 3-4 weeks | End-to-end pipeline produces PRs with full audit trail; retry logic handles failures |
| **Phase 5** | Epic 5: Operational Maturity | 3-4 weeks | Pipeline runs nightly unattended; morning notifications; run history and logs |

**Total estimated duration: 19-28 weeks** (one developer, sequential execution)

**Parallelization opportunities:**
- Epic 2 prompt engineering can begin during Epic 1 development (prompts don't depend on gates running)
- Benchmark input curation (Epic 1) can happen in parallel with adapter development (Epic 1)
- Epic 5 health checks and logging can be developed alongside Epic 4

### 5.3 Critical Path

```
Engine Graph Generator → Stage 2 (needs graph) → Stage 3 (needs impact report) →
Stage 4 (needs integration plan) → Stage 5 (needs PRD) → Stage 6 (needs code) →
Stage 7 (needs code + PRD) → Stage 8 (needs passing code) → Stage 9 (needs passing code) →
Stage 10 (needs all stages passed)
```

The engine graph generator is the single most critical dependency — every intelligence layer stage depends on it. Build it first.

### 5.4 Integration with Existing Product

The pipeline does not add new capabilities to the AI-PRD Generator's user-facing features. Instead, it automates the improvement process that currently happens manually:

| Current Manual Process | Pipeline Equivalent | Integration |
|------------------------|---------------------|-------------|
| Read Technical Veil findings | Stage 1: parse_findings.py | New adapter script |
| Decide which engines are affected | Stage 2: Claude Code impact analysis | New prompt + validator |
| Design the improvement | Stage 3: Claude Code integration design | New prompt + validator |
| Write upgrade spec | Stage 4: AI-PRD Generator dogfood | Uses existing SKILL.md + library |
| Implement the change | Stage 5: Claude Code CLI session | Uses existing CLAUDE.md |
| Run tests + build | Stage 6: `make test-all` + `make build-library` | Wraps existing Makefile targets |
| Test encryption pipeline | Stage 9: `make distribute` | Wraps existing Makefile target |
| Create PR | Stage 10: `gh pr create` | New PR composition script |
| Sync public repo | Stage 10: `make sync-public` | Wraps existing Makefile target |

**New Makefile targets added:**

```makefile
.PHONY: pipeline
pipeline: ## Run full feedback pipeline (trigger → PR)
	@scripts/pipeline/pipeline.sh

.PHONY: pipeline-gates
pipeline-gates: ## Run deterministic gates only (for testing)
	@scripts/pipeline/stage_6_enforcement.sh

.PHONY: pipeline-benchmark
pipeline-benchmark: ## Run quality benchmarks (for baseline comparison)
	@scripts/pipeline/stage_8_quality_gate.sh

.PHONY: pipeline-health
pipeline-health: ## Check pipeline dependencies
	@scripts/pipeline/health_check.sh

.PHONY: update-engine-graph
update-engine-graph: ## Regenerate engine dependency graph from Package.swift files
	@scripts/pipeline/generate_engine_graph.py

.PHONY: update-baselines
update-baselines: ## Update benchmark baselines after accepted improvement
	@scripts/pipeline/update_baselines.sh
```

---

## 6. High-Level Architecture

### 6.1 System Context

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         AI-ARCHITECT ECOSYSTEM                            │
│                                                                           │
│  ┌──────────────┐     ┌───────────────────────┐     ┌──────────────────┐ │
│  │  Technical    │────▶│  Pipeline Feedback     │────▶│  AI-PRD          │ │
│  │  Veil         │     │  (this system)         │     │  Generator       │ │
│  │              │     │                         │     │  (9 engines)     │ │
│  │  Findings    │     │  10 stages              │     │  Private repo    │ │
│  │  (JSON)      │     │  4 Claude Code sessions │     │                  │ │
│  └──────────────┘     │  6 deterministic gates  │     └────────┬─────────┘ │
│                        └───────────┬─────────────┘              │          │
│                                    │                             │          │
│                                    │  dogfood (Stage 4)         │          │
│                                    │◀────────────────────────────┘          │
│                                    │                                       │
│                                    │  make sync-public (Stage 10)          │
│                                    ▼                                       │
│                        ┌───────────────────────┐                          │
│                        │  ai-prd-generator      │                          │
│                        │  (public repo)         │                          │
│                        │  Encrypted xcFrameworks│                          │
│                        └───────────────────────┘                          │
└───────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Pipeline Data Flow

```
Technical Veil Output
       │
       ▼
findings.json ──▶ Stage 1 (shell) ──▶ filtered findings
                                            │
                                            ▼
engine_graph.json ──▶ Stage 2 (Claude Code #1) ──▶ impact_report.json
                                                          │
                                                          ▼
engine source ──▶ Stage 3 (Claude Code #2) ──▶ integration_plan.json
                                                       │
                                                       ├──▶ manifest.json (deterministic)
                                                       │
                                                       ▼
                  Stage 4 (AI-PRD Generator) ──▶ upgrade_prd.md
                                                       │
                                              ┌────────┤
                                              │        ▼
                                              │  Stage 5 (Claude Code #3) ──▶ git branch
                                              │        │
                                              │        ▼
                                              │  Stage 6 (shell) ──▶ pass/fail
                                              │        │     │
                                              │        │     └──▶ retry (max 3)
                                              │        ▼
                                              │  Stage 7 (Claude Code #4) ──▶ pass/fail
                                              │        │     │
                                              │        │     └──▶ retry (max 2 cycles)
                                              │        ▼
                                              │  Stage 8 (shell) ──▶ pass/reject
                                              │        │
                                              │        ▼
                                              │  Stage 9 (shell) ──▶ pass/reject
                                              │        │
                                              │        ▼
                                              │  Stage 10 (git + gh) ──▶ Pull Request
                                              │        │
                                              │        ▼
                                              │  make sync-public ──▶ Public repo updated
                                              │
                                              └──▶ (PRD used for verification in Stage 7)
```

### 6.3 File Structure

```
ai-architect-pipeline-feedback/          # Can live inside ai-architect-prd-builder
├── pipeline.sh                          # Main orchestrator (Epic 5)
├── config/
│   ├── engine_graph.json                # Auto-generated + manual overrides (Epic 1)
│   ├── engine_graph_overrides.json      # Manual semantic relationships
│   ├── thresholds.json                  # Scoring thresholds for all stages
│   └── prohibited_patterns.txt          # Stage 6 Gate 1 patterns
├── scripts/
│   └── pipeline/
│       ├── stage_1_trigger.sh           # Parse + filter (Epic 1)
│       ├── stage_2_impact_analysis.sh   # Claude Code CLI orchestrator (Epic 2)
│       ├── stage_3_integration_design.sh# Claude Code CLI orchestrator (Epic 2)
│       ├── stage_4_dogfood.sh           # PRD generation (Epic 3)
│       ├── stage_5_implementation.sh    # Claude Code CLI orchestrator (Epic 3)
│       ├── stage_6_enforcement.sh       # 6 deterministic gates (Epic 1)
│       ├── stage_7_semantic_verification.sh # Claude Code CLI orchestrator (Epic 4)
│       ├── stage_8_quality_gate.sh      # Benchmark comparison (Epic 1)
│       ├── stage_9_deployment.sh        # make distribute wrapper (Epic 1)
│       ├── stage_10_pull_request.sh     # PR creation (Epic 4)
│       ├── retry_orchestrator.sh        # Stage 5→6→7 loop (Epic 4)
│       ├── parse_findings.py            # Technical Veil adapter (Epic 1)
│       ├── generate_engine_graph.py     # Package.swift parser (Epic 1)
│       ├── generate_manifest.py         # Integration plan → manifest (Epic 2)
│       ├── compose_prd_input.py         # Finding → PRD input (Epic 3)
│       ├── compose_pr.py               # Stage outputs → PR description (Epic 4)
│       ├── notify.sh                    # macOS notifications (Epic 5)
│       ├── health_check.sh              # Pre-flight validation (Epic 5)
│       └── update_baselines.sh          # Post-merge baseline update (Epic 5)
├── prompts/
│   ├── impact_analysis.md               # Stage 2 Claude Code prompt (Epic 2)
│   ├── integration_design.md            # Stage 3 Claude Code prompt (Epic 2)
│   ├── implementation.md                # Stage 5 Claude Code prompt (Epic 3)
│   └── semantic_verification.md         # Stage 7 Claude Code prompt (Epic 4)
├── benchmarks/
│   ├── inputs/                          # Fixed benchmark inputs (Epic 1)
│   │   ├── simple_feature.json
│   │   ├── complex_multiepic.json
│   │   ├── ambiguous_requirements.json
│   │   ├── contradictory_specs.json
│   │   ├── compliance_heavy.json
│   │   └── mockup_driven.json
│   └── baselines/                       # Last known good outputs (Epic 1)
├── runs/                                # Timestamped run directories (gitignored)
│   └── 20260211_220000/
│       ├── findings.json
│       ├── impact_report.json
│       ├── integration_plan.json
│       ├── manifest.json
│       ├── prd_output/
│       ├── enforcement_report.txt
│       ├── verification_result.json
│       ├── quality_results/
│       └── pr_description.md
├── logs/                                # Pipeline logs (gitignored)
│   └── pipeline.log
└── com.ai-architect.pipeline-feedback.plist  # launchd scheduler (Epic 5)
```

### 6.4 Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Pipeline orchestration | Bash shell scripts | Zero dependencies, POSIX-compatible, integrates with existing Makefile |
| Technical Veil adapter | Python 3 (system) | JSON parsing, filtering — macOS ships with Python 3 |
| Engine graph generator | Python 3 | Package.swift parsing, graph construction |
| Manifest/PR generators | Python 3 | JSON transformation, markdown composition |
| Claude Code sessions | `claude` CLI (Max subscription) | Stages 2, 3, 5, 7 — zero API cost |
| Deterministic gates | Bash + existing Makefile targets | `make build-library`, `make test-all`, `make distribute` |
| PR creation | `gh` CLI (GitHub CLI) | Already used in the project |
| Scheduling | launchd (macOS native) | Reliable, survives reboots, native integration |
| Notifications | `osascript` (AppleScript) | macOS native, no external dependencies |
| Build/test/encrypt | Swift toolchain + Xcode | Existing project infrastructure |

### 6.5 Engine Dependency Graph (Machine-Readable)

The graph is auto-generated from `Package.swift` dependency declarations with manual overrides for semantic relationships (data flow, contract dependencies):

```json
{
  "engine_graph": {
    "VisionEngine": {
      "feeds": ["RAGEngine"],
      "fed_by": [],
      "role": "input_processing",
      "package": "packages/AIPRDVisionEngine"
    },
    "VisionEngineApple": {
      "feeds": ["RAGEngine"],
      "fed_by": [],
      "role": "on_device_input_processing",
      "package": "packages/AIPRDVisionEngineApple"
    },
    "RAGEngine": {
      "feeds": ["VerificationEngine", "MetaPromptingEngine", "StrategyEngine"],
      "fed_by": ["VisionEngine", "VisionEngineApple"],
      "role": "retrieval",
      "package": "packages/AIPRDRAGEngine"
    },
    "VerificationEngine": {
      "feeds": ["OrchestrationEngine", "StrategyEngine"],
      "fed_by": ["RAGEngine"],
      "role": "quality_assurance",
      "package": "packages/AIPRDVerificationEngine"
    },
    "MetaPromptingEngine": {
      "feeds": ["OrchestrationEngine"],
      "fed_by": ["RAGEngine"],
      "role": "context_optimization",
      "package": "packages/AIPRDMetaPromptingEngine"
    },
    "StrategyEngine": {
      "feeds": ["OrchestrationEngine"],
      "fed_by": ["RAGEngine", "VerificationEngine"],
      "role": "strategy_selection",
      "package": "packages/AIPRDStrategyEngine"
    },
    "OrchestrationEngine": {
      "feeds": ["EncryptionEngine"],
      "fed_by": ["VerificationEngine", "MetaPromptingEngine", "StrategyEngine"],
      "role": "coordination",
      "package": "packages/AIPRDOrchestrationEngine"
    },
    "SharedUtilities": {
      "feeds": ["ALL"],
      "fed_by": [],
      "role": "common_infrastructure",
      "package": "packages/AIPRDSharedUtilities"
    },
    "EncryptionEngine": {
      "feeds": [],
      "fed_by": ["OrchestrationEngine"],
      "role": "security_wrapper",
      "package": "packages/AIPRDEncryptionEngine"
    }
  }
}
```

---

## 7. Risks & Open Questions

### 7.1 Technical Risks

| ID | Risk | Severity | Probability | Impact | Mitigation |
|----|------|----------|-------------|--------|------------|
| R-001 | Claude Code CLI session produces low-quality impact analysis or integration designs | HIGH | 30% | Pipeline produces bad PRs that waste reviewer time | Iterative prompt engineering in Epic 2; deterministic gates in Stage 6 catch structural violations; quality gate in Stage 8 catches output regression |
| R-002 | Dogfood loop (product speccing its own improvements) produces self-referential or circular PRDs | MEDIUM | 20% | Upgrade PRDs lack specificity, implementation sessions flounder | Stage 4 quality threshold (>= 80% verification score); human review is final gate |
| R-003 | Benchmark golden baselines become stale as product evolves | MEDIUM | 60% | Quality gate produces false regressions or misses real regressions | `update-baselines` script runs after each accepted PR merge; track baseline age |
| R-004 | Claude Code CLI changes interface or behavior between versions | MEDIUM | 40% | Stage orchestration scripts break | Health check validates CLI version and capabilities at pipeline start; pin CLI version if possible |
| R-005 | Cross-engine improvements are too complex for a single Claude Code session to implement | HIGH | 25% | Implementation fails all 3 retries, creates GitHub issue | Stage 3 integration design limits scope to manageable touchpoints; reject findings with > 5 engines affected until pipeline matures |
| R-006 | Mac must be awake for nightly pipeline runs (no cloud backup) | LOW | 10% | Missed nightly runs | caffeinate during pipeline run; launchd retry on wake; morning notification shows last run time |
| R-007 | Prohibited patterns gate (Stage 6 Gate 1) produces false positives on legitimate code | LOW | 30% | Valid improvements rejected | Maintain allowlist alongside prohibited patterns; tune patterns based on false positive log |

### 7.2 Assumptions

| ID | Assumption | Impact if Wrong | Validator | Status |
|----|------------|-----------------|-----------|--------|
| A-001 | Technical Veil produces structured JSON with relevance scores | Adapter development scope increases significantly | Review Technical Veil output format | Needs validation |
| A-002 | Claude Code CLI supports `--context` flag for injecting files | Must use alternative file injection method (e.g., CLAUDE.md references) | Test current CLI capabilities | Needs validation |
| A-003 | 4 Claude Code sessions per pipeline run stays within Max subscription limits | May need to serialize sessions or reduce to fewer stages | Check Max subscription session limits | Needs validation |
| A-004 | Multi-dimensional quality scoring (verification score + completeness + consistency + coverage) is sufficient to detect regressions | May need human-evaluated quality scores for calibration | Calibrate against 10+ manual reviews | Needs validation |
| A-005 | Engine dependency graph from Package.swift captures sufficient relationships | May miss semantic dependencies (data flow, contract coupling) | Compare auto-generated vs design doc graph | Partially validated (hybrid approach with overrides addresses this) |

### 7.3 Open Questions

| ID | Question | Decision Needed By | Owner |
|----|----------|-------------------|-------|
| OQ-001 | Should the pipeline live inside ai-architect-prd-builder or as a separate repository? | Before Epic 1 implementation | Developer |
| OQ-002 | What is Technical Veil's exact output JSON schema? | Before adapter development (Epic 1) | Developer |
| OQ-003 | Should benchmark inputs be synthetic or derived from actual customer usage patterns? | Before benchmark suite creation (Epic 1) | Developer |
| OQ-004 | How should the pipeline handle findings that require new engine capabilities (not just improvements to existing engines)? | Before Epic 2 prompt design | Developer |
| OQ-005 | Should Stage 4 (dogfood) use the SKILL.md prompt flow or the Swift library API for PRD generation? | Design doc says both; clarify primary vs fallback | Developer |
| OQ-006 | What compound_score threshold should trigger acceptance? Design doc says 0.3 — is this calibrated? | Before Epic 2 deployment | Developer |

### 7.4 Human Review Requirements

| Area | Why Pipeline Cannot Validate | Action |
|------|------------------------------|--------|
| Architectural coherence | Pipeline checks structural compliance but cannot evaluate whether an improvement makes the product architecturally better | Human reviews PR for design quality |
| User-facing impact | Pipeline measures internal quality metrics but cannot assess whether output is more useful to end users | Human evaluates sample PRD outputs |
| Security implications | Deterministic gates check for known patterns but cannot reason about novel attack vectors | Human reviews security-sensitive changes |
| Patent implications | Pipeline cannot assess whether improvements affect IP claims | Human reviews changes touching patentable algorithms |

---

## Summary

| Epic | Size | Dependencies | Phase |
|------|------|-------------|-------|
| **Epic 1: Deterministic Foundation** | L (5-8 weeks) | None | Phase 1 |
| **Epic 2: Intelligence Layer** | L (5-8 weeks) | Epic 1 (engine graph, enforcement gates) | Phase 2 |
| **Epic 3: Dogfood & Implementation** | M (3-4 weeks) | Epic 2 (impact analysis, integration design) | Phase 3 |
| **Epic 4: Verification & Delivery** | M (3-4 weeks) | Epic 3 (implementation output) | Phase 4 |
| **Epic 5: Operational Maturity** | M (3-4 weeks) | Epics 1-4 (all stages working) | Phase 5 |
| **Total** | **19-28 weeks** | Sequential with parallelization opportunities | 5 phases |

**Select an epic when ready for implementation-level PRD.**

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Full Scope Overview)*
*All 5 epics documented with T-shirt sizing and dependency analysis*

