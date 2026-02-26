# Test Cases: Pipeline Feedback — Epic 1: Deterministic Foundation

**Generated:** 2026-02-11
**PRD Type:** Implementation-Level (Focused Epic)
**Total Tests:** 52 tests
**Coverage:** 26 FRs + 8 NFRs → 35 ACs

---

## Test Strategy

| Test Level | Count | Purpose |
|------------|-------|---------|
| **Unit** | 28 | Individual function/script validation |
| **Integration** | 18 | Stage-to-stage data flow, Makefile target execution |
| **End-to-End** | 6 | Full stage pipeline from input to output |

---

## PART A: Coverage Tests

### A.1 Unit Tests — parse_findings.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-001 | parse_findings.py | Parses valid TV JSON with 10 findings, extracts only matching relevance categories | AC-E1-001 |
| UT-002 | parse_findings.py | Filters findings by relevance score threshold (0.5 default) — keeps 3 of 4 scored [0.2, 0.5, 0.8, 0.9] | AC-E1-002 |
| UT-003 | parse_findings.py | Handles empty TV output (valid JSON, zero findings) — clean exit code 0 | AC-E1-003 |
| UT-004 | parse_findings.py | Rejects malformed JSON — exit code 1, error to stderr | AC-E1-004 |
| UT-005 | parse_findings.py | Outputs valid `findings.json` schema with all required fields | AC-E1-001 |
| UT-006 | parse_findings.py | Accepts all 7 relevance categories: prompting, retrieval, verification, embeddings, inference, cost_optimization, benchmarks | AC-E1-001 |
| UT-007 | parse_findings.py | Rejects findings with unknown relevance category | AC-E1-001 |
| UT-008 | parse_findings.py | Custom threshold via `--threshold` argument overrides default 0.5 | AC-E1-002 |
| UT-009 | parse_findings.py | Stats block in output shows total_findings, filtered_findings, categories_matched | AC-E1-001 |

### A.2 Unit Tests — generate_engine_graph.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-010 | generate_engine_graph.py | Parses SharedUtilities Package.swift (0 dependencies) | AC-E1-008 |
| UT-011 | generate_engine_graph.py | Parses OrchestrationEngine Package.swift (5 dependencies: SharedUtilities, RAG, Verification, MetaPrompting, Strategy) | AC-E1-008 |
| UT-012 | generate_engine_graph.py | All 9 engines appear in output | AC-E1-008 |
| UT-013 | generate_engine_graph.py | Edge count matches known dependency count | AC-E1-008 |
| UT-014 | generate_engine_graph.py | Merges override feeds/fed_by into auto-generated graph | AC-E1-009 |
| UT-015 | generate_engine_graph.py | Merges override role field into auto-generated graph | AC-E1-009 |
| UT-016 | generate_engine_graph.py | Detects simple cycle (A→B→A) in overrides | AC-E1-010 |
| UT-017 | generate_engine_graph.py | Detects complex cycle (A→B→C→A) in overrides | AC-E1-010 |
| UT-018 | generate_engine_graph.py | Output matches engine_graph.json schema (has engines, stats, generated_at) | AC-E1-011 |
| UT-019 | generate_engine_graph.py | Handles missing Package.swift gracefully (warning, not error) | AC-E1-008 |

### A.3 Unit Tests — Configuration

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-020 | thresholds.json | All threshold values are valid numbers | AC-E1-032 |
| UT-021 | thresholds.json | relevance_score_minimum is between 0.0 and 1.0 | AC-E1-032 |
| UT-022 | thresholds.json | compound_score_minimum is between 0.0 and 1.0 | AC-E1-032 |
| UT-023 | thresholds.json | engines_affected_minimum is >= 1 | AC-E1-032 |
| UT-024 | prohibited_patterns.txt | No empty lines in file | AC-E1-033 |
| UT-025 | prohibited_patterns.txt | All lines compile as valid regex patterns | AC-E1-033 |

### A.4 Unit Tests — score_quality.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-026 | score_quality.py | Extracts verification_score from PRD verification report | AC-E1-024 |
| UT-027 | score_quality.py | Calculates section_completeness (sections present / expected) | AC-E1-024 |
| UT-028 | score_quality.py | Calculates consistency (cross-referenced requirement IDs) | AC-E1-024 |

