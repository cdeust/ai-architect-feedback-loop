# JIRA Tickets: Pipeline Feedback — Epic 2: Intelligence Layer

**Generated:** 2026-02-11
**Total Story Points:** 58 SP
**Estimated Duration:** 8 weeks (1 developer, 4 sprints)
**Parent PRD:** PRD-PipelineFeedback-Epic2-IntelligenceLayer.md

---

## Epic: Intelligence Layer [58 SP]

**Description:** Build Claude Code CLI session orchestration for cross-engine impact analysis and integration design. This is where bolt-on features get rejected.

---

### PIPE-E2-001: Write Stage 2 Impact Analysis Prompt Template
**Type:** Story | **Priority:** P0 | **SP:** 8 | **Sprint:** 1

**Description:**
As a Claude Code session (Stage 2),
I want a structured prompt with engine graph context and scoring instructions,
So that impact analysis traces cross-engine propagation paths accurately.

**Acceptance Criteria:**
- [ ] AC-E2-001: Engine graph embedded in prompt context (9 engines, all relationships)
- [ ] AC-E2-002: Propagation tracing instructions for first/second-order paths
- [ ] AC-E2-003: Output matches impact_report.json schema

**Tasks:**
- [ ] Write `prompts/impact_analysis.md`
- [ ] Include compound scoring formula
- [ ] Include propagation tracing instructions
- [ ] Include few-shot example
- [ ] Manual test with 3 sample findings

**Dependencies:** PIPE-E2-008 (contract extractor for context)
**Labels:** pipeline, stage-2, prompt, p0

---

### PIPE-E2-002: Build Stage 2 Impact Analysis Orchestrator
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 2

**Description:**
As a pipeline orchestrator,
I want a shell script that invokes Claude Code CLI for impact analysis,
So that findings are analyzed for cross-engine impact automatically.

**Acceptance Criteria:**
- [ ] AC-E2-004: Claude Code CLI invoked with prompt + context
- [ ] AC-E2-005: impact_report.json written to run directory
- [ ] AC-E2-006: Error handling for CLI failures

**Tasks:**
- [ ] Implement `stage_2_impact_analysis.sh`
- [ ] Assemble prompt from template + finding + graph
- [ ] Invoke claude CLI, extract JSON output
- [ ] Add timeout handling (15 min default)

**Dependencies:** PIPE-E2-001 (prompt template)
**Labels:** pipeline, stage-2, orchestrator, bash, p0

---

### PIPE-E2-003: Build Stage 2 Impact Report Validator
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 2

**Description:**
As a pipeline quality enforcer,
I want deterministic validation of impact reports,
So that single-engine findings are rejected.

**Acceptance Criteria:**
- [ ] AC-E2-007: engines_affected < 2 → REJECTED
- [ ] AC-E2-008: compound_score < 0.3 → REJECTED
- [ ] AC-E2-009: Valid report → ACCEPTED
- [ ] AC-E2-010: Rejection includes reason + values

**Tasks:**
- [ ] Implement `validate_impact_report.sh`
- [ ] Parse JSON for thresholds
- [ ] Compare against config values
- [ ] Generate rejection report
- [ ] Unit tests for accept/reject

**Dependencies:** PIPE-E2-002 (orchestrator for test data)
**Labels:** pipeline, stage-2, validator, bash, p0

---

### PIPE-E2-004: Write Stage 3 Integration Design Prompt Template
**Type:** Story | **Priority:** P0 | **SP:** 8 | **Sprint:** 3

**Description:**
As a Claude Code session (Stage 3),
I want a structured prompt with engine contracts and anti-bolt-on rules,
So that integration plans specify exact modifications within existing architecture.

**Acceptance Criteria:**
- [ ] AC-E2-011: Anti-bolt-on rules in prompt (no new packages, no standalone modules)
- [ ] AC-E2-012: Engine contracts embedded from extractor output
- [ ] AC-E2-013: File-level specificity required in output

**Tasks:**
- [ ] Write `prompts/integration_design.md`
- [ ] Include CLAUDE.md port/adapter references
- [ ] Include few-shot example plan
- [ ] Manual test with 3 sample impact reports

**Dependencies:** PIPE-E2-003 (Stage 2 output for context)
**Labels:** pipeline, stage-3, prompt, p0

---

### PIPE-E2-005: Build Stage 3 Integration Design Orchestrator
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 3

**Description:**
As a pipeline orchestrator,
I want a shell script that invokes Claude Code CLI for integration design,
So that accepted findings get concrete implementation plans.

