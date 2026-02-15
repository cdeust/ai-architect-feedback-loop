# JIRA Tickets: AI-Architect Pipeline Feedback

**Generated:** 2026-02-11
**PRD Type:** Full Scope Overview
**Note:** T-shirt sizing only (no Fibonacci story points). Select an epic for implementation-level breakdown.

---

## Epic 1: Deterministic Foundation [L: 5-8 weeks]

**Description:** Build all deterministic gates (shell scripts, Makefile targets, benchmark harness) that form the foundation for the intelligence layer. No AI involvement in this epic — pure automation.

| Story | Priority | Size | Description |
|-------|----------|------|-------------|
| PIPE-001 | P0 | M | Build Technical Veil output adapter (`parse_findings.py`) that transforms raw TV JSON into pipeline `findings.json` format |
| PIPE-002 | P0 | L | Implement Stage 6: Deterministic Enforcement with 6 gates (prohibited patterns, manifest compliance, dead code, compilation, tests, encryption) |
| PIPE-003 | P0 | M | Build Stage 8: Quality Gate with multi-dimensional benchmark comparison (verification score + completeness + consistency + coverage) |
| PIPE-004 | P0 | S | Build Stage 9: Deployment Simulation wrapper around `make distribute` |
| PIPE-005 | P0 | M | Build Stage 1: Trigger & Parse shell script with relevance category filtering |
| PIPE-006 | P0 | L | Create benchmark suite: 6+ curated PRD inputs covering feature, bug, mvp, ambiguous, contradictory, compliance, mockup types |
| PIPE-007 | P0 | M | Establish benchmark golden baselines by running current product against all benchmark inputs (both SKILL.md and library paths) |
| PIPE-008 | P1 | M | Build engine graph generator (`generate_engine_graph.py`) that parses Package.swift files with manual override support |
| PIPE-009 | P1 | S | Create `config/prohibited_patterns.txt` and `config/thresholds.json` with calibrated values |
| PIPE-010 | P1 | S | Add pipeline Makefile targets: `pipeline-gates`, `pipeline-benchmark`, `pipeline-health`, `update-engine-graph`, `update-baselines` |

**Dependencies:** None (first epic)

---

## Epic 2: Intelligence Layer [L: 5-8 weeks]

**Description:** Build Claude Code CLI session orchestration for cross-engine impact analysis and integration design. This is where bolt-on features get rejected.

| Story | Priority | Size | Description |
|-------|----------|------|-------------|
| PIPE-011 | P0 | L | Write Stage 2 prompt template (`prompts/impact_analysis.md`) with engine graph context, propagation rules, and compound scoring |
| PIPE-012 | P0 | M | Build Stage 2 orchestrator (`stage_2_impact_analysis.sh`) that invokes Claude Code CLI with structured context |
| PIPE-013 | P0 | M | Build Stage 2 validator (`validate_impact_report.sh`) enforcing engines_affected >= 2 and compound_score >= 0.3 |
| PIPE-014 | P0 | L | Write Stage 3 prompt template (`prompts/integration_design.md`) with contract definitions and anti-bolt-on rules |
| PIPE-015 | P0 | M | Build Stage 3 orchestrator (`stage_3_integration_design.sh`) |
| PIPE-016 | P0 | M | Build Stage 3 validator (`validate_integration_plan.sh`) rejecting new non-test files and zero cross-engine connections |
| PIPE-017 | P0 | M | Build manifest generator (`generate_manifest.py`) that converts integration plan into enforcement manifest |
| PIPE-018 | P1 | L | Calibrate compound scoring formula against 10+ manual improvement decisions |
| PIPE-019 | P1 | M | Extract engine contract definitions programmatically from Swift source for prompt context |

**Dependencies:** Epic 1 (engine graph, enforcement gates)

---

## Epic 3: Dogfood & Implementation [M: 3-4 weeks]

**Description:** The self-improving loop. Product specs its own improvements, Claude Code implements them.

| Story | Priority | Size | Description |
|-------|----------|------|-------------|
| PIPE-020 | P0 | M | Build PRD input composer (`compose_prd_input.py`) that assembles finding + integration plan + contracts into PRD input |
| PIPE-021 | P0 | M | Build Stage 4 orchestrator (`stage_4_dogfood.sh`) invoking AI-PRD Generator via both SKILL.md and Swift library |
| PIPE-022 | P0 | S | Add quality threshold check: reject PRDs with verification score < 80% |
| PIPE-023 | P0 | L | Write Stage 5 prompt template (`prompts/implementation.md`) with PRD, integration plan, manifest, and CLAUDE.md references |
| PIPE-024 | P0 | M | Build Stage 5 orchestrator (`stage_5_implementation.sh`) creating feature branch and invoking Claude Code CLI |

**Dependencies:** Epic 2 (impact report, integration plan)

---

## Epic 4: Verification & Delivery [M: 3-4 weeks]

**Description:** Independent verification, retry logic, and PR creation with full audit trail.

| Story | Priority | Size | Description |
|-------|----------|------|-------------|
| PIPE-025 | P0 | L | Write Stage 7 prompt template (`prompts/semantic_verification.md`) focused on finding misalignment |
| PIPE-026 | P0 | M | Build Stage 7 orchestrator (`stage_7_semantic_verification.sh`) |
| PIPE-027 | P0 | M | Build retry orchestrator (`retry_orchestrator.sh`) managing Stage 5→6→7 loop (max 3 retries) |
| PIPE-028 | P0 | M | Build PR description composer (`compose_pr.py`) assembling all stage outputs |
| PIPE-029 | P0 | M | Build Stage 10 (`stage_10_pull_request.sh`) with `gh pr create` + `make sync-public` |
| PIPE-030 | P1 | S | Build failure issue creator using `gh issue create` with structured failure report |

**Dependencies:** Epic 3 (implementation output to verify)

---

## Epic 5: Operational Maturity [M: 3-4 weeks]

**Description:** Nightly scheduling, monitoring, health checks, and self-healing.

| Story | Priority | Size | Description |
|-------|----------|------|-------------|
| PIPE-031 | P0 | L | Build main pipeline orchestrator (`pipeline.sh`) sequencing all 10 stages with error handling |
| PIPE-032 | P0 | M | Build health check script validating all dependencies (claude, gh, make, swift, swiftc) |
| PIPE-033 | P1 | M | Create launchd plist for nightly scheduling with caffeinate support |
| PIPE-034 | P1 | S | Build macOS notification script (`notify.sh`) with morning summary |
| PIPE-035 | P1 | S | Build baseline update script (`update_baselines.sh`) for post-merge baseline refresh |
| PIPE-036 | P2 | S | Add structured JSON logging across all stages |
| PIPE-037 | P2 | S | Add `.gitignore` entries for `runs/` and `logs/` directories |

**Dependencies:** Epics 1-4 (all stages working)

---

## Summary

| Epic | Stories | Size | Phase |
|------|---------|------|-------|
| Epic 1: Deterministic Foundation | 10 | L (5-8 weeks) | Phase 1 |
| Epic 2: Intelligence Layer | 9 | L (5-8 weeks) | Phase 2 |
| Epic 3: Dogfood & Implementation | 5 | M (3-4 weeks) | Phase 3 |
| Epic 4: Verification & Delivery | 6 | M (3-4 weeks) | Phase 4 |
| Epic 5: Operational Maturity | 7 | M (3-4 weeks) | Phase 5 |
| **Total** | **37** | **19-28 weeks** | **5 phases** |

---

*Select an epic for implementation-level PRD with Fibonacci story points, sprint plan, and detailed acceptance criteria.*

