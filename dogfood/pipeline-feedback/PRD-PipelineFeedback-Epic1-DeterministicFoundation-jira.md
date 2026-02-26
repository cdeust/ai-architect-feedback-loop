# JIRA Tickets: Pipeline Feedback — Epic 1: Deterministic Foundation

**Generated:** 2026-02-11
**Total Story Points:** 66 SP
**Estimated Duration:** 8 weeks (1 developer, 4 sprints)
**Parent PRD:** PRD-PipelineFeedback-Epic1-DeterministicFoundation.md

---

## Epic: Deterministic Foundation [66 SP]

**Description:** Build all deterministic gates (shell scripts, Makefile targets, benchmark harness) that form the foundation for the intelligence layer. No AI involvement — pure automation.

---

### PIPE-E1-001: Build Technical Veil Output Adapter
**Type:** Story | **Priority:** P0 | **SP:** 8 | **Sprint:** 1

**Description:**
As a pipeline operator,
I want Technical Veil findings transformed into a standard pipeline format,
So that downstream stages receive consistent, validated input regardless of TV output format changes.

**Acceptance Criteria:**

**AC-E1-001:** Valid TV Output Parsing
- [ ] GIVEN a valid Technical Veil JSON file with 10 findings WHEN `parse_findings.py` runs THEN output contains only findings matching relevance categories

| Baseline | N/A | Target | 100% relevant findings extracted | Measurement | Unit test | Impact | BG-002 |

**AC-E1-002:** Relevance Score Filtering
- [ ] GIVEN findings with scores [0.2, 0.5, 0.8, 0.9] WHEN adapter runs with threshold 0.5 THEN only 3 findings pass

| Baseline | N/A | Target | Exact threshold enforcement | Measurement | Unit test | Impact | BG-003 |

**AC-E1-003:** Empty TV Output Handling
- [ ] GIVEN empty TV output WHEN adapter runs THEN exits with code 0 and empty findings array

| Baseline | N/A | Target | Clean exit (code 0) | Measurement | Unit test | Impact | TG-001 |

**AC-E1-004:** Malformed JSON Rejection
- [ ] GIVEN malformed JSON WHEN adapter runs THEN exits with code 1 and error to stderr

| Baseline | N/A | Target | 100% detection | Measurement | Unit test | Impact | TG-003 |

**Tasks:**
- [ ] Define `findings.json` output schema
- [ ] Implement `parse_findings.py` with argparse CLI
- [ ] Add relevance category enum validation
- [ ] Add unit tests (4 test cases minimum)
- [ ] Add structured JSON logging

**Dependencies:** PIPE-E1-009 (thresholds config)
**Labels:** pipeline, stage-1, python, p0

---

### PIPE-E1-002: Build Stage 1 Trigger & Parse Script
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 1

**Description:**
As a pipeline orchestrator,
I want a shell script that triggers TV output parsing and prepares the run directory,
So that each pipeline run has a clean, timestamped workspace.

**Acceptance Criteria:**

**AC-E1-005:** Run Directory Creation
- [ ] GIVEN pipeline trigger WHEN script runs THEN creates `runs/<YYYYMMDD_HHMMSS>/` directory

| Baseline | N/A | Target | Directory created | Measurement | Existence check | Impact | FR-021 |

**AC-E1-006:** Adapter Invocation
- [ ] GIVEN TV output at expected location WHEN script runs THEN writes `findings.json` to run directory

| Baseline | N/A | Target | File present | Measurement | File + JSON validation | Impact | BG-001 |

**AC-E1-007:** No-Findings Clean Exit
- [ ] GIVEN 0 findings from adapter WHEN script runs THEN exits code 0 with "No actionable findings"

| Baseline | N/A | Target | Clean exit | Measurement | Exit code | Impact | TG-001 |

**Tasks:**
- [ ] Implement `stage_1_trigger.sh` with `set -euo pipefail`
- [ ] Add timestamp generation and run directory creation
- [ ] Integrate `parse_findings.py` invocation
- [ ] Add early exit on zero findings
- [ ] Add structured log output

