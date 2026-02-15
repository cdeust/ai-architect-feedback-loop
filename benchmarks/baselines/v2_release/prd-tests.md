# Test Cases: AI-Architect Pipeline Feedback

**Generated:** 2026-02-11
**PRD Type:** Full Scope Overview
**Note:** High-level test strategy per epic. Select an epic for detailed test cases with AC traceability.

---

## Test Strategy Overview

| Test Level | Purpose | Epic Coverage |
|------------|---------|---------------|
| **Unit** | Individual script/function validation | All epics |
| **Integration** | Stage-to-stage data flow | Epics 2-4 |
| **End-to-End** | Full pipeline from trigger to PR | Epic 5 |
| **Regression** | Benchmark comparison (old vs new) | Epic 1 |

---

## PART A: Coverage Tests by Epic

### Epic 1: Deterministic Foundation

| Test ID | Type | Component | What It Validates |
|---------|------|-----------|-------------------|
| T-001 | Unit | parse_findings.py | Filters findings by relevance categories; removes below-threshold scores |
| T-002 | Unit | parse_findings.py | Handles empty Technical Veil output gracefully (no findings = clean exit) |
| T-003 | Unit | parse_findings.py | Rejects malformed JSON input with clear error message |
| T-004 | Unit | generate_engine_graph.py | Parses all 9 Package.swift files correctly |
| T-005 | Unit | generate_engine_graph.py | Merges manual overrides into auto-generated graph |
| T-006 | Unit | generate_engine_graph.py | Detects cycles in override definitions |
| T-007 | Integration | stage_6_enforcement.sh | Gate 1: Detects prohibited patterns (TODO, FIXME, placeholder, etc.) |
| T-008 | Integration | stage_6_enforcement.sh | Gate 2: Enforces manifest file constraints (must change / must not change) |
| T-009 | Integration | stage_6_enforcement.sh | Gate 3: Detects orphan files (new files not imported anywhere) |
| T-010 | Integration | stage_6_enforcement.sh | Gate 4: `make build-library` succeeds |
| T-011 | Integration | stage_6_enforcement.sh | Gate 5: `make test-all` passes all package tests |
| T-012 | Integration | stage_6_enforcement.sh | Gate 6: `make distribute` passes 38/38 encryption tests |
| T-013 | Integration | stage_8_quality_gate.sh | Compares old vs new benchmark outputs; detects regression |
| T-014 | Integration | stage_8_quality_gate.sh | Passes when all benchmarks improve or maintain quality |
| T-015 | Integration | stage_8_quality_gate.sh | Runs benchmarks through both SKILL.md and library paths |
| T-016 | Integration | stage_9_deployment.sh | Full `make distribute` succeeds with clean state |
| T-017 | Unit | thresholds.json | All threshold values are valid numbers in expected ranges |
| T-018 | Unit | prohibited_patterns.txt | No empty lines or invalid regex patterns |

### Epic 2: Intelligence Layer

| Test ID | Type | Component | What It Validates |
|---------|------|-----------|-------------------|
| T-019 | Integration | stage_2_impact_analysis.sh | Claude Code CLI session produces valid `impact_report.json` schema |
| T-020 | Unit | validate_impact_report.sh | Rejects findings with engines_affected < 2 |
| T-021 | Unit | validate_impact_report.sh | Rejects findings with compound_score < 0.3 |
| T-022 | Unit | validate_impact_report.sh | Passes findings meeting both thresholds |
| T-023 | Integration | stage_3_integration_design.sh | Claude Code CLI session produces valid `integration_plan.json` schema |
| T-024 | Unit | validate_integration_plan.sh | Rejects plans with new non-test source files |
| T-025 | Unit | validate_integration_plan.sh | Rejects plans with missing engine touchpoints |
| T-026 | Unit | validate_integration_plan.sh | Rejects plans with zero cross-engine connections |
| T-027 | Unit | generate_manifest.py | Produces valid manifest from integration plan |
| T-028 | Unit | generate_manifest.py | Manifest constraints match integration plan |

### Epic 3: Dogfood & Implementation

| Test ID | Type | Component | What It Validates |
|---------|------|-----------|-------------------|
| T-029 | Unit | compose_prd_input.py | Assembles coherent PRD input from finding + plan + contracts |
| T-030 | Integration | stage_4_dogfood.sh | AI-PRD Generator produces PRD with quality score >= 80% |
| T-031 | Integration | stage_4_dogfood.sh | Rejects PRD with quality score < 80% |
| T-032 | Integration | stage_5_implementation.sh | Claude Code CLI creates feature branch and commits code |
| T-033 | Integration | stage_5_implementation.sh | Implementation respects manifest constraints |