### A.5 Integration Tests — Stage 1

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-001 | stage_1_trigger.sh | Creates timestamped run directory in `runs/` | AC-E1-005 |
| IT-002 | stage_1_trigger.sh | Invokes parse_findings.py and writes findings.json to run directory | AC-E1-006 |
| IT-003 | stage_1_trigger.sh | Exits cleanly with code 0 when 0 findings returned | AC-E1-007 |
| IT-004 | stage_1_trigger.sh | Structured log output contains stage name, timestamp, findings count | AC-E1-006 |

### A.6 Integration Tests — Stage 6

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-005 | stage_6_enforcement.sh | Gate 1: Detects seeded TODO in test file | AC-E1-012 |
| IT-006 | stage_6_enforcement.sh | Gate 1: Detects seeded FIXME in test file | AC-E1-012 |
| IT-007 | stage_6_enforcement.sh | Gate 1: Does not flag patterns in config/ or test directories | AC-E1-012 |
| IT-008 | stage_6_enforcement.sh | Gate 2: Passes when all must-change files are in diff | AC-E1-013 |
| IT-009 | stage_6_enforcement.sh | Gate 2: Fails when must-not-change file is in diff | AC-E1-013 |
| IT-010 | stage_6_enforcement.sh | Gate 3: Detects new file not imported anywhere | AC-E1-014 |
| IT-011 | stage_6_enforcement.sh | Gate 3: Passes when new file is imported by another file | AC-E1-014 |
| IT-012 | stage_6_enforcement.sh | Gate 4: `make build-library` executes and reports result | AC-E1-015 |
| IT-013 | stage_6_enforcement.sh | Gate 5: `make test-all` executes and reports result | AC-E1-016 |
| IT-014 | stage_6_enforcement.sh | Gate 6: `make distribute` executes and reports 38/38 | AC-E1-017 |
| IT-015 | stage_6_enforcement.sh | Produces valid enforcement_report.json with all 6 gates | AC-E1-018 |

### A.7 Integration Tests — Stage 8

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-016 | stage_8_quality_gate.sh | Detects regression when score drops below threshold | AC-E1-025 |
| IT-017 | stage_8_quality_gate.sh | Passes when all dimensions maintain or improve | AC-E1-026 |
| IT-018 | stage_8_quality_gate.sh | Produces valid quality_results.json | AC-E1-027 |

### A.8 Integration Tests — Stage 9

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-019 | stage_9_deployment.sh | `make distribute` executes successfully | AC-E1-028 |
| IT-020 | stage_9_deployment.sh | Placeholder keys restored after distribute | AC-E1-029 |

### A.9 Integration Tests — Baselines & Makefile

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-021 | update_baselines.sh | Updates baselines directory from specified run | AC-E1-030 |
| IT-022 | update_baselines.sh | Archives previous baselines before overwriting | AC-E1-031 |

### A.10 End-to-End Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| E2E-001 | Stage 1 → findings.json | Full flow: TV JSON → adapter → run dir → findings.json | AC-E1-001 to AC-E1-007 |
| E2E-002 | Stage 6 full | All 6 gates execute sequentially on clean codebase, all pass | AC-E1-012 to AC-E1-018 |
| E2E-003 | Stage 8 full | Benchmark suite runs, compares against baselines, produces report | AC-E1-022 to AC-E1-027 |
| E2E-004 | Stage 9 full | Deployment simulation completes with key restoration | AC-E1-028 to AC-E1-029 |
| E2E-005 | Engine graph | Parse all 9 Package.swift + merge overrides → valid graph | AC-E1-008 to AC-E1-011 |
| E2E-006 | Makefile targets | All 6 pipeline targets execute without error | AC-E1-034, AC-E1-035 |

---

## PART B: AC Validation Tests

### AC-E1-001: Valid TV Output Parsing
**Criteria:** GIVEN valid TV JSON with 10 findings WHEN `parse_findings.py` runs THEN only matching relevance categories extracted
**Tests:** UT-001, UT-005, UT-006, UT-009
**Assertions:**
- Output JSON has `findings` array
- Each finding has `relevance_category` in allowed set
- Output `stats.total_findings` matches input count
- Output `stats.filtered_findings` <= input count