**Dependencies:** PIPE-E1-001 (TV adapter)
**Labels:** pipeline, stage-1, bash, p0

---

### PIPE-E1-003: Build Engine Dependency Graph Generator
**Type:** Story | **Priority:** P0 | **SP:** 8 | **Sprint:** 1

**Description:**
As a pipeline intelligence layer,
I want a machine-readable engine dependency graph from Package.swift files,
So that cross-engine impact analysis uses accurate dependency information.

**Acceptance Criteria:**

**AC-E1-008:** Package.swift Parsing
- [ ] GIVEN 9 Package.swift files WHEN generator runs THEN all 9 engines in output with correct edges

| Baseline | Manual knowledge | Target | 9/9 engines, all deps correct | Measurement | Graph validation | Impact | BG-003 |

**AC-E1-009:** Manual Override Merging
- [ ] GIVEN overrides with semantic relationships WHEN generator runs THEN overrides merged into output

| Baseline | N/A | Target | All overrides present | Measurement | JSON diff | Impact | FR-017 |

**AC-E1-010:** Cycle Detection
- [ ] GIVEN overrides creating A→B→C→A cycle WHEN generator runs THEN exits code 1 with cycle path

| Baseline | N/A | Target | 100% cycles detected | Measurement | Unit test | Impact | TG-003 |

**AC-E1-011:** Output Schema Compliance
- [ ] GIVEN valid inputs WHEN generator runs THEN output matches engine_graph.json schema

| Baseline | N/A | Target | Schema-valid | Measurement | JSON Schema | Impact | EG-003 |

**Tasks:**
- [ ] Implement Package.swift parser (regex: `.package(path:)`, `.product(name:package:)`)
- [ ] Build adjacency list from parsed dependencies
- [ ] Implement override merging (deep merge)
- [ ] Implement cycle detection (DFS)
- [ ] Add CLI arguments: `--output`, `--overrides`, `--packages-dir`
- [ ] Create initial `engine_graph_overrides.json`
- [ ] Add unit tests (4 test cases)

**Dependencies:** PIPE-E1-009 (config files)
**Labels:** pipeline, engine-graph, python, p0

---

### PIPE-E1-004: Build Stage 6 Deterministic Enforcement Gates
**Type:** Story | **Priority:** P0 | **SP:** 13 | **Sprint:** 2

**Description:**
As a pipeline quality enforcer,
I want 6 deterministic gates that validate implementation quality without AI involvement,
So that no code passes that violates structural, compilation, or testing constraints.

**Acceptance Criteria:**

**AC-E1-012:** Gate 1 — Prohibited Patterns
- [ ] GIVEN codebase with TODO/FIXME WHEN Gate 1 runs THEN all patterns detected with file:line

| Baseline | N/A | Target | 0% false negatives | Measurement | Seeded violations test | Impact | TG-003 |

**AC-E1-013:** Gate 2 — Manifest Compliance
- [ ] GIVEN manifest with must-change/must-not-change WHEN Gate 2 runs THEN correct compliance report

| Baseline | N/A | Target | 100% enforcement | Measurement | Controlled git diff | Impact | FR-009 |

**AC-E1-014:** Gate 3 — Orphan Detection
- [ ] GIVEN unimported new file WHEN Gate 3 runs THEN flagged as orphan

| Baseline | N/A | Target | All orphans detected | Measurement | Orphaned file test | Impact | No dead code |

**AC-E1-015:** Gate 4 — Build
- [ ] GIVEN changes WHEN Gate 4 runs `make build-library` THEN pass/fail reported

| Baseline | Build succeeds on main | Target | Build success maintained | Measurement | Exit code | Impact | TG-004 |

**AC-E1-016:** Gate 5 — Tests
- [ ] GIVEN changes WHEN Gate 5 runs `make test-all` THEN all 100+ tests pass

