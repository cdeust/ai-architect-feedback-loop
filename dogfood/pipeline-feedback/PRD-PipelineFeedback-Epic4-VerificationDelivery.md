# PRD: Pipeline Feedback — Epic 4: Verification & Delivery

**Document Type:** Implementation-Level PRD (Focused Epic)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Parent PRD:** PRD-PipelineFeedback.md (Full Scope Overview)
**Epic:** 4 of 5 — Verification & Delivery
**Stages Covered:** 7, 10, Retry Logic
**Estimated Effort:** 42 SP (Fibonacci)
**License Tier:** Licensed (Full verification engine + all 15 strategies)

---

## 1. Overview

### 1.1 Epic Scope

Independent verification and PR creation. The verification agent is intentionally separate from the implementation agent to prevent self-confirming bias.

| Component | Stage | What It Delivers |
|-----------|-------|-----------------|
| Semantic Verification Prompt | Stage 7 | Prompt focused on finding misalignment (not confirming correctness) |
| Stage 7 Orchestrator | Stage 7 | Independent Claude Code CLI session for PRD-to-code verification |
| Retry Orchestrator | 5→6→7 | Manages Stage 5→6→7 loop with max 3 retries, appending failure context |
| PR Description Composer | Stage 10 | Assembles all stage outputs into structured PR description |
| Stage 10 Orchestrator | Stage 10 | Creates GitHub PR via `gh` CLI + runs `make sync-public` |
| Failure Issue Creator | Post-retry | Auto-creates GitHub issue after all retries exhausted |

### 1.2 Key Design Decision: Verification Independence

Stage 7 Claude Code session is **intentionally separate** from Stage 5 (implementation):
- Different session (no shared context)
- Prompt focused on **finding problems**, not confirming success
- Reads the PRD + git diff + integration plan independently
- Cannot see Stage 5's reasoning or intent

---

## 2. Goals & Success Metrics

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| EG-401 | Independent verification catches misalignment | No automated verification | Verification detects deliberate misalignment in test cases | Test with seeded misalignment |
| EG-402 | Retry logic handles transient failures | No retry mechanism | 80%+ of retryable failures succeed within 3 attempts | Retry success rate |
| EG-403 | PRs created with full audit trail | Manual PR creation | Automated PR with all stage outputs attached | PR description completeness |
| EG-404 | Failed pipelines create GitHub issues | No failure tracking | 100% of exhausted retries create issues | Issue creation rate |
| EG-405 | Public repo sync after PR creation | Manual sync | Automated `make sync-public` after PR | Sync execution |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement | Story |
|----|----------|-------------|-------|
| FR-E4-001 | P0 | Stage 7 prompt focused on finding misalignment between PRD spec and implementation | PIPE-E4-001 |
| FR-E4-002 | P0 | Stage 7 prompt verifies cross-engine integration completeness | PIPE-E4-001 |
| FR-E4-003 | P0 | Stage 7 prompt checks for anti-patterns: prohibited patterns, dead code, bolt-on detection | PIPE-E4-001 |
| FR-E4-004 | P0 | Stage 7 orchestrator invokes independent Claude Code CLI session with PRD + git diff + integration plan | PIPE-E4-002 |
| FR-E4-005 | P0 | Stage 7 produces `verification_result.json` with pass/fail, findings, and confidence | PIPE-E4-002 |
| FR-E4-006 | P0 | Retry orchestrator manages Stage 5→6→7 loop with max 3 attempts | PIPE-E4-003 |
| FR-E4-007 | P0 | Retry orchestrator appends failure details from previous attempt to next attempt's prompt | PIPE-E4-003 |
| FR-E4-008 | P0 | Retry orchestrator tracks attempt count and failure reasons | PIPE-E4-003 |
| FR-E4-009 | P0 | PR description composer assembles all stage outputs into structured markdown | PIPE-E4-004 |
| FR-E4-010 | P0 | PR description includes: impact report, integration plan, PRD summary, enforcement report, quality results | PIPE-E4-004 |
| FR-E4-011 | P0 | Stage 10 creates GitHub PR via `gh pr create` with correct labels | PIPE-E4-005 |
| FR-E4-012 | P0 | Stage 10 runs `make sync-public` after successful PR creation | PIPE-E4-005 |
| FR-E4-013 | P1 | Failure issue creator uses `gh issue create` with structured failure report | PIPE-E4-006 |
| FR-E4-014 | P1 | Failure issue includes: finding details, attempt count, per-attempt failure reasons, stage outputs | PIPE-E4-006 |
| FR-E4-015 | P1 | PR labels include `pipeline-generated`, `improvement`, and affected engine names | PIPE-E4-005 |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-E4-001 | P0 | Stage 7 execution time | < 15 minutes |
| NFR-E4-002 | P0 | Retry loop total time (3 attempts max) | < 90 minutes |
| NFR-E4-003 | P0 | Verification session independent of implementation session | No shared context |
| NFR-E4-004 | P1 | PR description readable by human reviewer | Structured markdown |