### AC-E1-002: Relevance Score Filtering
**Criteria:** GIVEN scores [0.2, 0.5, 0.8, 0.9] with threshold 0.5 THEN 3 findings pass
**Tests:** UT-002, UT-008
**Assertions:**
- Exactly 3 findings in output (score >= 0.5)
- Finding with score 0.2 absent
- Custom `--threshold 0.7` would yield 2 findings

### AC-E1-003: Empty TV Output
**Criteria:** GIVEN empty TV output THEN exit code 0, empty findings array
**Tests:** UT-003
**Assertions:**
- Process exit code == 0
- Output `findings` array length == 0
- No error output to stderr

### AC-E1-004: Malformed JSON Rejection
**Criteria:** GIVEN malformed JSON THEN exit code 1, error to stderr
**Tests:** UT-004
**Assertions:**
- Process exit code == 1
- stderr contains error message with "JSON" or "parse"
- No output file created (or empty)

### AC-E1-008: Package.swift Parsing
**Criteria:** GIVEN 9 Package.swift files THEN all 9 engines in output
**Tests:** UT-010, UT-011, UT-012, UT-013
**Assertions:**
- Output `engines` object has exactly 9 keys
- SharedUtilities has 0 dependencies
- OrchestrationEngine has 5 dependencies
- `stats.engine_count` == 9

### AC-E1-010: Cycle Detection
**Criteria:** GIVEN cyclic overrides THEN exit code 1 with cycle path
**Tests:** UT-016, UT-017
**Assertions:**
- Process exit code == 1
- stderr contains cycle description (e.g., "A → B → C → A")

### AC-E1-012: Gate 1 — Prohibited Patterns
**Criteria:** GIVEN codebase with TODO/FIXME THEN all detected with file:line
**Tests:** IT-005, IT-006, IT-007
**Assertions:**
- Each violation includes file path and line number
- No violations reported from excluded directories (config/, Tests/)
- All patterns from `prohibited_patterns.txt` checked

### AC-E1-025: Regression Detection
**Criteria:** GIVEN baseline 0.85, new 0.78, threshold 0.05 THEN FAIL
**Tests:** IT-016
**Assertions:**
- Gate result == "FAIL"
- Report shows dimension name, baseline, current, delta
- Delta (0.07) exceeds threshold (0.05)

### AC-E1-028: Full Distribute
**Criteria:** GIVEN changes WHEN stage 9 runs THEN 38/38 tests pass
**Tests:** IT-019
**Assertions:**
- `make distribute` exit code == 0
- Output contains "38/38" or equivalent pass count

### AC-E1-029: Key Restoration
**Criteria:** GIVEN distribute completes THEN placeholder keys restored
**Tests:** IT-020
**Assertions:**
- `SecureLicenseValidator.swift` contains `PLACEHOLDER_PUBLIC_KEY_INJECT_AT_BUILD_TIME`
- `validate-license.swift` contains `PLACEHOLDER_PUBLIC_KEY_INJECT_AT_BUILD_TIME`

---

## PART C: AC-to-Test Traceability Matrix