| Baseline | 100 tests passing | Target | All tests pass | Measurement | Exit code | Impact | TG-004 |

**AC-E1-017:** Gate 6 — Encryption
- [ ] GIVEN changes WHEN Gate 6 runs `make distribute` THEN 38/38 tests pass

| Baseline | 38/38 passing | Target | 38/38 maintained | Measurement | Exit code | Impact | TG-004 |

**AC-E1-018:** Enforcement Report
- [ ] GIVEN all gates executed WHEN enforcement completes THEN `enforcement_report.json` with per-gate details

| Baseline | N/A | Target | Complete structured report | Measurement | JSON Schema | Impact | FR-013 |

**Tasks:**
- [ ] Implement `stage_6_enforcement.sh` with modular gate functions
- [ ] Gate 1: grep with patterns from `prohibited_patterns.txt`
- [ ] Gate 2: Parse manifest, compare against `git diff --name-only`
- [ ] Gate 3: Find new `.swift` files, check import references
- [ ] Gate 4: `make build-library` wrapper
- [ ] Gate 5: `make test-all` wrapper
- [ ] Gate 6: `make distribute` wrapper
- [ ] Generate `enforcement_report.json`
- [ ] Add `--manifest` and `--run-dir` arguments
- [ ] Add `--skip-gate` for testing individual gates

**Dependencies:** PIPE-E1-009 (prohibited patterns config)
**Labels:** pipeline, stage-6, enforcement, bash, p0

---

### PIPE-E1-005: Create Benchmark Suite
**Type:** Story | **Priority:** P0 | **SP:** 8 | **Sprint:** 2

**Description:**
As a pipeline quality gate,
I want curated benchmark inputs covering all PRD types,
So that quality regression can be detected by comparing outputs.

**Acceptance Criteria:**

**AC-E1-019:** Benchmark Input Coverage
- [ ] GIVEN 6+ input files WHEN enumerated THEN cover: feature, bug, mvp, ambiguous, contradictory, compliance

| Baseline | 0 inputs | Target | 6+ inputs | Measurement | File count | Impact | TG-005 |

**AC-E1-020:** Benchmark Input Format
- [ ] GIVEN each input WHEN validated THEN contains: title, description, type, expected_sections

| Baseline | N/A | Target | 100% schema-valid | Measurement | JSON Schema | Impact | EG-002 |

**AC-E1-021:** Golden Baseline Establishment
- [ ] GIVEN all inputs WHEN baseline generation runs THEN baselines for all inputs × both paths

| Baseline | N/A | Target | Complete baselines | Measurement | Directory validation | Impact | BG-005 |

**Tasks:**
- [ ] Design benchmark input JSON schema
- [ ] Create `simple_feature.json`
- [ ] Create `complex_multiepic.json`
- [ ] Create `ambiguous_requirements.json`
- [ ] Create `contradictory_specs.json`
- [ ] Create `compliance_heavy.json`
- [ ] Create `mockup_driven.json`
- [ ] Run current product against all inputs for golden baselines
- [ ] Document baseline process

**Dependencies:** None (parallel with PIPE-E1-004)
**Labels:** pipeline, benchmarks, p0

---

### PIPE-E1-006: Build Stage 8 Quality Gate
**Type:** Story | **Priority:** P0 | **SP:** 13 | **Sprint:** 3

**Description:**
As a pipeline quality enforcer,
I want multi-dimensional benchmark comparison detecting output quality regression,
So that no improvement degrades PRD generation quality.

**Acceptance Criteria:**

**AC-E1-022:** SKILL.md Path Benchmark
- [ ] GIVEN inputs WHEN quality gate runs THEN PRD generation via SKILL.md for each input

| Baseline | N/A | Target | All inputs processed | Measurement | Output count | Impact | FR-018 |

**AC-E1-023:** Library Path Benchmark
- [ ] GIVEN inputs WHEN quality gate runs THEN PRD generation via Swift library for each input