**Acceptance Criteria:**
- [ ] AC-E2-014: Claude Code CLI invoked with impact report + contracts
- [ ] AC-E2-015: integration_plan.json written to run directory

**Tasks:**
- [ ] Implement `stage_3_integration_design.sh`
- [ ] Assemble prompt from template + impact report + contracts
- [ ] Invoke claude CLI, extract JSON
- [ ] Add timeout handling

**Dependencies:** PIPE-E2-004 (prompt template)
**Labels:** pipeline, stage-3, orchestrator, bash, p0

---

### PIPE-E2-006: Build Stage 3 Integration Plan Validator
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 3

**Description:**
As a pipeline quality enforcer,
I want deterministic validation rejecting bolt-on integration plans.

**Acceptance Criteria:**
- [ ] AC-E2-016: New non-test files → REJECTED
- [ ] AC-E2-017: Missing engine touchpoints → REJECTED
- [ ] AC-E2-018: Zero cross-engine connections → REJECTED
- [ ] AC-E2-019: Valid plan → ACCEPTED

**Tasks:**
- [ ] Implement `validate_integration_plan.sh`
- [ ] Check for new non-test files
- [ ] Verify all referenced engines have modifications
- [ ] Verify cross-engine connections >= 2
- [ ] Generate validation report
- [ ] Unit tests

**Dependencies:** PIPE-E2-005 (orchestrator for test data)
**Labels:** pipeline, stage-3, validator, bash, p0

---

### PIPE-E2-007: Build Manifest Generator
**Type:** Story | **Priority:** P0 | **SP:** 5 | **Sprint:** 4

**Description:**
As a Stage 6 enforcement gate,
I want manifest.json derived from the integration plan,
So that Gate 2 can enforce file constraints deterministically.

**Acceptance Criteria:**
- [ ] AC-E2-020: Valid manifest from integration_plan.json
- [ ] AC-E2-021: must_change matches plan files
- [ ] AC-E2-022: must_not_change includes unaffected critical files

**Tasks:**
- [ ] Implement `generate_manifest.py`
- [ ] Derive must_change from plan
- [ ] Derive must_not_change from unaffected engines
- [ ] Derive allowed_new_files (test files only)
- [ ] Unit tests

**Dependencies:** PIPE-E2-006 (validated plan)
**Labels:** pipeline, manifest, python, p0

---

### PIPE-E2-008: Build Engine Contract Extractor
**Type:** Story | **Priority:** P1 | **SP:** 8 | **Sprint:** 1

**Description:**
As a prompt assembler,
I want engine contracts extracted from Swift source,
So that prompts contain accurate API signatures.

**Acceptance Criteria:**
- [ ] AC-E2-023: Protocol extraction (name, methods, parameters)
- [ ] AC-E2-024: All public/open declarations captured
- [ ] AC-E2-025: Markdown output for prompt injection

**Tasks:**
- [ ] Implement `extract_contracts.py`
- [ ] Regex-based Swift parsing
- [ ] Group by engine package
- [ ] Markdown output format
- [ ] Unit tests with mock Swift files

**Dependencies:** Epic 1 (engine graph for package paths)
**Labels:** pipeline, contracts, python, p1

---

### PIPE-E2-009: Calibrate Compound Scoring Formula
**Type:** Story | **Priority:** P1 | **SP:** 5 | **Sprint:** 1

**Description:**
As a pipeline operator,
I want calibrated compound scoring,
So that the 0.3 threshold is meaningful.

**Acceptance Criteria:**
- [ ] AC-E2-026: Formula produces correct results for known inputs
- [ ] AC-E2-027: > 80% agreement with 10+ manual decisions

**Tasks:**
- [ ] Document formula
- [ ] Collect 10+ historical decisions
- [ ] Compute scores, measure agreement
- [ ] Adjust weights if needed
- [ ] Update thresholds.json

**Dependencies:** None
**Labels:** pipeline, calibration, p1

---

## Summary

| Sprint | Stories | Story Points | Theme |
|--------|---------|-------------|-------|
| Sprint 1 (Wk 1-2) | E2-008, E2-001, E2-009 | 21 | Prompts + contracts + calibration |
| Sprint 2 (Wk 3-4) | E2-002, E2-003 | 10 | Stage 2 end-to-end |
| Sprint 3 (Wk 5-6) | E2-004, E2-005, E2-006 | 18 | Stage 3 end-to-end |
| Sprint 4 (Wk 7-8) | E2-007 + integration testing | 9 | Manifest + polish |
| **Total** | **9** | **58** | **4 sprints, 8 weeks** |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