| AC ID | AC Title | Test IDs | Test Type | Status |
|-------|----------|----------|-----------|--------|
| AC-E1-001 | Valid TV Output Parsing | UT-001, UT-005, UT-006, UT-009, E2E-001 | Unit + E2E | Pending |
| AC-E1-002 | Relevance Score Filtering | UT-002, UT-008 | Unit | Pending |
| AC-E1-003 | Empty TV Output | UT-003, E2E-001 | Unit + E2E | Pending |
| AC-E1-004 | Malformed JSON Rejection | UT-004 | Unit | Pending |
| AC-E1-005 | Run Directory Creation | IT-001, E2E-001 | Integration + E2E | Pending |
| AC-E1-006 | Adapter Invocation | IT-002, IT-004, E2E-001 | Integration + E2E | Pending |
| AC-E1-007 | No-Findings Clean Exit | IT-003, E2E-001 | Integration + E2E | Pending |
| AC-E1-008 | Package.swift Parsing | UT-010, UT-011, UT-012, UT-013, UT-019, E2E-005 | Unit + E2E | Pending |
| AC-E1-009 | Manual Override Merging | UT-014, UT-015, E2E-005 | Unit + E2E | Pending |
| AC-E1-010 | Cycle Detection | UT-016, UT-017 | Unit | Pending |
| AC-E1-011 | Output Schema Compliance | UT-018, E2E-005 | Unit + E2E | Pending |
| AC-E1-012 | Gate 1 — Prohibited Patterns | IT-005, IT-006, IT-007, E2E-002 | Integration + E2E | Pending |
| AC-E1-013 | Gate 2 — Manifest Compliance | IT-008, IT-009, E2E-002 | Integration + E2E | Pending |
| AC-E1-014 | Gate 3 — Orphan Detection | IT-010, IT-011, E2E-002 | Integration + E2E | Pending |
| AC-E1-015 | Gate 4 — Build | IT-012, E2E-002 | Integration + E2E | Pending |
| AC-E1-016 | Gate 5 — Tests | IT-013, E2E-002 | Integration + E2E | Pending |
| AC-E1-017 | Gate 6 — Encryption | IT-014, E2E-002 | Integration + E2E | Pending |
| AC-E1-018 | Enforcement Report | IT-015, E2E-002 | Integration + E2E | Pending |
| AC-E1-019 | Benchmark Input Coverage | E2E-003 | E2E | Pending |
| AC-E1-020 | Benchmark Input Format | E2E-003 | E2E | Pending |
| AC-E1-021 | Golden Baselines | E2E-003 | E2E | Pending |
| AC-E1-022 | SKILL.md Path | E2E-003 | E2E | Pending |
| AC-E1-023 | Library Path | E2E-003 | E2E | Pending |
| AC-E1-024 | Multi-Dimensional Scoring | UT-026, UT-027, UT-028, IT-016 | Unit + Integration | Pending |
| AC-E1-025 | Regression Detection | IT-016, E2E-003 | Integration + E2E | Pending |
| AC-E1-026 | Pass on Improvement | IT-017, E2E-003 | Integration + E2E | Pending |
| AC-E1-027 | Quality Report | IT-018, E2E-003 | Integration + E2E | Pending |
| AC-E1-028 | Full Distribute | IT-019, E2E-004 | Integration + E2E | Pending |
| AC-E1-029 | Key Restoration | IT-020, E2E-004 | Integration + E2E | Pending |
| AC-E1-030 | Baseline Update | IT-021 | Integration | Pending |
| AC-E1-031 | Baseline Backup | IT-022 | Integration | Pending |
| AC-E1-032 | Thresholds Valid | UT-020, UT-021, UT-022, UT-023 | Unit | Pending |
| AC-E1-033 | Patterns Valid | UT-024, UT-025 | Unit | Pending |
| AC-E1-034 | New Makefile Targets | E2E-006 | E2E | Pending |
| AC-E1-035 | Target Execution | E2E-006 | E2E | Pending |
| **Total** | **35 ACs** | **52 tests** | - | **All mapped** |

---

## Test Data Requirements

| Dataset | Purpose | Size | Location |
|---------|---------|------|----------|
| `tv_output_valid.json` | AC-E1-001, AC-E1-002 tests | 10 findings | `tests/fixtures/` |
| `tv_output_empty.json` | AC-E1-003 test | 0 findings | `tests/fixtures/` |
| `tv_output_malformed.json` | AC-E1-004 test | Invalid JSON | `tests/fixtures/` |
| `package_swift_mocks/` | AC-E1-008 to AC-E1-011 tests | 9 mock Package.swift | `tests/fixtures/` |
| `overrides_cyclic.json` | AC-E1-010 test | Intentional cycle | `tests/fixtures/` |
| `manifest_test.json` | AC-E1-013 tests | Must-change/must-not-change | `tests/fixtures/` |
| `benchmark_baselines_test/` | AC-E1-025, AC-E1-026 tests | Synthetic baselines | `tests/fixtures/` |
| `benchmark_degraded_test/` | AC-E1-025 test | Degraded outputs | `tests/fixtures/` |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
*52 tests covering 35 acceptance criteria across 10 stories*