| Baseline | N/A | Target | All inputs processed | Measurement | Output count | Impact | FR-018 |

**AC-E1-024:** Multi-Dimensional Scoring
- [ ] GIVEN old/new outputs WHEN comparison runs THEN 4 dimensions scored

| Baseline | N/A | Target | 4 scores per input | Measurement | Schema validation | Impact | FR-011 |

**AC-E1-025:** Regression Detection
- [ ] GIVEN baseline 0.85, new 0.78, threshold 0.05 WHEN comparison runs THEN FAIL reported

| Baseline | Configurable threshold | Target | 100% regression detection | Measurement | Degraded output test | Impact | BG-005 |

**AC-E1-026:** Pass on Improvement
- [ ] GIVEN all dimensions maintained/improved WHEN comparison runs THEN PASS

| Baseline | All baseline scores | Target | PASS on no regression | Measurement | Improved output test | Impact | BG-005 |

**AC-E1-027:** Quality Report
- [ ] GIVEN comparison complete WHEN finished THEN `quality_results.json` with full details

| Baseline | N/A | Target | Complete report | Measurement | JSON Schema | Impact | FR-013 |

**Tasks:**
- [ ] Implement `stage_8_quality_gate.sh` orchestrator
- [ ] Implement SKILL.md benchmark runner (Claude Code CLI)
- [ ] Implement library benchmark runner (Swift invocation)
- [ ] Implement `score_quality.py` with 4 scoring dimensions
- [ ] Implement old-vs-new comparator
- [ ] Generate `quality_results.json`
- [ ] Add CLI arguments: `--baseline-dir`, `--current-dir`, `--threshold`

**Dependencies:** PIPE-E1-005 (benchmark suite + baselines)
**Labels:** pipeline, stage-8, quality, p0

---

### PIPE-E1-007: Build Stage 9 Deployment Simulation
**Type:** Story | **Priority:** P0 | **SP:** 3 | **Sprint:** 4

**Description:**
As a pipeline integrity checker,
I want deployment simulation verifying the full build-encrypt-test pipeline,
So that code changes don't break the distribution process.

**Acceptance Criteria:**

**AC-E1-028:** Full Distribute
- [ ] GIVEN changes WHEN `stage_9_deployment.sh` runs THEN `make distribute` executes (38/38 tests)

| Baseline | 38/38 on main | Target | 38/38 maintained | Measurement | Exit code + test count | Impact | TG-004 |

**AC-E1-029:** Key Restoration
- [ ] GIVEN `make distribute` completes WHEN finished THEN placeholder keys restored in source

| Baseline | Placeholder keys | Target | Placeholders restored | Measurement | grep PLACEHOLDER | Impact | Security |

**Tasks:**
- [ ] Implement `stage_9_deployment.sh`
- [ ] Add post-distribute key restoration
- [ ] Add deployment report to run directory
- [ ] Verify `.gitignore` prevents build artifacts

**Dependencies:** None
**Labels:** pipeline, stage-9, deployment, p0

---

### PIPE-E1-008: Build Baseline Update Script
**Type:** Story | **Priority:** P1 | **SP:** 3 | **Sprint:** 4

**Description:**
As a pipeline maintainer,
I want a script to update benchmark baselines after accepted improvements,
So that baselines stay current for quality gate comparisons.

**Acceptance Criteria:**

**AC-E1-030:** Baseline Update
- [ ] GIVEN latest passing outputs WHEN `update_baselines.sh` runs THEN baselines updated

| Baseline | Stale baselines | Target | Current baselines | Measurement | Content diff | Impact | R-003 |

**AC-E1-031:** Baseline Backup
- [ ] GIVEN existing baselines WHEN update runs THEN previous archived to `baselines_archive/<timestamp>/`

| Baseline | N/A | Target | Previous preserved | Measurement | Archive existence | Impact | Rollback |

