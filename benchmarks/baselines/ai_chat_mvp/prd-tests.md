# Test Cases: Pipeline Feedback — Epic 3: Dogfood & Implementation

**Generated:** 2026-02-11
**PRD Type:** Implementation-Level (Focused Epic)
**Total Tests:** 28 tests
**Coverage:** 16 FRs + 4 NFRs → 16 ACs

---

## PART A: Coverage Tests

### A.1 Unit Tests — compose_prd_input.py

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E3-001 | compose_prd_input.py | Extracts finding title, description, source URL from impact_report.json | AC-E3-001 |
| UT-E3-002 | compose_prd_input.py | Includes affected engines list from integration_plan.json | AC-E3-002 |
| UT-E3-003 | compose_prd_input.py | Includes cross-engine touchpoints in output | AC-E3-002 |
| UT-E3-004 | compose_prd_input.py | Produces valid markdown with required sections | AC-E3-003 |
| UT-E3-005 | compose_prd_input.py | Batch mode: 3 findings → 3 separate documents | AC-E3-004 |
| UT-E3-006 | compose_prd_input.py | Handles missing optional fields gracefully | AC-E3-001 |
| UT-E3-007 | compose_prd_input.py | Includes engine contract snippets in output | AC-E3-002 |

### A.2 Unit Tests — Quality Threshold

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E3-008 | stage_4_dogfood.sh | Extracts verification score from PRD verification report | AC-E3-007 |
| UT-E3-009 | stage_4_dogfood.sh | Score 75% with threshold 80% → REJECTED | AC-E3-007 |
| UT-E3-010 | stage_4_dogfood.sh | Score 88% with threshold 80% → ACCEPTED | AC-E3-008 |
| UT-E3-011 | stage_4_dogfood.sh | Score exactly 80% → ACCEPTED (>= threshold) | AC-E3-008 |

### A.3 Unit Tests — Prompt Templates

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E3-012 | prompts/implementation.md | Contains PRD placeholder section | AC-E3-010 |
| UT-E3-013 | prompts/implementation.md | Contains integration plan constraint section | AC-E3-011 |
| UT-E3-014 | prompts/implementation.md | References CLAUDE.md rules | AC-E3-012 |

### A.4 Integration Tests — Stage 4

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E3-001 | stage_4_dogfood.sh | SKILL.md path: Claude Code CLI invoked, produces output | AC-E3-005 |
| IT-E3-002 | stage_4_dogfood.sh | Library path: Swift library invoked, produces output | AC-E3-006 |
| IT-E3-003 | stage_4_dogfood.sh | Run directory contains 4 PRD files after success | AC-E3-009 |
| IT-E3-004 | stage_4_dogfood.sh | Low quality PRD rejected, not written to output | AC-E3-007 |

### A.5 Integration Tests — Stage 5

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E3-005 | stage_5_implementation.sh | Feature branch created with correct naming | AC-E3-013 |
| IT-E3-006 | stage_5_implementation.sh | Claude Code CLI session produces code changes | AC-E3-014 |
| IT-E3-007 | stage_5_implementation.sh | At least 1 commit on feature branch | AC-E3-015 |
| IT-E3-008 | stage_5_implementation.sh | Failure preserves branch state, exits code 1 | AC-E3-016 |
| IT-E3-009 | stage_5_implementation.sh | Branch not left checked out on failure (returns to main) | AC-E3-016 |

### A.6 End-to-End Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| E2E-E3-001 | Stage 4 full | Finding artifacts → compose → AI-PRD Generator → quality check → output | All Stage 4 ACs |
| E2E-E3-002 | Stage 5 full | PRD + plan + manifest → branch → Claude Code → commits | All Stage 5 ACs |
| E2E-E3-003 | Stage 4 → 5 chain | Finding → PRD → implementation → feature branch with code | All ACs |
| E2E-E3-004 | Quality rejection flow | Low-quality PRD → Stage 4 rejects → pipeline stops before Stage 5 | AC-E3-007 |

---

## PART B: AC Validation Tests

### AC-E3-007: Quality Threshold Enforcement
**Criteria:** GIVEN PRD with verification score 75% WHEN quality check runs THEN REJECTED
**Tests:** UT-E3-009, IT-E3-004, E2E-E3-004
**Assertions:** Exit code != 0, rejection contains "75% < threshold 80%"

### AC-E3-013: Feature Branch Creation
**Criteria:** GIVEN finding id `tv-20260211-001` WHEN Stage 5 starts THEN branch `pipeline/improvement-tv-20260211-001`
**Tests:** IT-E3-005, E2E-E3-002
**Assertions:** `git branch` shows correct name, branch exists

---

## PART C: AC-to-Test Traceability Matrix

| AC ID | AC Title | Test IDs | Test Type | Status |
|-------|----------|----------|-----------|--------|
| AC-E3-001 | Finding Context | UT-E3-001, UT-E3-006, E2E-E3-001 | Unit + E2E | Pending |
| AC-E3-002 | Integration Constraints | UT-E3-002, UT-E3-003, UT-E3-007, E2E-E3-001 | Unit + E2E | Pending |
| AC-E3-003 | Output Format | UT-E3-004, E2E-E3-001 | Unit + E2E | Pending |
| AC-E3-004 | Batch Mode | UT-E3-005 | Unit | Pending |
| AC-E3-005 | SKILL.md Path | IT-E3-001, E2E-E3-001 | Integration + E2E | Pending |
| AC-E3-006 | Library Path | IT-E3-002 | Integration | Pending |
| AC-E3-007 | Quality Rejection | UT-E3-009, IT-E3-004, E2E-E3-004 | Unit + Integration + E2E | Pending |
| AC-E3-008 | Quality Pass | UT-E3-010, UT-E3-011, E2E-E3-001 | Unit + E2E | Pending |
| AC-E3-009 | PRD Output Files | IT-E3-003, E2E-E3-001 | Integration + E2E | Pending |
| AC-E3-010 | PRD as Primary Input | UT-E3-012 | Unit | Pending |
| AC-E3-011 | Constraint Integration | UT-E3-013 | Unit | Pending |
| AC-E3-012 | CLAUDE.md Reference | UT-E3-014 | Unit | Pending |
| AC-E3-013 | Feature Branch | IT-E3-005, E2E-E3-002 | Integration + E2E | Pending |
| AC-E3-014 | CLI Implementation | IT-E3-006, E2E-E3-002 | Integration + E2E | Pending |
| AC-E3-015 | Git Commits | IT-E3-007, E2E-E3-002 | Integration + E2E | Pending |
| AC-E3-016 | Error Handling | IT-E3-008, IT-E3-009 | Integration | Pending |
| **Total** | **16 ACs** | **28 tests** | - | **All mapped** |

---

## Test Data Requirements

| Dataset | Purpose | Location |
|---------|---------|----------|
| `impact_report_sample.json` | AC-E3-001, AC-E3-002 composer tests | `tests/fixtures/` |
| `integration_plan_sample.json` | AC-E3-002 constraint tests | `tests/fixtures/` |
| `prd_high_quality.md` | AC-E3-008 pass test (verification score 88%) | `tests/fixtures/` |
| `prd_low_quality.md` | AC-E3-007 reject test (verification score 75%) | `tests/fixtures/` |
| `batch_findings/` | AC-E3-004 batch mode test (3 findings) | `tests/fixtures/` |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
*28 tests covering 16 acceptance criteria across 4 stories*
