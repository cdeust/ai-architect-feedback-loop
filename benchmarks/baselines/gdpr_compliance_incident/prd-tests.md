# Test Cases: Pipeline Feedback — Epic 4: Verification & Delivery

**Generated:** 2026-02-11
**Total Tests:** 34 tests
**Coverage:** 15 FRs + 4 NFRs → 19 ACs

---

## PART A: Coverage Tests

### A.1 Unit Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E4-001 | prompts/semantic_verification.md | Contains adversarial framing | AC-E4-001 |
| UT-E4-002 | prompts/semantic_verification.md | Contains cross-engine touchpoint checklist | AC-E4-002 |
| UT-E4-003 | prompts/semantic_verification.md | Contains anti-pattern criteria | AC-E4-003 |
| UT-E4-004 | compose_pr.py | Assembles all 6 audit trail sections | AC-E4-012 |
| UT-E4-005 | compose_pr.py | Uses `<details>` tags for collapsible sections | AC-E4-013 |
| UT-E4-006 | compose_pr.py | Includes pipeline metadata (run ID, duration) | AC-E4-012 |
| UT-E4-007 | compose_pr.py | Handles missing optional sections gracefully | AC-E4-012 |
| UT-E4-008 | retry state tracking | Attempt count increments correctly | AC-E4-008 |
| UT-E4-009 | retry state tracking | Failure details captured per attempt | AC-E4-009 |
| UT-E4-010 | failure issue content | Issue body includes finding details + attempt log | AC-E4-019 |

### A.2 Integration Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E4-001 | stage_7_semantic_verification.sh | Independent Claude Code CLI session invoked | AC-E4-004 |
| IT-E4-002 | stage_7_semantic_verification.sh | PRD + git diff provided as context | AC-E4-005 |
| IT-E4-003 | stage_7_semantic_verification.sh | verification_result.json produced | AC-E4-006 |
| IT-E4-004 | stage_7_semantic_verification.sh | Detects seeded misalignment | AC-E4-007 |
| IT-E4-005 | retry_orchestrator.sh | Retries on Stage 6 failure | AC-E4-008 |
| IT-E4-006 | retry_orchestrator.sh | Appends failure to next attempt prompt | AC-E4-009 |
| IT-E4-007 | retry_orchestrator.sh | Creates issue after 3 failures | AC-E4-010 |
| IT-E4-008 | retry_orchestrator.sh | Exits early on success (attempt 2) | AC-E4-011 |
| IT-E4-009 | stage_10_pull_request.sh | PR created via `gh pr create` | AC-E4-014 |
| IT-E4-010 | stage_10_pull_request.sh | Labels applied correctly | AC-E4-015 |
| IT-E4-011 | stage_10_pull_request.sh | `make sync-public` executes | AC-E4-016 |
| IT-E4-012 | stage_10_pull_request.sh | PR description contains metadata | AC-E4-017 |
| IT-E4-013 | failure issue creation | `gh issue create` invoked with labels | AC-E4-018 |
| IT-E4-014 | failure issue creation | Issue content has structured failure report | AC-E4-019 |

### A.3 End-to-End Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| E2E-E4-001 | Stage 7 full | PRD + branch → Claude Code → verification_result.json | All Stage 7 ACs |
| E2E-E4-002 | Retry flow success | Stage 6 fail → retry → Stage 5+6+7 pass on attempt 2 | AC-E4-008, AC-E4-011 |
| E2E-E4-003 | Retry flow exhaustion | 3 failures → GitHub issue created | AC-E4-008, AC-E4-010 |
| E2E-E4-004 | Stage 10 full | All outputs → PR composed → gh pr create → sync-public | All Stage 10 ACs |
| E2E-E4-005 | Full delivery | Stage 7 pass → Stage 8 → Stage 9 → Stage 10 → PR | All ACs |
| E2E-E4-006 | Stage 5→6→7 loop | Implementation → enforcement → verification chain | AC-E4-008 to AC-E4-011 |
| E2E-E4-007 | Misalignment catch | Seeded misalignment → Stage 7 detects → retry triggered | AC-E4-007, AC-E4-008 |
| E2E-E4-008 | Failure context append | Attempt 1 failure → attempt 2 prompt includes failure | AC-E4-009 |
| E2E-E4-009 | Failure → issue | All retries fail → issue created with full context | AC-E4-010, AC-E4-018, AC-E4-019 |
| E2E-E4-010 | PR completeness | All stage outputs → PR with all sections | AC-E4-012 to AC-E4-017 |

---

## PART C: AC-to-Test Traceability Matrix

| AC ID | AC Title | Test IDs | Test Type | Status |
|-------|----------|----------|-----------|--------|
| AC-E4-001 | Misalignment Focus | UT-E4-001 | Unit | Pending |
| AC-E4-002 | Cross-Engine Check | UT-E4-002 | Unit | Pending |
| AC-E4-003 | Anti-Patterns | UT-E4-003 | Unit | Pending |
| AC-E4-004 | Independent Session | IT-E4-001, E2E-E4-001 | Integration + E2E | Pending |
| AC-E4-005 | PRD + Diff Context | IT-E4-002, E2E-E4-001 | Integration + E2E | Pending |
| AC-E4-006 | Verification Result | IT-E4-003, E2E-E4-001 | Integration + E2E | Pending |
| AC-E4-007 | Misalignment Detection | IT-E4-004, E2E-E4-007 | Integration + E2E | Pending |
| AC-E4-008 | Retry Loop | UT-E4-008, IT-E4-005, E2E-E4-002, E2E-E4-006 | All | Pending |
| AC-E4-009 | Failure Append | UT-E4-009, IT-E4-006, E2E-E4-008 | All | Pending |
| AC-E4-010 | Exhaustion Handling | IT-E4-007, E2E-E4-003, E2E-E4-009 | Integration + E2E | Pending |
| AC-E4-011 | Success Path | IT-E4-008, E2E-E4-002 | Integration + E2E | Pending |
| AC-E4-012 | Complete Audit Trail | UT-E4-004, UT-E4-006, E2E-E4-010 | Unit + E2E | Pending |
| AC-E4-013 | Human-Readable | UT-E4-005 | Unit | Pending |
| AC-E4-014 | PR Creation | IT-E4-009, E2E-E4-004 | Integration + E2E | Pending |
| AC-E4-015 | PR Labels | IT-E4-010, E2E-E4-004 | Integration + E2E | Pending |
| AC-E4-016 | Public Sync | IT-E4-011, E2E-E4-004 | Integration + E2E | Pending |
| AC-E4-017 | PR Metadata | IT-E4-012, E2E-E4-010 | Integration + E2E | Pending |
| AC-E4-018 | Issue Creation | IT-E4-013, E2E-E4-009 | Integration + E2E | Pending |
| AC-E4-019 | Issue Content | UT-E4-010, IT-E4-014, E2E-E4-009 | All | Pending |
| **Total** | **19 ACs** | **34 tests** | - | **All mapped** |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
*34 tests covering 19 acceptance criteria across 6 stories*
