# PRD: Pipeline Feedback — Epic 3: Dogfood & Implementation

**Document Type:** Implementation-Level PRD (Focused Epic)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Parent PRD:** PRD-PipelineFeedback.md (Full Scope Overview)
**Epic:** 3 of 5 — Dogfood & Implementation
**Stages Covered:** 4, 5
**Estimated Effort:** 34 SP (Fibonacci)
**License Tier:** Licensed (Full verification engine + all 15 strategies)

---

## 1. Overview

### 1.1 Epic Scope

The self-improving loop. The AI-PRD Generator writes its own upgrade PRD (dogfood), then a Claude Code CLI session implements it. This is where the product improves itself.

| Component | Stage | What It Delivers |
|-----------|-------|-----------------|
| PRD Input Composer | Stage 4 | Assembles finding + integration plan + contracts into coherent PRD input |
| Stage 4 Dogfood Orchestrator | Stage 4 | Invokes AI-PRD Generator via SKILL.md and Swift library |
| Quality Threshold Check | Stage 4 | Rejects PRDs with verification score < 80% |
| Implementation Prompt | Stage 5 | Structured prompt with PRD + integration plan + manifest + CLAUDE.md |
| Stage 5 Orchestrator | Stage 5 | Creates feature branch, invokes Claude Code CLI for implementation |

### 1.2 Dependencies on Epic 2

| Epic 2 Deliverable | Used By | How |
|--------------------|---------|-----|
| `impact_report.json` | PRD input composer | Finding context for PRD generation |
| `integration_plan.json` | PRD input composer + implementation prompt | Design constraints for both stages |
| `manifest.json` | Implementation prompt | Hard limits for Stage 5 session |
| Engine contract extractions | PRD input composer | Technical context |

---

## 2. Goals & Success Metrics

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| EG-301 | Product specs its own upgrades | Manual PRD writing (~4-8 hours) | Automated PRD generation (< 30 min) | Stage 4 execution time |
| EG-302 | PRD quality from self-spec meets threshold | N/A | >= 80% verification score | PRD verification report |
| EG-303 | Implementation produces compilable code | Manual implementation (~days) | Automated implementation (< 30 min) | Stage 5 execution + build pass |
| EG-304 | Implementation respects manifest constraints | No automated enforcement | 100% manifest compliance | Stage 6 Gate 2 (Epic 1) |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement | Story |
|----|----------|-------------|-------|
| FR-E3-001 | P0 | PRD input composer assembles finding description + integration plan + engine contracts into a coherent PRD input document | PIPE-E3-001 |
| FR-E3-002 | P0 | PRD input includes Technical Veil finding context (title, description, source URL, relevance) | PIPE-E3-001 |
| FR-E3-003 | P0 | PRD input includes integration plan constraints (affected engines, cross-engine touchpoints, file changes) | PIPE-E3-001 |
| FR-E3-004 | P0 | Stage 4 invokes AI-PRD Generator via SKILL.md prompt flow (Claude Code CLI session) | PIPE-E3-002 |
| FR-E3-005 | P0 | Stage 4 invokes AI-PRD Generator via Swift library direct invocation | PIPE-E3-002 |
| FR-E3-006 | P0 | Stage 4 validates PRD output quality: verification score >= 80% | PIPE-E3-002 |
| FR-E3-007 | P0 | Stage 4 rejects PRDs with quality score < 80% and logs rejection | PIPE-E3-002 |
| FR-E3-008 | P0 | Stage 4 writes upgrade PRD and all 4 companion files to run directory | PIPE-E3-002 |
| FR-E3-009 | P0 | Implementation prompt template includes PRD as primary input | PIPE-E3-003 |
| FR-E3-010 | P0 | Implementation prompt includes integration plan as design constraints | PIPE-E3-003 |
| FR-E3-011 | P0 | Implementation prompt includes manifest as hard limits (must-change, must-not-change) | PIPE-E3-003 |
| FR-E3-012 | P0 | Implementation prompt references CLAUDE.md for port/adapter pattern enforcement | PIPE-E3-003 |
| FR-E3-013 | P0 | Stage 5 creates a feature branch (`pipeline/improvement-<finding_id>`) before implementation | PIPE-E3-004 |
| FR-E3-014 | P0 | Stage 5 invokes Claude Code CLI session with implementation prompt and all context files | PIPE-E3-004 |
| FR-E3-015 | P0 | Stage 5 implementation session produces git commits on the feature branch | PIPE-E3-004 |
| FR-E3-016 | P1 | PRD input composer supports batch mode (multiple findings → multiple PRD inputs) | PIPE-E3-001 |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-E3-001 | P0 | Stage 4 + Stage 5 combined execution time | < 60 minutes per finding |
| NFR-E3-002 | P0 | Feature branch naming convention consistent | `pipeline/improvement-<finding_id>` |
| NFR-E3-003 | P0 | Implementation session respects CLAUDE.md rules | Port/adapter pattern enforced |
| NFR-E3-004 | P1 | PRD input composition time | < 30 seconds |