---

## 4. User Stories & Acceptance Criteria

### PIPE-E4-001: Semantic Verification Prompt Template [5 SP]

**As a** Claude Code session (Stage 7),
**I want** a prompt focused on finding misalignment between PRD and code,
**So that** verification catches issues the implementation session missed.

**AC-E4-001:** Misalignment Detection Focus
- [ ] GIVEN prompt template WHEN reviewed THEN focuses on finding problems (not confirming correctness)

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Adversarial verification tone |
| Measurement | Prompt content review |
| Business Impact | EG-401: catch misalignment |

**AC-E4-002:** Cross-Engine Verification
- [ ] GIVEN prompt WHEN assembled THEN includes integration plan touchpoints to verify

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All touchpoints checkable |
| Measurement | Prompt contains touchpoint list |
| Business Impact | FR-E4-002: cross-engine check |

**AC-E4-003:** Anti-Pattern Detection
- [ ] GIVEN prompt WHEN assembled THEN includes prohibited pattern rules and bolt-on detection criteria

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All anti-patterns in prompt |
| Measurement | Pattern list in prompt |
| Business Impact | FR-E4-003: anti-pattern check |

**Tasks:**
- [ ] Write `prompts/semantic_verification.md`
- [ ] Include adversarial framing ("find what's wrong, not what's right")
- [ ] Include cross-engine touchpoint checklist
- [ ] Include anti-pattern detection criteria
- [ ] Include output schema requirement (verification_result.json)

---

### PIPE-E4-002: Stage 7 Semantic Verification Orchestrator [8 SP]

**As a** pipeline verifier,
**I want** an independent Claude Code CLI session checking PRD-to-code alignment,
**So that** implementation quality is validated by a separate agent.

**AC-E4-004:** Independent Session
- [ ] GIVEN implementation complete on branch WHEN Stage 7 runs THEN uses separate Claude Code CLI session (no shared history with Stage 5)

| Metric | Value |
|--------|-------|
| Baseline | No automated verification |
| Target | Independent session confirmed |
| Measurement | Session isolation check |
| Business Impact | NFR-E4-003: independence |

**AC-E4-005:** PRD + Diff Context
- [ ] GIVEN feature branch with changes WHEN Stage 7 runs THEN Claude Code receives PRD + `git diff main..HEAD` + integration plan

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Full context provided |
| Measurement | Session context files |
| Business Impact | FR-E4-004: complete context |

**AC-E4-006:** Verification Result
- [ ] GIVEN verification complete WHEN result captured THEN `verification_result.json` contains pass/fail, findings list, confidence score

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Structured result |
| Measurement | JSON Schema validation |
| Business Impact | FR-E4-005: structured output |

**AC-E4-007:** Misalignment Detection
- [ ] GIVEN code that intentionally misses a PRD requirement WHEN Stage 7 verifies THEN reports the missing requirement

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Detects seeded misalignment |
| Measurement | Test with deliberate omission |
| Business Impact | EG-401: catch misalignment |

**Tasks:**
- [ ] Implement `stage_7_semantic_verification.sh`
- [ ] Generate `git diff main..HEAD` for context
- [ ] Assemble prompt with PRD + diff + plan
- [ ] Invoke Claude Code CLI (independent session)
- [ ] Extract verification result JSON
- [ ] Add timeout (15 min)

---

### PIPE-E4-003: Retry Orchestrator [8 SP]

**As a** pipeline resilience mechanism,
**I want** Stage 5→6→7 retried up to 3 times with failure context,
**So that** transient failures don't waste an entire pipeline run.

**AC-E4-008:** Retry Loop
- [ ] GIVEN Stage 6 fails on first attempt WHEN retry orchestrator runs THEN retries Stage 5→6→7 (max 3 attempts)

| Metric | Value |
|--------|-------|
| Baseline | No retry mechanism |
| Target | Up to 3 attempts |
| Measurement | Attempt count in log |
| Business Impact | FR-E4-006: retry logic |

