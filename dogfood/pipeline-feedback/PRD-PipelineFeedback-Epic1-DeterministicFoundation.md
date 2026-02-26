# PRD: Pipeline Feedback — Epic 1: Deterministic Foundation

**Document Type:** Implementation-Level PRD (Focused Epic)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Parent PRD:** PRD-PipelineFeedback.md (Full Scope Overview)
**Epic:** 1 of 5 — Deterministic Foundation
**Stages Covered:** 1, 6, 8, 9
**Estimated Effort:** 55 SP (Fibonacci)
**License Tier:** Licensed (Full verification engine + all 15 strategies)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Goals & Success Metrics](#2-goals--success-metrics)
3. [Requirements](#3-requirements)
4. [User Stories & Acceptance Criteria](#4-user-stories--acceptance-criteria)
5. [Technical Specification](#5-technical-specification)
6. [Implementation Roadmap](#6-implementation-roadmap)
7. [Open Questions](#7-open-questions)
8. [Appendix: Future Epics](#8-appendix-future-epics)

---

## 1. Overview

### 1.1 Epic Scope

Epic 1 builds the deterministic foundation that every subsequent pipeline stage depends on. No AI involvement — pure automation, shell scripts, Python parsers, and Makefile integration.

| Component | Stage | What It Delivers |
|-----------|-------|-----------------|
| Technical Veil Adapter | Stage 1 | Transforms raw TV JSON into pipeline `findings.json` |
| Trigger & Parse Script | Stage 1 | Filters findings by AI-PRD relevance categories |
| Engine Graph Generator | Pre-req | Auto-generates `engine_graph.json` from Package.swift files |
| Deterministic Enforcement | Stage 6 | 6 hard gates: patterns, manifest, dead code, build, tests, encryption |
| Quality Gate | Stage 8 | Multi-dimensional benchmark comparison (old vs new) |
| Deployment Simulation | Stage 9 | Full `make distribute` integrity check |
| Benchmark Suite | Pre-req | 6+ curated inputs with golden baselines |
| Configuration Files | Pre-req | `thresholds.json`, `prohibited_patterns.txt` |

### 1.2 Integration Philosophy

Every deliverable integrates with existing infrastructure — no standalone scripts that exist in isolation:

- **Makefile targets**: `pipeline-gates`, `pipeline-benchmark`, `pipeline-health`, `update-engine-graph`, `update-baselines`
- **Existing targets wrapped**: `make build-library`, `make test-all`, `make distribute`
- **Configuration co-located**: `config/` directory alongside existing `scripts/` structure
- **No new dependencies**: Python 3 (system), Bash (POSIX), existing Swift toolchain

### 1.3 Constraints

- No TODO, FIXME, placeholder, dead code, or deprecated methods in deliverables
- All scripts must be POSIX-compatible bash (no zsh-specific features)
- Pipeline artifacts (`runs/`, `logs/`) must not be committed to git
- Scripts must integrate as improvements to the overall product process
- All Python scripts must work with macOS system Python 3

---

## 2. Goals & Success Metrics

### 2.1 Epic-Level Goals

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| EG-001 | Establish deterministic gate infrastructure | No automated quality gates exist | 6 gates operational with 0% false negative rate | Gate execution on test corpus |
| EG-002 | Create benchmark suite for regression detection | No benchmarks exist | 6+ benchmark inputs covering all PRD types | Benchmark count in `benchmarks/inputs/` |
| EG-003 | Auto-generate engine dependency graph | Manual knowledge only | Machine-readable `engine_graph.json` with < 5 min generation time | `generate_engine_graph.py` execution time |
| EG-004 | Integrate pipeline targets into Makefile | 0 pipeline-related targets | 6 new pipeline targets integrated | `make help` output |
| EG-005 | Parse Technical Veil output for pipeline consumption | No adapter exists | Adapter produces valid `findings.json` from TV output | Adapter unit tests |

### 2.2 Key Performance Indicators

| KPI | How Measured | Target |
|-----|-------------|--------|
| Gate execution time (all 6 gates) | `time scripts/pipeline/stage_6_enforcement.sh` | < 15 minutes |
| Benchmark suite execution time (all inputs, both paths) | `time scripts/pipeline/stage_8_quality_gate.sh` | < 30 minutes |
| Engine graph generation time | `time scripts/pipeline/generate_engine_graph.py` | < 30 seconds |
| False positive rate on prohibited patterns | Manual review of gate results on known-good codebase | < 5% |
| Deployment simulation pass rate on clean codebase | `make distribute` on main branch | 100% |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement | Story |
|----|----------|-------------|-------|
| FR-E1-001 | P0 | `parse_findings.py` transforms Technical Veil JSON output into pipeline-compatible `findings.json` format | PIPE-E1-001 |
| FR-E1-002 | P0 | Adapter filters findings by relevance categories: prompting, retrieval, verification, embeddings, inference, cost_optimization, benchmarks | PIPE-E1-001 |
| FR-E1-003 | P0 | Adapter rejects findings with relevance scores below configurable threshold (default: 0.5) | PIPE-E1-001 |
| FR-E1-004 | P0 | Adapter handles empty TV output gracefully (no findings = clean exit with code 0) | PIPE-E1-001 |
| FR-E1-005 | P0 | Adapter rejects malformed JSON input with clear error message and exit code 1 | PIPE-E1-001 |
| FR-E1-006 | P0 | `stage_1_trigger.sh` invokes adapter, writes output to `runs/<timestamp>/findings.json` | PIPE-E1-002 |
| FR-E1-007 | P0 | `generate_engine_graph.py` parses all 9 Package.swift files and produces `engine_graph.json` | PIPE-E1-003 |
| FR-E1-008 | P0 | Engine graph generator merges manual overrides from `engine_graph_overrides.json` | PIPE-E1-003 |
| FR-E1-009 | P0 | Engine graph generator detects cycles in override definitions and exits with error | PIPE-E1-003 |
| FR-E1-010 | P0 | `stage_6_enforcement.sh` Gate 1: Detects prohibited patterns (configurable via `prohibited_patterns.txt`) | PIPE-E1-004 |
| FR-E1-011 | P0 | `stage_6_enforcement.sh` Gate 2: Enforces manifest file constraints (must-change / must-not-change) | PIPE-E1-004 |
| FR-E1-012 | P0 | `stage_6_enforcement.sh` Gate 3: Detects orphan files (new files not imported anywhere) | PIPE-E1-004 |
| FR-E1-013 | P0 | `stage_6_enforcement.sh` Gate 4: `make build-library` succeeds | PIPE-E1-004 |
| FR-E1-014 | P0 | `stage_6_enforcement.sh` Gate 5: `make test-all` passes all package tests | PIPE-E1-004 |
| FR-E1-015 | P0 | `stage_6_enforcement.sh` Gate 6: `make distribute` passes 38/38 encryption tests | PIPE-E1-004 |
| FR-E1-016 | P0 | `stage_8_quality_gate.sh` runs benchmark suite through SKILL.md prompt flow | PIPE-E1-006 |
| FR-E1-017 | P0 | `stage_8_quality_gate.sh` runs benchmark suite through Swift library direct invocation | PIPE-E1-006 |
| FR-E1-018 | P0 | Quality gate compares multi-dimensional scores: verification score, section completeness, consistency, requirement coverage | PIPE-E1-006 |
| FR-E1-019 | P0 | Quality gate rejects if any benchmark dimension regresses beyond configurable threshold | PIPE-E1-006 |
| FR-E1-020 | P0 | Quality gate passes when all benchmarks maintain or improve quality | PIPE-E1-006 |
| FR-E1-021 | P0 | `stage_9_deployment.sh` runs `make distribute` and reports pass/fail | PIPE-E1-007 |
| FR-E1-022 | P0 | Benchmark suite includes 6+ curated inputs covering: feature, bug, mvp, ambiguous, contradictory, compliance PRD types | PIPE-E1-005 |
| FR-E1-023 | P1 | `update_baselines.sh` copies latest benchmark outputs to `benchmarks/baselines/` | PIPE-E1-008 |
| FR-E1-024 | P1 | `thresholds.json` contains all configurable threshold values with valid ranges | PIPE-E1-009 |
| FR-E1-025 | P1 | `prohibited_patterns.txt` contains regex patterns for Stage 6 Gate 1 | PIPE-E1-009 |
| FR-E1-026 | P1 | 6 new Makefile targets integrated: `pipeline-gates`, `pipeline-benchmark`, `pipeline-health`, `update-engine-graph`, `update-baselines`, `pipeline-stage1` | PIPE-E1-010 |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-E1-001 | P0 | All shell scripts use `set -euo pipefail` for strict error handling | 100% of scripts |
| NFR-E1-002 | P0 | All shell scripts use POSIX-compatible bash (no zsh-specific features) | No `zsh` in shebangs |
| NFR-E1-003 | P0 | Gate false negative rate (passing code that violates constraints) | 0% |
| NFR-E1-004 | P1 | Gate false positive rate (rejecting valid code) | < 5% |
| NFR-E1-005 | P1 | Benchmark suite execution time (all inputs, both paths) | < 30 minutes |
| NFR-E1-006 | P1 | Engine graph generation time | < 30 seconds |
| NFR-E1-007 | P1 | All Python scripts work with macOS system Python 3 (no pip dependencies) | 0 external packages |
| NFR-E1-008 | P2 | Structured logging from all scripts (JSON format to stdout) | Parseable by `jq` |

---

## 4. User Stories & Acceptance Criteria

### PIPE-E1-001: Technical Veil Output Adapter [8 SP]

**As a** pipeline operator,
**I want** Technical Veil findings transformed into a standard pipeline format,
**So that** downstream stages receive consistent, validated input regardless of TV output format changes.

**AC-E1-001:** Valid TV Output Parsing
- [ ] GIVEN a valid Technical Veil JSON file with 10 findings WHEN `parse_findings.py` runs THEN output contains only findings matching relevance categories (prompting, retrieval, verification, embeddings, inference, cost_optimization, benchmarks)

| Metric | Value |
|--------|-------|
| Baseline | N/A — new capability |
| Target | 100% of relevant findings extracted |
| Measurement | Unit test with synthetic TV output |
| Business Impact | BG-002: enables daily improvement candidates |

**AC-E1-002:** Relevance Score Filtering
- [ ] GIVEN findings with relevance scores [0.2, 0.5, 0.8, 0.9] WHEN adapter runs with threshold 0.5 THEN only findings with score >= 0.5 pass (3 of 4)

| Metric | Value |
|--------|-------|
| Baseline | N/A — new capability |
| Target | Exact threshold enforcement |
| Measurement | Unit test with scored findings |
| Business Impact | BG-003: filters to high-quality candidates |

**AC-E1-003:** Empty TV Output Handling
- [ ] GIVEN an empty TV output file (valid JSON, zero findings) WHEN adapter runs THEN exits with code 0 and produces empty `findings.json` array

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Clean exit (code 0) on no findings |
| Measurement | Unit test with empty input |
| Business Impact | TG-001: pipeline completion rate |

**AC-E1-004:** Malformed JSON Rejection
- [ ] GIVEN a malformed JSON file (truncated, invalid syntax) WHEN adapter runs THEN exits with code 1 and prints error message to stderr

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% malformed inputs detected |
| Measurement | Unit test with corrupted JSON |
| Business Impact | TG-003: gate reliability |

**Tasks:**
- [ ] Define `findings.json` output schema (fields: id, title, description, source_url, relevance_category, relevance_score, raw_data)
- [ ] Implement `parse_findings.py` with argparse CLI (--input, --output, --threshold)
- [ ] Add relevance category enum validation
- [ ] Add unit tests for all AC scenarios
- [ ] Add structured JSON logging (finding count, filtered count, threshold used)

---

### PIPE-E1-002: Stage 1 Trigger & Parse Script [5 SP]

**As a** pipeline orchestrator,
**I want** a shell script that triggers Technical Veil output parsing and prepares the run directory,
**So that** each pipeline run has a clean, timestamped workspace with filtered findings.

**AC-E1-005:** Run Directory Creation
- [ ] GIVEN pipeline trigger WHEN `stage_1_trigger.sh` runs THEN creates `runs/<YYYYMMDD_HHMMSS>/` directory

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Timestamped directory created |
| Measurement | Directory existence check |
| Business Impact | FR-021: run history |

**AC-E1-006:** Adapter Invocation
- [ ] GIVEN TV output at expected location WHEN `stage_1_trigger.sh` runs THEN invokes `parse_findings.py` and writes `findings.json` to run directory

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | `findings.json` present in run directory |
| Measurement | File existence + JSON validation |
| Business Impact | BG-001: automated cycle time |

**AC-E1-007:** No-Findings Clean Exit
- [ ] GIVEN adapter returns 0 findings WHEN `stage_1_trigger.sh` runs THEN script exits cleanly with code 0 and message "No actionable findings"

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Clean exit, no error logs |
| Measurement | Exit code + log inspection |
| Business Impact | TG-001: pipeline completion rate |

**Tasks:**
- [ ] Implement `stage_1_trigger.sh` with `set -euo pipefail`
- [ ] Add timestamp generation and run directory creation
- [ ] Integrate `parse_findings.py` invocation
- [ ] Add findings count check and early exit on zero findings
- [ ] Add structured log output (stage, timestamp, findings_count, status)

---

### PIPE-E1-003: Engine Dependency Graph Generator [8 SP]

**As a** pipeline intelligence layer (Epic 2),
**I want** a machine-readable engine dependency graph generated from actual Package.swift files,
**So that** cross-engine impact analysis uses accurate, up-to-date dependency information.

**AC-E1-008:** Package.swift Parsing
- [ ] GIVEN 9 Package.swift files in `packages/` WHEN `generate_engine_graph.py` runs THEN all 9 engines appear in `engine_graph.json` with correct dependency edges

| Metric | Value |
|--------|-------|
| Baseline | Manual knowledge of 9 engines |
| Target | 9/9 engines parsed, all dependencies correct |
| Measurement | Graph node/edge count validation against known structure |
| Business Impact | BG-003: 100% multi-engine analysis |

**AC-E1-009:** Manual Override Merging
- [ ] GIVEN `engine_graph_overrides.json` with semantic relationships (feeds/fed_by/role) WHEN generator runs THEN overrides are merged into auto-generated graph

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All override fields present in output |
| Measurement | JSON diff between output and expected merged graph |
| Business Impact | FR-017: hybrid auto + override approach |

**AC-E1-010:** Cycle Detection
- [ ] GIVEN override definitions that create a cycle (A → B → C → A) WHEN generator runs THEN exits with code 1 and prints cycle path

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% cycles detected |
| Measurement | Unit test with intentional cycles |
| Business Impact | TG-003: gate reliability |

**AC-E1-011:** Output Schema Compliance
- [ ] GIVEN valid Package.swift files WHEN generator runs THEN output matches the `engine_graph.json` schema from PRD section 6.5

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Schema-valid JSON output |
| Measurement | JSON Schema validation |
| Business Impact | EG-003: machine-readable graph |

**Tasks:**
- [ ] Implement Package.swift parser (regex-based, extract `.package(path:)` and `.product(name:package:)`)
- [ ] Build adjacency list from parsed dependencies
- [ ] Implement override merging (deep merge with conflict detection)
- [ ] Implement cycle detection (DFS with back-edge detection)
- [ ] Add `--output`, `--overrides`, `--packages-dir` CLI arguments
- [ ] Add unit tests for all AC scenarios
- [ ] Create initial `engine_graph_overrides.json` with semantic relationships from PRD section 6.5

**Known Package Dependencies (from codebase exploration):**
- Layer 0: SharedUtilities (no deps)
- Layer 1: RAG, Verification, Strategy, Encryption, Vision (depend on SharedUtilities)
- Layer 2: MetaPrompting (SharedUtilities + RAG), VisionEngineApple (SharedUtilities + Vision)
- Layer 3: Orchestration (SharedUtilities, RAG, Verification, MetaPrompting, Strategy)

---

### PIPE-E1-004: Stage 6 Deterministic Enforcement Gates [13 SP]

**As a** pipeline quality enforcer,
**I want** 6 deterministic gates that validate implementation quality without any AI involvement,
**So that** no code passes that violates structural, compilation, or testing constraints.

**AC-E1-012:** Gate 1 — Prohibited Pattern Detection
- [ ] GIVEN a codebase with TODO/FIXME/placeholder comments WHEN Gate 1 runs THEN all prohibited patterns are detected and reported with file:line references

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% pattern detection rate (0% false negatives) |
| Measurement | Test with seeded violations |
| Business Impact | TG-003: gate reliability; user constraint (no TODO/FIXME) |

**AC-E1-013:** Gate 2 — Manifest Compliance
- [ ] GIVEN a manifest specifying `must_change: [file_a.swift]` and `must_not_change: [file_b.swift]` WHEN Gate 2 runs against a git diff THEN correctly reports compliance/violation

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% manifest constraint enforcement |
| Measurement | Test with controlled git diff |
| Business Impact | FR-009: deterministic gate enforcement |

**AC-E1-014:** Gate 3 — Orphan File Detection
- [ ] GIVEN a new file `NewHelper.swift` not imported anywhere WHEN Gate 3 runs THEN file is flagged as orphan

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All orphan files detected |
| Measurement | Test with intentionally orphaned file |
| Business Impact | User constraint (no dead code) |

**AC-E1-015:** Gate 4 — Build Verification
- [ ] GIVEN implementation changes WHEN Gate 4 runs `make build-library` THEN returns pass/fail with build output

| Metric | Value |
|--------|-------|
| Baseline | `make build-library` succeeds on main |
| Target | Build success maintained after changes |
| Measurement | Exit code of `make build-library` |
| Business Impact | TG-004: build pipeline integrity |

**AC-E1-016:** Gate 5 — Test Suite
- [ ] GIVEN implementation changes WHEN Gate 5 runs `make test-all` THEN all 100+ package tests pass

| Metric | Value |
|--------|-------|
| Baseline | 100 tests passing (64 Encryption + 33 Orchestration + 3 Vision) |
| Target | All existing tests pass + new tests pass |
| Measurement | Exit code of `make test-all` |
| Business Impact | TG-004: build pipeline integrity |

**AC-E1-017:** Gate 6 — Encryption Integrity
- [ ] GIVEN implementation changes WHEN Gate 6 runs `make distribute` THEN 38/38 encryption validation tests pass

| Metric | Value |
|--------|-------|
| Baseline | 38/38 passing |
| Target | 38/38 maintained |
| Measurement | Exit code of `make distribute` |
| Business Impact | TG-004: 38/38 encryption tests |

**AC-E1-018:** Enforcement Report
- [ ] GIVEN all 6 gates executed WHEN enforcement completes THEN produces structured `enforcement_report.json` with per-gate pass/fail, duration, and details

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Complete report for all 6 gates |
| Measurement | JSON schema validation |
| Business Impact | FR-013: PR audit trail |

**Tasks:**
- [ ] Implement `stage_6_enforcement.sh` with modular gate functions
- [ ] Gate 1: `grep -rn` with patterns from `prohibited_patterns.txt`, exclude `config/` and test files
- [ ] Gate 2: Parse `manifest.json` for must-change/must-not-change, compare against `git diff --name-only`
- [ ] Gate 3: Find new `.swift` files in diff, check each is imported by at least one other file
- [ ] Gate 4: Invoke `make build-library`, capture output
- [ ] Gate 5: Invoke `make test-all`, capture output
- [ ] Gate 6: Invoke `make distribute`, capture output (includes key injection, build, encrypt, 38 tests)
- [ ] Generate `enforcement_report.json` with structured results
- [ ] Add `--manifest` and `--run-dir` CLI arguments
- [ ] Add `--skip-gate` option for testing individual gates

---

### PIPE-E1-005: Benchmark Suite Creation [8 SP]

**As a** pipeline quality gate (Stage 8),
**I want** a curated set of benchmark inputs covering all PRD types,
**So that** quality regression can be detected by comparing outputs before and after improvements.

**AC-E1-019:** Benchmark Input Coverage
- [ ] GIVEN 6+ benchmark input files WHEN enumerated THEN cover at minimum: feature, bug, mvp, ambiguous, contradictory, compliance PRD types

| Metric | Value |
|--------|-------|
| Baseline | 0 benchmark inputs exist |
| Target | 6+ inputs covering all types |
| Measurement | File count + type coverage validation |
| Business Impact | TG-005: 6+ benchmark inputs |

**AC-E1-020:** Benchmark Input Format
- [ ] GIVEN each benchmark input WHEN validated THEN contains: title, description, type, expected_sections, and optional mockup_paths

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% schema-valid inputs |
| Measurement | JSON Schema validation |
| Business Impact | EG-002: benchmark suite established |

**AC-E1-021:** Golden Baseline Establishment
- [ ] GIVEN all benchmark inputs WHEN baseline generation runs THEN produces baseline outputs in `benchmarks/baselines/<input_name>/` for both SKILL.md and library paths

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Baselines for all inputs × both paths |
| Measurement | Baseline directory structure validation |
| Business Impact | BG-005: regression detection baseline |

**Tasks:**
- [ ] Design benchmark input JSON schema
- [ ] Create `simple_feature.json` — standard feature request with clear requirements
- [ ] Create `complex_multiepic.json` — large scope requiring epic decomposition
- [ ] Create `ambiguous_requirements.json` — vague requirements testing clarification quality
- [ ] Create `contradictory_specs.json` — conflicting requirements testing conflict detection
- [ ] Create `compliance_heavy.json` — GDPR/security-heavy requirements
- [ ] Create `mockup_driven.json` — mockup-first PRD with UI screenshots
- [ ] Establish initial golden baselines by running current product against all inputs
- [ ] Document baseline establishment process in README

---

### PIPE-E1-006: Stage 8 Quality Gate [13 SP]

**As a** pipeline quality enforcer,
**I want** multi-dimensional benchmark comparison that detects output quality regression,
**So that** no improvement degrades the product's PRD generation quality.

**AC-E1-022:** SKILL.md Path Benchmark
- [ ] GIVEN benchmark inputs WHEN quality gate runs THEN executes PRD generation through SKILL.md Claude Code CLI flow for each input

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All benchmark inputs processed via SKILL.md |
| Measurement | Output file count = input file count |
| Business Impact | FR-018: both paths tested |

**AC-E1-023:** Library Path Benchmark
- [ ] GIVEN benchmark inputs WHEN quality gate runs THEN executes PRD generation through Swift library direct invocation for each input

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All benchmark inputs processed via library |
| Measurement | Output file count = input file count |
| Business Impact | FR-018: both paths tested |

**AC-E1-024:** Multi-Dimensional Scoring
- [ ] GIVEN old and new benchmark outputs WHEN comparison runs THEN produces scores across 4 dimensions: verification_score, section_completeness, consistency, requirement_coverage

| Metric | Value |
|--------|-------|
| Baseline | N/A — scoring dimensions defined |
| Target | 4 dimension scores per benchmark input |
| Measurement | Score JSON schema validation |
| Business Impact | FR-011: multi-dimensional quality gate |

**AC-E1-025:** Regression Detection
- [ ] GIVEN old baseline score of 0.85 for verification_score and new score of 0.78 WHEN comparison runs with regression threshold 0.05 THEN gate reports FAIL for that dimension

| Metric | Value |
|--------|-------|
| Baseline | Configurable regression threshold (default: 0.05) |
| Target | 100% regression detection when delta exceeds threshold |
| Measurement | Test with degraded synthetic output |
| Business Impact | BG-005: 0% quality regression |

**AC-E1-026:** Pass-Through on Improvement
- [ ] GIVEN all benchmark dimensions maintain or improve scores WHEN comparison runs THEN gate reports PASS

| Metric | Value |
|--------|-------|
| Baseline | All baseline scores |
| Target | PASS when no regression detected |
| Measurement | Test with improved synthetic output |
| Business Impact | BG-005: quality maintained |

**AC-E1-027:** Quality Report
- [ ] GIVEN comparison complete WHEN quality gate finishes THEN produces `quality_results.json` with per-input, per-dimension, per-path scoring details

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Complete structured report |
| Measurement | JSON schema validation |
| Business Impact | FR-013: PR audit trail |

**Tasks:**
- [ ] Implement `stage_8_quality_gate.sh` as orchestrator
- [ ] Implement SKILL.md benchmark runner (Claude Code CLI invocation per input)
- [ ] Implement library benchmark runner (Swift library invocation per input)
- [ ] Implement multi-dimensional scoring engine (Python):
  - `verification_score`: extract from PRD verification report
  - `section_completeness`: count sections vs expected for PRD type
  - `consistency`: cross-reference requirement IDs
  - `requirement_coverage`: FR/NFR count and AC mapping
- [ ] Implement old-vs-new comparator with configurable regression thresholds
- [ ] Generate `quality_results.json` with structured scoring
- [ ] Add `--baseline-dir`, `--current-dir`, `--threshold` CLI arguments

---

### PIPE-E1-007: Stage 9 Deployment Simulation [3 SP]

**As a** pipeline integrity checker,
**I want** a deployment simulation that verifies the full build-encrypt-test pipeline,
**So that** code changes don't break the distribution process.

**AC-E1-028:** Full Distribute Execution
- [ ] GIVEN code changes on a feature branch WHEN `stage_9_deployment.sh` runs THEN executes `make distribute` (build 9 xcFrameworks + encrypt + 38 tests)

| Metric | Value |
|--------|-------|
| Baseline | `make distribute` succeeds on main (38/38 tests) |
| Target | 38/38 maintained after improvements |
| Measurement | Exit code + test count from output |
| Business Impact | TG-004: build pipeline integrity |

**AC-E1-029:** Clean State Verification
- [ ] GIVEN `make distribute` completes WHEN deployment simulation finishes THEN placeholder keys are restored in source files (no real keys committed)

| Metric | Value |
|--------|-------|
| Baseline | Source files have placeholder keys |
| Target | Placeholder keys restored post-distribute |
| Measurement | `grep PLACEHOLDER` in SecureLicenseValidator.swift and validate-license.swift |
| Business Impact | Security: no key leakage |

**Tasks:**
- [ ] Implement `stage_9_deployment.sh` wrapping `make distribute`
- [ ] Add post-distribute key restoration step
- [ ] Add deployment report to run directory
- [ ] Verify `.gitignore` prevents build artifacts from staging

---

### PIPE-E1-008: Baseline Update Script [3 SP]

**As a** pipeline maintainer,
**I want** a script that updates benchmark baselines after an accepted improvement,
**So that** baselines stay current and quality gate comparisons remain meaningful.

**AC-E1-030:** Baseline Update
- [ ] GIVEN latest passing quality gate outputs WHEN `update_baselines.sh` runs THEN baselines directory is updated with current outputs

| Metric | Value |
|--------|-------|
| Baseline | Stale baselines (pre-improvement) |
| Target | Current baselines (post-improvement) |
| Measurement | File timestamps + content diff |
| Business Impact | R-003: prevent stale baselines |

**AC-E1-031:** Baseline Backup
- [ ] GIVEN existing baselines WHEN update runs THEN previous baselines are archived to `benchmarks/baselines_archive/<timestamp>/`

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Previous baselines preserved |
| Measurement | Archive directory existence |
| Business Impact | Rollback capability |

**Tasks:**
- [ ] Implement `update_baselines.sh`
- [ ] Add archive step for previous baselines
- [ ] Add `--source-run` argument to specify which run to use
- [ ] Add confirmation prompt (can be bypassed with `--yes`)

---

### PIPE-E1-009: Configuration Files [3 SP]

**As a** pipeline operator,
**I want** externalized configuration for thresholds and patterns,
**So that** pipeline behavior can be tuned without modifying scripts.

**AC-E1-032:** Thresholds Configuration
- [ ] GIVEN `thresholds.json` WHEN validated THEN all values are valid numbers in expected ranges

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Schema-valid configuration |
| Measurement | JSON Schema validation |
| Business Impact | FR-E1-024: configurable thresholds |

**AC-E1-033:** Prohibited Patterns Configuration
- [ ] GIVEN `prohibited_patterns.txt` WHEN validated THEN no empty lines and all entries are valid regex patterns

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid regex patterns only |
| Measurement | Regex compilation test |
| Business Impact | FR-E1-025: configurable patterns |

**Tasks:**
- [ ] Create `config/thresholds.json` with:
  - `relevance_score_minimum`: 0.5
  - `compound_score_minimum`: 0.3
  - `engines_affected_minimum`: 2
  - `quality_regression_threshold`: 0.05
  - `prd_quality_minimum`: 0.80
  - `max_retry_count`: 3
- [ ] Create `config/prohibited_patterns.txt` with:
  - `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP`, `PLACEHOLDER`
  - `placeholder`, `not implemented`, `stub`
  - `deprecated` (in new code only)
- [ ] Add validation scripts for both config files

---

### PIPE-E1-010: Makefile Integration [5 SP]

**As a** developer,
**I want** pipeline targets in the existing Makefile,
**So that** pipeline operations follow the same `make <target>` workflow as existing build operations.

**AC-E1-034:** New Targets Available
- [ ] GIVEN updated Makefile WHEN `make help` runs THEN shows 6 new pipeline targets with descriptions

| Metric | Value |
|--------|-------|
| Baseline | 0 pipeline targets |
| Target | 6 new targets |
| Measurement | `make help` output |
| Business Impact | EG-004: Makefile integration |

**AC-E1-035:** Target Execution
- [ ] GIVEN each pipeline Makefile target WHEN invoked THEN delegates to correct script with proper arguments

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All 6 targets functional |
| Measurement | Execution test per target |
| Business Impact | Integration with existing workflow |

**Tasks:**
- [ ] Add `pipeline-gates` target → `stage_6_enforcement.sh`
- [ ] Add `pipeline-benchmark` target → `stage_8_quality_gate.sh`
- [ ] Add `pipeline-health` target → `health_check.sh` (placeholder, implemented in Epic 5)
- [ ] Add `update-engine-graph` target → `generate_engine_graph.py`
- [ ] Add `update-baselines` target → `update_baselines.sh`
- [ ] Add `pipeline-stage1` target → `stage_1_trigger.sh`
- [ ] Add `.gitignore` entries for `runs/` and `logs/`

---

## 5. Technical Specification

### 5.1 File Structure

```
ai-architect-prd-builder/
├── config/
│   ├── engine_graph.json                # Auto-generated from Package.swift
│   ├── engine_graph_overrides.json      # Manual semantic relationships
│   ├── thresholds.json                  # All configurable thresholds
│   └── prohibited_patterns.txt          # Stage 6 Gate 1 patterns
├── scripts/
│   └── pipeline/
│       ├── stage_1_trigger.sh           # Parse + filter
│       ├── stage_6_enforcement.sh       # 6 deterministic gates
│       ├── stage_8_quality_gate.sh      # Benchmark comparison
│       ├── stage_9_deployment.sh        # make distribute wrapper
│       ├── parse_findings.py            # Technical Veil adapter
│       ├── generate_engine_graph.py     # Package.swift parser
│       ├── score_quality.py             # Multi-dimensional scoring
│       └── update_baselines.sh          # Post-merge baseline refresh
├── benchmarks/
│   ├── inputs/                          # Fixed benchmark inputs
│   │   ├── simple_feature.json
│   │   ├── complex_multiepic.json
│   │   ├── ambiguous_requirements.json
│   │   ├── contradictory_specs.json
│   │   ├── compliance_heavy.json
│   │   └── mockup_driven.json
│   └── baselines/                       # Golden outputs
│       ├── simple_feature/
│       │   ├── skill_path/
│       │   └── library_path/
│       └── ...
├── runs/                                # Timestamped runs (gitignored)
└── logs/                                # Pipeline logs (gitignored)
```

### 5.2 Data Schemas

#### findings.json (Stage 1 Output)

```json
{
  "pipeline_version": "1.0",
  "generated_at": "2026-02-11T22:00:00Z",
  "source": "technical_veil",
  "threshold_used": 0.5,
  "findings": [
    {
      "id": "tv-20260211-001",
      "title": "Contextual retrieval improves RAG precision by 49%",
      "description": "Research from Anthropic shows...",
      "source_url": "https://...",
      "relevance_category": "retrieval",
      "relevance_score": 0.87,
      "raw_data": {}
    }
  ],
  "stats": {
    "total_findings": 15,
    "filtered_findings": 5,
    "categories_matched": ["retrieval", "verification"]
  }
}
```

#### engine_graph.json

```json
{
  "generated_at": "2026-02-11T22:00:00Z",
  "generator_version": "1.0",
  "source": "Package.swift + overrides",
  "engines": {
    "SharedUtilities": {
      "package_path": "packages/AIPRDSharedUtilities",
      "depends_on": [],
      "depended_by": ["RAGEngine", "VerificationEngine", "StrategyEngine", "EncryptionEngine", "VisionEngine", "MetaPromptingEngine", "OrchestrationEngine", "VisionEngineApple"],
      "feeds": ["ALL"],
      "fed_by": [],
      "role": "common_infrastructure"
    }
  },
  "stats": {
    "engine_count": 9,
    "edge_count": 15,
    "max_depth": 3,
    "cycles_detected": 0
  }
}
```

#### enforcement_report.json (Stage 6 Output)

```json
{
  "stage": "enforcement",
  "timestamp": "2026-02-11T22:15:00Z",
  "overall_result": "PASS",
  "gates": [
    {
      "gate": 1,
      "name": "prohibited_patterns",
      "result": "PASS",
      "duration_seconds": 2.1,
      "details": {
        "patterns_checked": 12,
        "violations_found": 0,
        "files_scanned": 245
      }
    },
    {
      "gate": 2,
      "name": "manifest_compliance",
      "result": "PASS",
      "duration_seconds": 0.3,
      "details": {
        "must_change_files": 3,
        "must_change_satisfied": 3,
        "must_not_change_files": 5,
        "must_not_change_satisfied": 5
      }
    }
  ]
}
```

#### quality_results.json (Stage 8 Output)

```json
{
  "stage": "quality_gate",
  "timestamp": "2026-02-11T22:30:00Z",
  "overall_result": "PASS",
  "regression_threshold": 0.05,
  "benchmarks": [
    {
      "input": "simple_feature",
      "paths": {
        "skill": {
          "verification_score": { "baseline": 0.85, "current": 0.88, "delta": 0.03, "result": "IMPROVED" },
          "section_completeness": { "baseline": 0.90, "current": 0.90, "delta": 0.00, "result": "MAINTAINED" },
          "consistency": { "baseline": 0.92, "current": 0.93, "delta": 0.01, "result": "IMPROVED" },
          "requirement_coverage": { "baseline": 0.88, "current": 0.88, "delta": 0.00, "result": "MAINTAINED" }
        },
        "library": {
          "verification_score": { "baseline": 0.83, "current": 0.86, "delta": 0.03, "result": "IMPROVED" }
        }
      }
    }
  ],
  "summary": {
    "total_dimensions_checked": 48,
    "improved": 12,
    "maintained": 36,
    "regressed": 0
  }
}
```

#### thresholds.json

```json
{
  "version": "1.0",
  "stage_1": {
    "relevance_score_minimum": 0.5,
    "relevance_categories": ["prompting", "retrieval", "verification", "embeddings", "inference", "cost_optimization", "benchmarks"]
  },
  "stage_2": {
    "compound_score_minimum": 0.3,
    "engines_affected_minimum": 2
  },
  "stage_6": {
    "prohibited_patterns_file": "config/prohibited_patterns.txt",
    "orphan_detection_extensions": [".swift"],
    "orphan_detection_exclude_dirs": ["Tests", "test", "benchmarks"]
  },
  "stage_8": {
    "regression_threshold": 0.05,
    "dimensions": ["verification_score", "section_completeness", "consistency", "requirement_coverage"]
  },
  "stage_4": {
    "prd_quality_minimum": 0.80
  },
  "retry": {
    "max_attempts": 3
  }
}
```

### 5.3 Script Patterns

All shell scripts follow the existing distribution script patterns:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# stage_X_name.sh — Brief description
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

# Structured logging
log() {
    local level="$1" msg="$2"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"stage\":\"$STAGE_NAME\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

log "INFO" "Stage started"
# ... stage logic ...
log "INFO" "Stage completed"
```

All Python scripts follow:

```python
#!/usr/bin/env python3
"""Brief description of script purpose."""

import argparse
import json
import sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    # ... arguments ...
    args = parser.parse_args()
    # ... logic ...

if __name__ == "__main__":
    main()
```

---

## 6. Implementation Roadmap

### Sprint 1 (Week 1-2): Foundation [21 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E1-009: Configuration Files | 3 | None |
| PIPE-E1-003: Engine Graph Generator | 8 | Config files |
| PIPE-E1-001: Technical Veil Adapter | 8 | Config files (thresholds) |
| PIPE-E1-002: Stage 1 Trigger Script | 5 | TV Adapter |

**Sprint Goal:** Parse TV output and generate engine graph — the two inputs everything downstream needs.

### Sprint 2 (Week 3-4): Enforcement [21 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E1-004: Stage 6 Enforcement Gates | 13 | Config files (patterns, thresholds) |
| PIPE-E1-005: Benchmark Suite Creation | 8 | None (parallel) |

**Sprint Goal:** All 6 deterministic gates operational; benchmark inputs curated.

### Sprint 3 (Week 5-6): Quality & Integration [13 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E1-006: Stage 8 Quality Gate | 13 | Benchmark suite, baselines |

**Sprint Goal:** Multi-dimensional quality comparison working against golden baselines.

### Sprint 4 (Week 7-8): Polish & Ship [11 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E1-007: Stage 9 Deployment Simulation | 3 | None |
| PIPE-E1-008: Baseline Update Script | 3 | Quality gate |
| PIPE-E1-010: Makefile Integration | 5 | All scripts |

**Sprint Goal:** Full deterministic foundation operational, integrated into Makefile.

### Summary

| Sprint | SP | Cumulative | Theme |
|--------|----|-----------|-------|
| Sprint 1 | 21 | 21 | Inputs: parse + graph |
| Sprint 2 | 21 | 42 | Gates: enforcement + benchmarks |
| Sprint 3 | 13 | 55 | Quality: comparison engine |
| Sprint 4 | 11 | 66 | Integration: Makefile + polish |
| **Total** | **66** | - | **8 weeks, 4 sprints** |

---

## 7. Open Questions

| ID | Question | Impact | Decision Needed By |
|----|----------|--------|-------------------|
| OQ-E1-001 | What is Technical Veil's exact output JSON schema? | Adapter implementation | Sprint 1, Week 1 |
| OQ-E1-002 | Should benchmark inputs be synthetic or derived from actual usage patterns? | Benchmark suite quality | Sprint 2, Week 3 |
| OQ-E1-003 | How should Gate 3 (orphan detection) handle test helper files? | False positive rate | Sprint 2, Week 3 |
| OQ-E1-004 | Should Stage 9 restore placeholder keys automatically, or should this be a separate script? | Security workflow | Sprint 4, Week 7 |

---

## 8. Appendix: Future Epics

| Epic | Status | Dependency on Epic 1 |
|------|--------|---------------------|
| **Epic 2: Intelligence Layer** | Pending | Needs `engine_graph.json` + enforcement gates |
| **Epic 3: Dogfood & Implementation** | Pending | Needs Stage 1 output format |
| **Epic 4: Verification & Delivery** | Pending | Needs Stage 6 enforcement |
| **Epic 5: Operational Maturity** | Pending | Needs all stages operational |

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Focused Epic — Deterministic Foundation)*
*Fibonacci story points: 66 SP across 10 stories, 4 sprints*