**Tasks:**
- [ ] Implement `update_baselines.sh`
- [ ] Add archive step
- [ ] Add `--source-run` argument
- [ ] Add `--yes` bypass for confirmation

**Dependencies:** PIPE-E1-006 (quality gate)
**Labels:** pipeline, baselines, bash, p1

---

### PIPE-E1-009: Create Configuration Files
**Type:** Story | **Priority:** P0 | **SP:** 3 | **Sprint:** 1

**Description:**
As a pipeline operator,
I want externalized configuration for thresholds and patterns,
So that behavior can be tuned without modifying scripts.

**Acceptance Criteria:**

**AC-E1-032:** Thresholds Valid
- [ ] GIVEN `thresholds.json` WHEN validated THEN all values valid numbers in expected ranges

| Baseline | N/A | Target | Schema-valid | Measurement | JSON Schema | Impact | FR-E1-024 |

**AC-E1-033:** Patterns Valid
- [ ] GIVEN `prohibited_patterns.txt` WHEN validated THEN no empty lines, all valid regex

| Baseline | N/A | Target | Valid regex | Measurement | Compilation test | Impact | FR-E1-025 |

**Tasks:**
- [ ] Create `config/thresholds.json` with calibrated values
- [ ] Create `config/prohibited_patterns.txt` with pattern list
- [ ] Add validation script for both files

**Dependencies:** None (first story)
**Labels:** pipeline, config, p0

---

### PIPE-E1-010: Integrate Pipeline Targets into Makefile
**Type:** Story | **Priority:** P1 | **SP:** 5 | **Sprint:** 4

**Description:**
As a developer,
I want pipeline targets in the existing Makefile,
So that pipeline operations follow the `make <target>` workflow.

**Acceptance Criteria:**

**AC-E1-034:** New Targets
- [ ] GIVEN updated Makefile WHEN `make help` THEN shows 6 new pipeline targets

| Baseline | 0 targets | Target | 6 new targets | Measurement | `make help` | Impact | EG-004 |

**AC-E1-035:** Target Execution
- [ ] GIVEN each target WHEN invoked THEN delegates to correct script

| Baseline | N/A | Target | All functional | Measurement | Execution test | Impact | Integration |

**Tasks:**
- [ ] Add 6 pipeline targets to Makefile
- [ ] Add `.gitignore` entries for `runs/` and `logs/`
- [ ] Test all targets

**Dependencies:** All scripts complete
**Labels:** pipeline, makefile, integration, p1

---

## Summary

| Sprint | Stories | Story Points | Theme |
|--------|---------|-------------|-------|
| Sprint 1 (Wk 1-2) | PIPE-E1-009, E1-003, E1-001, E1-002 | 24 | Inputs: parse + graph |
| Sprint 2 (Wk 3-4) | PIPE-E1-004, E1-005 | 21 | Gates: enforcement + benchmarks |
| Sprint 3 (Wk 5-6) | PIPE-E1-006 | 13 | Quality: comparison engine |
| Sprint 4 (Wk 7-8) | PIPE-E1-007, E1-008, E1-010 | 11 | Integration: deploy + Makefile |
| **Total** | **10** | **69** | **4 sprints, 8 weeks** |

---

## Dependency Graph

```
PIPE-E1-009 (Config) ──┬──▶ PIPE-E1-001 (TV Adapter) ──▶ PIPE-E1-002 (Stage 1)
                       │
                       ├──▶ PIPE-E1-003 (Engine Graph)
                       │
                       └──▶ PIPE-E1-004 (Stage 6 Gates)
                                │
PIPE-E1-005 (Benchmarks) ──────┤
                                │
                                └──▶ PIPE-E1-006 (Stage 8 Quality) ──▶ PIPE-E1-008 (Baselines)
                                                                              │
PIPE-E1-007 (Stage 9) ─────────────────────────────────────────────┐         │
                                                                    ▼         ▼
                                                          PIPE-E1-010 (Makefile)
```

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