**AC-E4-009:** Failure Context Append
- [ ] GIVEN attempt 1 fails with "Gate 1: prohibited pattern in file X" WHEN attempt 2 starts THEN implementation prompt includes previous failure details

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Failure details in next prompt |
| Measurement | Prompt content inspection |
| Business Impact | FR-E4-007: failure learning |

**AC-E4-010:** Exhaustion Handling
- [ ] GIVEN 3 failed attempts WHEN retry orchestrator detects exhaustion THEN triggers failure issue creation and exits cleanly

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Issue created after 3 failures |
| Measurement | GitHub issue existence |
| Business Impact | FR-E4-008: failure tracking |

**AC-E4-011:** Success Path
- [ ] GIVEN attempt 2 passes all stages WHEN retry loop completes THEN reports success and continues to Stage 8

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Early exit on success |
| Measurement | Exit code 0 after pass |
| Business Impact | TG-001: pipeline completion |

**Tasks:**
- [ ] Implement `retry_orchestrator.sh`
- [ ] Track attempt count (1-3)
- [ ] Capture failure details per attempt (gate name, message, affected files)
- [ ] Append failure context to Stage 5 prompt on retry
- [ ] Handle each retry branch (reset or new branch)
- [ ] Trigger failure issue creation on exhaustion
- [ ] Clean exit on success

---

### PIPE-E4-004: PR Description Composer [5 SP]

**As a** human PR reviewer,
**I want** a structured PR description with full audit trail,
**So that** I can review the automated improvement with complete context.

**AC-E4-012:** Complete Audit Trail
- [ ] GIVEN all stage outputs WHEN composer runs THEN PR description includes: finding summary, impact analysis, integration plan, PRD summary, enforcement report, quality comparison

| Metric | Value |
|--------|-------|
| Baseline | Manual PR description |
| Target | All stage sections present |
| Measurement | Section count in output |
| Business Impact | FR-E4-009, FR-E4-010: full trail |

**AC-E4-013:** Human-Readable Format
- [ ] GIVEN composed PR description WHEN rendered on GitHub THEN structured markdown with collapsible sections for detailed outputs

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Readable on GitHub |
| Measurement | Markdown rendering test |
| Business Impact | NFR-E4-004: readable PRs |

**Tasks:**
- [ ] Implement `compose_pr.py`
- [ ] Read all stage outputs from run directory
- [ ] Compose markdown with sections: Summary, Impact Analysis, Integration Plan, PRD (collapsed), Enforcement Results, Quality Gate Results
- [ ] Use `<details>` tags for collapsible sections
- [ ] Add pipeline metadata (run ID, duration, retry count)

---

### PIPE-E4-005: Stage 10 Pull Request Creation [8 SP]

**As a** pipeline delivery mechanism,
**I want** automated PR creation with labels and public repo sync,
**So that** improvements are ready for human review and public distribution.

**AC-E4-014:** PR Creation
- [ ] GIVEN composed PR description and feature branch WHEN Stage 10 runs THEN `gh pr create` produces a PR on the private repo

| Metric | Value |
|--------|-------|
| Baseline | Manual PR creation |
| Target | Automated via `gh` CLI |
| Measurement | PR URL in output |
| Business Impact | FR-E4-011: automated PR |

**AC-E4-015:** PR Labels
- [ ] GIVEN PR creation WHEN labels applied THEN includes `pipeline-generated`, `improvement`, and engine names

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Correct labels applied |
| Measurement | `gh pr view --json labels` |
| Business Impact | FR-E4-015: PR labeling |

**AC-E4-016:** Public Repo Sync
- [ ] GIVEN PR created successfully WHEN Stage 10 continues THEN `make sync-public` executes

| Metric | Value |
|--------|-------|
| Baseline | Manual sync |
| Target | Automated after PR |
| Measurement | sync-public exit code |
| Business Impact | FR-E4-012: auto-sync |

**AC-E4-017:** PR Metadata
- [ ] GIVEN PR created WHEN viewed THEN description contains pipeline run ID, finding ID, and stage outputs

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Full metadata in PR |
| Measurement | PR description content |
| Business Impact | EG-403: audit trail |

**Tasks:**
- [ ] Implement `stage_10_pull_request.sh`
- [ ] Invoke `compose_pr.py` for description
- [ ] Call `gh pr create --base main --head $BRANCH --title "..." --body "..." --label "..."`
- [ ] Run `make sync-public` after PR creation
- [ ] Log PR URL and number
- [ ] Handle sync-public failure gracefully (PR still created)