### Epic 4: Verification & Delivery

| Test ID | Type | Component | What It Validates |
|---------|------|-----------|-------------------|
| T-034 | Integration | stage_7_semantic_verification.sh | Independent verification detects PRD-code misalignment |
| T-035 | Integration | retry_orchestrator.sh | Retries Stage 5→6→7 up to 3 times on failure |
| T-036 | Integration | retry_orchestrator.sh | Appends failure details to subsequent retry prompts |
| T-037 | Integration | retry_orchestrator.sh | Creates GitHub issue after 3 failed retries |
| T-038 | Unit | compose_pr.py | Produces well-formatted PR description from all stage outputs |
| T-039 | Integration | stage_10_pull_request.sh | Creates PR via `gh pr create` with correct labels |
| T-040 | Integration | stage_10_pull_request.sh | Runs `make sync-public` after PR creation |

### Epic 5: Operational Maturity

| Test ID | Type | Component | What It Validates |
|---------|------|-----------|-------------------|
| T-041 | E2E | pipeline.sh | Full 10-stage pipeline completes successfully with test finding |
| T-042 | E2E | pipeline.sh | Pipeline handles "no findings" gracefully (clean exit at Stage 1) |
| T-043 | E2E | pipeline.sh | Pipeline handles Stage 6 failure with retry and eventual GitHub issue |
| T-044 | Unit | health_check.sh | Detects missing `claude` CLI |
| T-045 | Unit | health_check.sh | Detects missing `gh` CLI |
| T-046 | Unit | health_check.sh | Detects missing `swift` / `swiftc` |
| T-047 | Unit | notify.sh | macOS notification displays with correct content |
| T-048 | Unit | update_baselines.sh | Updates baselines directory from latest passing run |

---

## PART B: AC Validation Tests (High-Level)

**Note:** Full AC-to-test traceability will be generated with implementation-level PRD for selected epic.

| AC Area | What Must Be Validated | Test Approach |
|---------|------------------------|---------------|
| Multi-engine enforcement | Finding affecting 1 engine is rejected | Unit test with mock finding |
| Bolt-on rejection | Integration plan with new standalone file is rejected | Unit test with mock plan |
| Quality regression detection | Benchmark score drop triggers rejection | Integration test with degraded output |
| Build integrity | 38/38 encryption tests pass after improvement | `make distribute` in Stage 9 |
| Retry exhaustion | 3 failures → GitHub issue created | Integration test with intentionally failing implementation |
| Batch processing | Multiple findings processed in single run | E2E test with 3+ mock findings |

---

## PART C: Traceability Matrix (Summary)

| Requirement | Test IDs | Coverage |
|-------------|----------|----------|
| FR-001 (Parse TV output) | T-001, T-002, T-003 | 3 tests |
| FR-002 (TV adapter) | T-001, T-003 | 2 tests |
| FR-003 (Cross-engine analysis) | T-019 | 1 test |
| FR-004 (2+ engine rejection) | T-020, T-021, T-022 | 3 tests |
| FR-005 (Integration design) | T-023 | 1 test |
| FR-006 (Bolt-on rejection) | T-024, T-025, T-026 | 3 tests |
| FR-007 (Dogfood PRD) | T-030, T-031 | 2 tests |
| FR-008 (Implementation) | T-032, T-033 | 2 tests |
| FR-009 (Deterministic gates) | T-007 to T-012 | 6 tests |
| FR-010 (Semantic verification) | T-034 | 1 test |
| FR-011 (Quality gate) | T-013, T-014, T-015 | 3 tests |
| FR-012 (Deployment simulation) | T-016 | 1 test |
| FR-013 (PR creation) | T-038, T-039 | 2 tests |
| FR-014 (Sync public) | T-040 | 1 test |
| FR-015 (Retry logic) | T-035, T-036 | 2 tests |
| FR-016 (Failure issue) | T-037 | 1 test |
| FR-017 (Engine graph) | T-004, T-005, T-006 | 3 tests |
| FR-018 (Both benchmark paths) | T-015 | 1 test |
| FR-019 (Batch processing) | T-041 | 1 test |
| FR-020 (macOS notification) | T-047 | 1 test |
| FR-021 (Run history) | T-041, T-042 | 2 tests |
| **Total** | **48 tests** | **All 21 FRs covered** |

---

*Select an epic for detailed test cases with GIVEN-WHEN-THEN format and AC-specific validation tests.*

