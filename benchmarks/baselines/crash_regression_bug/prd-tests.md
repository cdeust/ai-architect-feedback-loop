# Test Cases: Pipeline Feedback — Epic 2: Intelligence Layer

**Generated:** 2026-02-11
**PRD Type:** Implementation-Level (Focused Epic)
**Total Tests:** 42 tests
**Coverage:** 21 FRs + 6 NFRs → 27 ACs

---

## Test Strategy

| Test Level | Count | Purpose |
|------------|-------|---------|
| **Unit** | 22 | Validator logic, manifest generation, scoring formula |
| **Integration** | 14 | Stage orchestrator → Claude Code CLI → validator chain |
| **End-to-End** | 6 | Full Stage 2 → Stage 3 → manifest pipeline |

---

## PART A: Coverage Tests

### A.1 Unit Tests — validate_impact_report.sh

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E2-001 | validate_impact_report.sh | Rejects report with engines_affected=1 (below threshold 2) | AC-E2-007 |
| UT-E2-002 | validate_impact_report.sh | Rejects report with compound_score=0.2 (below threshold 0.3) | AC-E2-008 |
| UT-E2-003 | validate_impact_report.sh | Accepts report with engines_affected=3, compound_score=0.65 | AC-E2-009 |
| UT-E2-004 | validate_impact_report.sh | Rejection report contains reason, threshold, actual value | AC-E2-010 |
| UT-E2-005 | validate_impact_report.sh | Rejects when both thresholds fail | AC-E2-007, AC-E2-008 |
| UT-E2-006 | validate_impact_report.sh | Handles malformed impact_report.json (missing fields) | AC-E2-007 |

### A.2 Unit Tests — validate_integration_plan.sh

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E2-007 | validate_integration_plan.sh | Rejects plan with new non-test source file | AC-E2-016 |
| UT-E2-008 | validate_integration_plan.sh | Rejects plan with missing engine touchpoint | AC-E2-017 |
| UT-E2-009 | validate_integration_plan.sh | Rejects plan with zero cross-engine connections | AC-E2-018 |
| UT-E2-010 | validate_integration_plan.sh | Accepts valid plan with 3 engines, cross-engine touchpoints | AC-E2-019 |
| UT-E2-011 | validate_integration_plan.sh | Allows new test files (not flagged as non-test) | AC-E2-016 |
| UT-E2-012 | validate_integration_plan.sh | Handles malformed integration_plan.json | AC-E2-016 |

### A.3 Unit Tests — generate_manifest.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E2-013 | generate_manifest.py | Produces valid manifest from integration plan | AC-E2-020 |
| UT-E2-014 | generate_manifest.py | must_change matches plan's modified files exactly | AC-E2-021 |
| UT-E2-015 | generate_manifest.py | must_not_change includes critical unaffected files | AC-E2-022 |
| UT-E2-016 | generate_manifest.py | allowed_new_files contains only test files | AC-E2-020 |
| UT-E2-017 | generate_manifest.py | Package.swift files always in must_not_change | AC-E2-022 |

### A.4 Unit Tests — extract_contracts.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E2-018 | extract_contracts.py | Extracts public protocol with methods | AC-E2-023 |
| UT-E2-019 | extract_contracts.py | Captures public struct/class/func declarations | AC-E2-024 |
| UT-E2-020 | extract_contracts.py | Produces markdown output with code blocks | AC-E2-025 |
| UT-E2-021 | extract_contracts.py | Handles empty Swift file gracefully | AC-E2-023 |

### A.5 Unit Tests — Compound Scoring

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E2-022 | scoring formula | engines=3, depth=2, contract=0.7, test=0.3 → score=1.57 | AC-E2-026 |