---

### PIPE-E4-006: Failure Issue Creator [3 SP]

**As a** pipeline operator,
**I want** automated GitHub issue creation after all retries fail,
**So that** failed improvements are tracked for manual investigation.

**AC-E4-018:** Issue Creation
- [ ] GIVEN 3 failed retry attempts WHEN failure handler runs THEN `gh issue create` produces an issue

| Metric | Value |
|--------|-------|
| Baseline | No failure tracking |
| Target | Issue created automatically |
| Measurement | Issue URL in output |
| Business Impact | FR-E4-013: failure tracking |

**AC-E4-019:** Issue Content
- [ ] GIVEN failure issue WHEN viewed THEN includes: finding details, attempt count, per-attempt failure reasons

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Structured failure report |
| Measurement | Issue content |
| Business Impact | FR-E4-014: failure details |

**Tasks:**
- [ ] Implement failure issue creation in `retry_orchestrator.sh`
- [ ] Compose issue body with finding context, attempt log, suggested manual actions
- [ ] Add `pipeline-failure` and `needs-investigation` labels
- [ ] Log issue URL

---

## 5. Technical Specification

### 5.1 Data Schemas

#### verification_result.json (Stage 7 Output)

```json
{
  "stage": "semantic_verification",
  "timestamp": "2026-02-11T22:25:00Z",
  "overall_result": "PASS",
  "confidence": 0.87,
  "findings": [
    {
      "severity": "INFO",
      "category": "completeness",
      "description": "All PRD requirements traced to code changes",
      "evidence": "FR-001 → ContextualBM25.swift:42"
    }
  ],
  "prd_alignment_score": 0.92,
  "cross_engine_verification": {
    "touchpoints_verified": 3,
    "touchpoints_total": 3,
    "result": "PASS"
  },
  "anti_patterns_detected": []
}
```

#### Retry State

```json
{
  "finding_id": "tv-20260211-001",
  "max_attempts": 3,
  "current_attempt": 2,
  "attempts": [
    {
      "attempt": 1,
      "timestamp": "2026-02-11T22:15:00Z",
      "failed_stage": "stage_6",
      "failed_gate": "gate_1",
      "failure_reason": "Prohibited pattern 'TODO' found in packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift:42",
      "files_affected": ["packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift"]
    }
  ]
}
```

### 5.2 Retry Logic Flow

```
attempt = 1
while attempt <= 3:
    run Stage 5 (implementation) with failure context from previous attempts
    run Stage 6 (enforcement)
    if Stage 6 fails:
        log failure, increment attempt, continue
    run Stage 7 (verification)
    if Stage 7 fails:
        log failure, increment attempt, continue
    break (success)

if attempt > 3:
    create GitHub issue
    exit 1
else:
    proceed to Stage 8
```

---

## 6. Implementation Roadmap

### Sprint 1 (Week 1-2): Verification [13 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E4-001: Verification Prompt | 5 | Epic 3 (PRD output) |
| PIPE-E4-002: Stage 7 Orchestrator | 8 | Prompt template |

### Sprint 2 (Week 3-4): Retry + Delivery [29 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E4-003: Retry Orchestrator | 8 | Stage 7 |
| PIPE-E4-004: PR Composer | 5 | All stage outputs |
| PIPE-E4-005: Stage 10 PR Creation | 8 | PR composer |
| PIPE-E4-006: Failure Issue Creator | 3 | Retry orchestrator |
| Integration testing | 5 | All stories |

### Summary

| Sprint | SP | Theme |
|--------|----|-------|
| Sprint 1 | 13 | Independent verification |
| Sprint 2 | 29 | Retry + PR + delivery |
| **Total** | **42** | **4 weeks** |

---

## 7. Open Questions

| ID | Question | Impact | Decision By |
|----|----------|--------|-------------|
| OQ-E4-001 | Should retry reset the branch or amend commits? | Branch management | Sprint 2 |
| OQ-E4-002 | Should Stage 7 have veto power or just advisory? | Verification strictness | Sprint 1 |
| OQ-E4-003 | Should `make sync-public` failure block PR creation? | Delivery policy | Sprint 2 |

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Focused Epic — Verification & Delivery)*
*Fibonacci story points: 42 SP across 6 stories, 2 sprints*