---

## 4. User Stories & Acceptance Criteria

### PIPE-E3-001: PRD Input Composer [8 SP]

**As a** Stage 4 dogfood orchestrator,
**I want** a coherent PRD input assembled from pipeline artifacts,
**So that** the AI-PRD Generator receives well-structured upgrade specifications.

**AC-E3-001:** Finding Context Assembly
- [ ] GIVEN `impact_report.json` with finding details WHEN composer runs THEN output includes finding title, description, source URL, relevance category

| Metric | Value |
|--------|-------|
| Baseline | Manual: ~30 min to assemble context |
| Target | Automated: < 30 seconds |
| Measurement | Composition time |
| Business Impact | BG-004: 0 hours manual spec |

**AC-E3-002:** Integration Constraints
- [ ] GIVEN `integration_plan.json` WHEN composer runs THEN output includes affected engines, cross-engine touchpoints, and file change list

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All plan constraints in output |
| Measurement | Content validation |
| Business Impact | EG-304: manifest compliance |

**AC-E3-003:** Output Format
- [ ] GIVEN all input artifacts WHEN composer runs THEN produces markdown document suitable for AI-PRD Generator input

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid markdown with structured sections |
| Measurement | Markdown parsing + section count |
| Business Impact | EG-301: automated spec |

**AC-E3-004:** Batch Mode
- [ ] GIVEN 3 findings WHEN composer runs in batch mode THEN produces 3 separate PRD input documents

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 1 document per finding |
| Measurement | Output file count |
| Business Impact | FR-E3-016: batch support |

**Tasks:**
- [ ] Implement `compose_prd_input.py` with argparse
- [ ] Read impact_report.json and integration_plan.json
- [ ] Extract engine contracts from extractor output
- [ ] Compose structured markdown with sections: Context, Finding, Affected Engines, Integration Constraints, Implementation Guidelines
- [ ] Support `--batch` flag for multiple findings
- [ ] Add unit tests for all AC scenarios

---

### PIPE-E3-002: Stage 4 Dogfood Orchestrator [13 SP]

**As a** pipeline self-improvement engine,
**I want** the AI-PRD Generator to spec its own upgrade,
**So that** each improvement has a verified, production-ready PRD.

**AC-E3-005:** SKILL.md Path Execution
- [ ] GIVEN PRD input document WHEN Stage 4 runs SKILL.md path THEN Claude Code CLI invokes SKILL.md prompt and produces 4 PRD files

| Metric | Value |
|--------|-------|
| Baseline | Manual PRD writing: 4-8 hours |
| Target | Automated: < 20 minutes |
| Measurement | Execution time + file count |
| Business Impact | BG-004: 0 hours manual spec |

**AC-E3-006:** Library Path Execution
- [ ] GIVEN PRD input document WHEN Stage 4 runs library path THEN Swift library produces PRD output

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Library produces output |
| Measurement | File existence |
| Business Impact | FR-E3-005: both paths |

**AC-E3-007:** Quality Threshold Enforcement
- [ ] GIVEN PRD with verification score 75% WHEN quality check runs THEN PRD REJECTED with "quality score 75% < threshold 80%"

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% below-threshold PRDs rejected |
| Measurement | Rejection on test PRD |
| Business Impact | EG-302: quality threshold |