### A.6 Integration Tests — Stage 2

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E2-001 | stage_2_impact_analysis.sh | Claude Code CLI invoked with prompt + context | AC-E2-004 |
| IT-E2-002 | stage_2_impact_analysis.sh | impact_report.json written to run directory | AC-E2-005 |
| IT-E2-003 | stage_2_impact_analysis.sh | Error handled on CLI failure (timeout) | AC-E2-006 |
| IT-E2-004 | stage_2_impact_analysis.sh | Output passes JSON Schema validation | AC-E2-003 |
| IT-E2-005 | Stage 2 → Validator | Orchestrator output fed to validator, threshold check works | AC-E2-007 to AC-E2-010 |

### A.7 Integration Tests — Stage 3

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E2-006 | stage_3_integration_design.sh | Claude Code CLI invoked with impact report + contracts | AC-E2-014 |
| IT-E2-007 | stage_3_integration_design.sh | integration_plan.json written to run directory | AC-E2-015 |
| IT-E2-008 | stage_3_integration_design.sh | Output passes JSON Schema validation | AC-E2-013 |
| IT-E2-009 | Stage 3 → Validator | Orchestrator output fed to validator, bolt-on check works | AC-E2-016 to AC-E2-019 |

### A.8 Integration Tests — Prompt Templates

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E2-010 | prompts/impact_analysis.md | Engine graph placeholder is correctly substituted | AC-E2-001 |
| IT-E2-011 | prompts/impact_analysis.md | Finding placeholder is correctly substituted | AC-E2-001 |
| IT-E2-012 | prompts/integration_design.md | Anti-bolt-on rules present in rendered prompt | AC-E2-011 |
| IT-E2-013 | prompts/integration_design.md | Contract context present in rendered prompt | AC-E2-012 |
| IT-E2-014 | extract_contracts.py → prompt | Extracted contracts correctly injected into prompt | AC-E2-012, AC-E2-025 |

### A.9 End-to-End Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| E2E-E2-001 | Stage 2 full | Finding → Claude Code → impact_report.json → validation → accept/reject | AC-E2-001 to AC-E2-010 |
| E2E-E2-002 | Stage 3 full | Impact report → Claude Code → integration_plan.json → validation | AC-E2-011 to AC-E2-019 |
| E2E-E2-003 | Stage 2 → 3 chain | Finding → impact analysis → integration design → manifest | All ACs |
| E2E-E2-004 | Rejection flow | Single-engine finding → Stage 2 → REJECTED (pipeline stops) | AC-E2-007, AC-E2-008 |
| E2E-E2-005 | Bolt-on rejection | Valid impact → bolt-on plan → Stage 3 → REJECTED | AC-E2-016 |
| E2E-E2-006 | Contract extraction | All 9 engines → contracts → markdown → prompt injection | AC-E2-023 to AC-E2-025 |

---

## PART B: AC Validation Tests

### AC-E2-007: Engines Affected Threshold
**Criteria:** GIVEN engines_affected=1 WHEN validator runs THEN REJECTED
**Tests:** UT-E2-001, UT-E2-005, E2E-E2-004
**Assertions:** Exit code != 0, rejection report contains "engines_affected"

### AC-E2-016: New File Rejection
**Criteria:** GIVEN plan with new non-test file WHEN validator runs THEN REJECTED
**Tests:** UT-E2-007, UT-E2-011, E2E-E2-005
**Assertions:** Exit code != 0, rejection contains "non-test source files"

### AC-E2-020: Manifest Generation
**Criteria:** GIVEN valid plan WHEN generator runs THEN manifest.json produced
**Tests:** UT-E2-013, UT-E2-014, UT-E2-015, UT-E2-016, UT-E2-017
**Assertions:** File exists, JSON valid, arrays non-empty

---

## PART C: AC-to-Test Traceability Matrix