**AC-E3-008:** Quality Pass
- [ ] GIVEN PRD with verification score 88% WHEN quality check runs THEN PRD ACCEPTED and written to run directory

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid PRDs pass |
| Measurement | Exit code 0 + files written |
| Business Impact | TG-001: pipeline completion |

**AC-E3-009:** PRD Output Files
- [ ] GIVEN successful generation WHEN Stage 4 completes THEN run directory contains: upgrade PRD, verification report, JIRA tickets, test cases

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 4 files in prd_output/ |
| Measurement | File count in run directory |
| Business Impact | FR-E3-008: all files written |

**Tasks:**
- [ ] Implement `stage_4_dogfood.sh`
- [ ] SKILL.md path: invoke Claude Code CLI with SKILL.md + PRD input
- [ ] Library path: invoke Swift library CLI with PRD input
- [ ] Extract verification score from output
- [ ] Implement quality threshold check (configurable via thresholds.json)
- [ ] Write all output files to `$RUN_DIR/prd_output/`
- [ ] Add structured logging
- [ ] Add timeout handling (default: 20 min per path)

---

### PIPE-E3-003: Implementation Prompt Template [5 SP]

**As a** Claude Code session (Stage 5),
**I want** a structured prompt with PRD, integration plan, manifest, and CLAUDE.md references,
**So that** implementation follows the spec precisely within architectural constraints.

**AC-E3-010:** PRD as Primary Input
- [ ] GIVEN implementation prompt WHEN reviewed THEN upgrade PRD is embedded as primary context with all sections

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Full PRD in prompt |
| Measurement | Template review |
| Business Impact | FR-E3-009: PRD-driven implementation |

**AC-E3-011:** Constraint Integration
- [ ] GIVEN prompt template WHEN assembled THEN includes integration plan constraints and manifest limits

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All constraints in prompt |
| Measurement | Template review |
| Business Impact | FR-E3-010, FR-E3-011 |

**AC-E3-012:** CLAUDE.md Reference
- [ ] GIVEN prompt template WHEN reviewed THEN references CLAUDE.md port/adapter pattern rules

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | CLAUDE.md referenced |
| Measurement | Template content check |
| Business Impact | NFR-E3-003: pattern enforcement |

**Tasks:**
- [ ] Write `prompts/implementation.md` with sections: PRD Context, Integration Plan, Manifest Constraints, Architectural Rules, Implementation Instructions, Output Expectations
- [ ] Include CLAUDE.md references for dependency rules
- [ ] Include manifest file as hard constraints section
- [ ] Include example of expected git workflow (branch, commit, test)

---

### PIPE-E3-004: Stage 5 Implementation Orchestrator [8 SP]

**As a** pipeline implementer,
**I want** a Claude Code CLI session that implements the upgrade on a feature branch,
**So that** code changes follow the PRD spec and respect all constraints.

**AC-E3-013:** Feature Branch Creation
- [ ] GIVEN finding with id `tv-20260211-001` WHEN Stage 5 starts THEN creates branch `pipeline/improvement-tv-20260211-001`

| Metric | Value |
|--------|-------|
| Baseline | Manual branch creation |
| Target | Automated branch with consistent naming |
| Measurement | `git branch` output |
| Business Impact | NFR-E3-002: naming convention |

**AC-E3-014:** Claude Code CLI Implementation Session
- [ ] GIVEN implementation prompt with all context WHEN Claude Code session runs THEN produces code changes on feature branch

| Metric | Value |
|--------|-------|
| Baseline | Manual implementation: days |
| Target | Automated: < 30 minutes |
| Measurement | Session completion + git diff |
| Business Impact | EG-303: automated implementation |

**AC-E3-015:** Git Commits Produced
- [ ] GIVEN successful implementation WHEN session completes THEN at least 1 commit exists on feature branch

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | >= 1 commit on feature branch |
| Measurement | `git log` on branch |
| Business Impact | FR-E3-015: git commits |

**AC-E3-016:** Error Handling
- [ ] GIVEN Claude Code session fails (timeout, crash) WHEN orchestrator detects failure THEN logs error, preserves branch state, exits with code 1

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Clean failure handling |
| Measurement | Exit code + log + branch state |
| Business Impact | TG-001: pipeline completion |

**Tasks:**
- [ ] Implement `stage_5_implementation.sh`
- [ ] Create feature branch from current HEAD
- [ ] Assemble implementation prompt with all context files
- [ ] Invoke Claude Code CLI with prompt
- [ ] Verify commits on branch after session
- [ ] Add timeout handling (default: 30 min)
- [ ] Add structured logging
- [ ] Handle branch cleanup on failure (leave branch for manual inspection)

---

## 5. Technical Specification

### 5.1 PRD Input Document Format

```markdown
# Upgrade Specification: [Finding Title]

## Finding Context
- **ID:** tv-20260211-001
- **Source:** [Technical Veil]
- **Relevance:** retrieval (score: 0.87)
- **Description:** [Full finding description]

## Impact Analysis Summary
- **Engines Affected:** RAGEngine, VerificationEngine, MetaPromptingEngine
- **Compound Score:** 0.65
- **Propagation Depth:** 2

## Integration Constraints
### Files to Modify
- `packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift`
- `packages/AIPRDVerificationEngine/Sources/Claims/ClaimDecomposer.swift`

### Cross-Engine Touchpoints
- RAGEngine → VerificationEngine: RAG output feeds claim decomposition
- RAGEngine → MetaPromptingEngine: RAG chunks inform template selection

### Contract Changes
- RetrievalPort.search(query:context:) — Add contextWeight parameter

## Engine Contracts (Current)
[Extracted protocol definitions for affected engines]

## Implementation Guidelines
- Follow CLAUDE.md port/adapter pattern
- No new packages or standalone modules
- Modifications to existing files only (except test files)
- All changes must compile and pass existing tests
```

### 5.2 Stage 5 Git Workflow

```bash
# Stage 5 orchestrator workflow
FINDING_ID="tv-20260211-001"
BRANCH="pipeline/improvement-$FINDING_ID"

# 1. Create feature branch
git checkout -b "$BRANCH"

# 2. Invoke Claude Code CLI
claude --context "$CONTEXT_DIR" \
       --max-turns 20 \
       --prompt "$(cat prompts/implementation.md)"

# 3. Verify commits
COMMIT_COUNT=$(git rev-list --count HEAD ^main)
if [ "$COMMIT_COUNT" -eq 0 ]; then
    log "ERROR" "No commits produced by implementation session"
    exit 1
fi

# 4. Log success
log "INFO" "Implementation complete: $COMMIT_COUNT commits on $BRANCH"
```

---

## 6. Implementation Roadmap

### Sprint 1 (Week 1-2): Composition & PRD Generation [21 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E3-001: PRD Input Composer | 8 | Epic 2 output schemas |
| PIPE-E3-002: Stage 4 Dogfood Orchestrator | 13 | PRD input composer |

**Sprint Goal:** Pipeline generates upgrade PRDs from findings with quality enforcement.

### Sprint 2 (Week 3-4): Implementation [13 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E3-003: Implementation Prompt Template | 5 | Stage 4 output |
| PIPE-E3-004: Stage 5 Implementation Orchestrator | 8 | Prompt template |

**Sprint Goal:** Full Stage 4 → Stage 5 pipeline operational — finding → PRD → code.

### Summary

| Sprint | SP | Cumulative | Theme |
|--------|----|-----------|-------|
| Sprint 1 | 21 | 21 | PRD composition + dogfood |
| Sprint 2 | 13 | 34 | Implementation + branch mgmt |
| **Total** | **34** | - | **4 weeks, 2 sprints** |

---

## 7. Open Questions

| ID | Question | Impact | Decision By |
|----|----------|--------|-------------|
| OQ-E3-001 | Should Stage 4 prefer SKILL.md or library path output? | Primary vs fallback decision | Sprint 1, Week 1 |
| OQ-E3-002 | How should Stage 5 handle cross-engine refactors touching > 10 files? | Implementation scope | Sprint 2, Week 3 |
| OQ-E3-003 | Should failed implementation sessions clean up the feature branch? | Branch management | Sprint 2, Week 3 |

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Focused Epic — Dogfood & Implementation)*
*Fibonacci story points: 34 SP across 4 stories, 2 sprints*