| AC ID | AC Title | Test IDs | Test Type | Status |
|-------|----------|----------|-----------|--------|
| AC-E2-001 | Engine Graph Injection | IT-E2-010, IT-E2-011, E2E-E2-001 | Integration + E2E | Pending |
| AC-E2-002 | Propagation Instructions | E2E-E2-001 | E2E | Pending |
| AC-E2-003 | Output Schema | IT-E2-004, E2E-E2-001 | Integration + E2E | Pending |
| AC-E2-004 | CLI Invocation (S2) | IT-E2-001, E2E-E2-001 | Integration + E2E | Pending |
| AC-E2-005 | Output Capture (S2) | IT-E2-002, E2E-E2-001 | Integration + E2E | Pending |
| AC-E2-006 | Error Handling (S2) | IT-E2-003 | Integration | Pending |
| AC-E2-007 | Engines Threshold | UT-E2-001, UT-E2-005, E2E-E2-004 | Unit + E2E | Pending |
| AC-E2-008 | Compound Threshold | UT-E2-002, E2E-E2-004 | Unit + E2E | Pending |
| AC-E2-009 | Valid Report Accept | UT-E2-003 | Unit | Pending |
| AC-E2-010 | Rejection Report | UT-E2-004 | Unit | Pending |
| AC-E2-011 | Anti-Bolt-On Rules | IT-E2-012, E2E-E2-005 | Integration + E2E | Pending |
| AC-E2-012 | Contract Context | IT-E2-013, IT-E2-014, E2E-E2-006 | Integration + E2E | Pending |
| AC-E2-013 | File Specificity | IT-E2-008, E2E-E2-002 | Integration + E2E | Pending |
| AC-E2-014 | CLI Invocation (S3) | IT-E2-006, E2E-E2-002 | Integration + E2E | Pending |
| AC-E2-015 | Output Capture (S3) | IT-E2-007, E2E-E2-002 | Integration + E2E | Pending |
| AC-E2-016 | New File Rejection | UT-E2-007, UT-E2-011, E2E-E2-005 | Unit + E2E | Pending |
| AC-E2-017 | Missing Touchpoints | UT-E2-008, E2E-E2-005 | Unit + E2E | Pending |
| AC-E2-018 | Cross-Engine Enforcement | UT-E2-009, E2E-E2-005 | Unit + E2E | Pending |
| AC-E2-019 | Valid Plan Accept | UT-E2-010 | Unit | Pending |
| AC-E2-020 | Manifest Generation | UT-E2-013, UT-E2-016, E2E-E2-003 | Unit + E2E | Pending |
| AC-E2-021 | Must-Change Derivation | UT-E2-014 | Unit | Pending |
| AC-E2-022 | Must-Not-Change | UT-E2-015, UT-E2-017 | Unit | Pending |
| AC-E2-023 | Protocol Extraction | UT-E2-018, UT-E2-021, E2E-E2-006 | Unit + E2E | Pending |
| AC-E2-024 | Public API Surface | UT-E2-019, E2E-E2-006 | Unit + E2E | Pending |
| AC-E2-025 | Output Format | UT-E2-020, E2E-E2-006 | Unit + E2E | Pending |
| AC-E2-026 | Formula Implementation | UT-E2-022 | Unit | Pending |
| AC-E2-027 | Calibration Dataset | E2E-E2-001 | E2E | Pending |
| **Total** | **27 ACs** | **42 tests** | - | **All mapped** |

---

## Test Data Requirements

| Dataset | Purpose | Location |
|---------|---------|----------|
| `impact_report_valid.json` | AC-E2-009 tests | `tests/fixtures/` |
| `impact_report_single_engine.json` | AC-E2-007 rejection test | `tests/fixtures/` |
| `impact_report_low_score.json` | AC-E2-008 rejection test | `tests/fixtures/` |
| `integration_plan_valid.json` | AC-E2-019 acceptance test | `tests/fixtures/` |
| `integration_plan_bolt_on.json` | AC-E2-016 rejection test | `tests/fixtures/` |
| `integration_plan_no_crossengine.json` | AC-E2-018 rejection test | `tests/fixtures/` |
| `mock_swift_protocols/` | AC-E2-023 to AC-E2-025 extraction test | `tests/fixtures/` |
| `calibration_decisions.json` | AC-E2-027 calibration test | `tests/fixtures/` |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
*42 tests covering 27 acceptance criteria across 9 stories*
