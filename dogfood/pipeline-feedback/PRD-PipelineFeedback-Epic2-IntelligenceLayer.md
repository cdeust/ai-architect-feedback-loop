# PRD: Pipeline Feedback — Epic 2: Intelligence Layer

**Document Type:** Implementation-Level PRD (Focused Epic)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Parent PRD:** PRD-PipelineFeedback.md (Full Scope Overview)
**Epic:** 2 of 5 — Intelligence Layer
**Stages Covered:** 2, 3
**Estimated Effort:** 58 SP (Fibonacci)
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
8. [Appendix](#8-appendix)

---

## 1. Overview

### 1.1 Epic Scope

Epic 2 builds the intelligence layer — Claude Code CLI sessions that analyze findings for cross-engine compound impact and design integration plans. This is where bolt-on features get rejected.

| Component | Stage | What It Delivers |
|-----------|-------|-----------------|
| Impact Analysis Prompt | Stage 2 | Structured prompt template with engine graph context and scoring rules |
| Stage 2 Orchestrator | Stage 2 | Shell script invoking Claude Code CLI with structured context |
| Stage 2 Validator | Stage 2 | Deterministic post-processing enforcing engines_affected >= 2, compound_score >= 0.3 |
| Integration Design Prompt | Stage 3 | Structured prompt with contract definitions and anti-bolt-on rules |
| Stage 3 Orchestrator | Stage 3 | Shell script invoking Claude Code CLI for integration planning |
| Stage 3 Validator | Stage 3 | Deterministic validation rejecting new standalone files and zero cross-engine connections |
| Manifest Generator | Stage 3 | Python script converting integration plan into enforcement manifest for Stage 6 |
| Engine Contract Extractor | Pre-req | Script that extracts protocol/interface definitions from Swift source |

### 1.2 Dependencies on Epic 1

| Epic 1 Deliverable | Used By | How |
|---------------------|---------|-----|
| `config/engine_graph.json` | Stage 2 prompt context | Injected into Claude Code CLI session |
| `config/thresholds.json` | Stage 2/3 validators | compound_score_minimum, engines_affected_minimum |
| `runs/<timestamp>/findings.json` | Stage 2 input | Each finding processed through impact analysis |
| Stage 6 enforcement gates | Manifest → Stage 6 | Manifest from Stage 3 feeds into Stage 6 Gate 2 |

### 1.3 Key Design Decisions

- **Claude Code CLI, not API**: All sessions use `claude` CLI (Max subscription, zero cost)
- **Prompt injection via files**: Context provided through `--context` flag or file references, not inline
- **Deterministic post-processing**: Claude Code output is validated by shell scripts, not trusted blindly
- **Bolt-on rejection**: Any integration plan that creates new standalone modules is automatically rejected
- **No new inter-package dependencies**: Improvements must work within existing dependency graph

---

## 2. Goals & Success Metrics

### 2.1 Epic-Level Goals

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| EG-201 | Cross-engine impact analysis operational | Manual analysis (~2-4 hours per finding) | Automated analysis (< 15 min per finding) | Stage 2 execution time |
| EG-202 | Bolt-on feature rejection rate | No automated rejection | 100% of single-engine-only findings rejected | Stage 2 validator rejection count |
| EG-203 | Integration plan quality | No integration design step exists | Plans specify exact files, contracts, and cross-engine touchpoints | Validator pass rate |
| EG-204 | Manifest generation from plan | Manual manifest creation | Automated manifest.json from integration_plan.json | Manifest generator output |
| EG-205 | Compound scoring calibration | No scoring exists | Score correlates with manual improvement decisions (> 80% agreement) | Calibration against 10+ manual decisions |

### 2.2 Key Performance Indicators

| KPI | How Measured | Target |
|-----|-------------|--------|
| Stage 2 execution time (per finding) | Timestamp diff: start → impact_report.json written | < 15 minutes |
| Stage 3 execution time (per finding) | Timestamp diff: start → integration_plan.json written | < 15 minutes |
| Impact report schema validity | JSON Schema validation of output | 100% |
| Integration plan schema validity | JSON Schema validation of output | 100% |
| Bolt-on rejection accuracy | Manual review of rejected vs accepted findings | > 90% correct |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement | Story |
|----|----------|-------------|-------|
| FR-E2-001 | P0 | Stage 2 prompt template includes engine dependency graph, finding details, and compound scoring instructions | PIPE-E2-001 |
| FR-E2-002 | P0 | Stage 2 prompt instructs Claude Code to trace first-order and second-order propagation paths through engine graph | PIPE-E2-001 |
| FR-E2-003 | P0 | Stage 2 prompt requires output in valid `impact_report.json` schema | PIPE-E2-001 |
| FR-E2-004 | P0 | Stage 2 orchestrator invokes Claude Code CLI with finding + engine graph + engine source as context | PIPE-E2-002 |
| FR-E2-005 | P0 | Stage 2 orchestrator writes `impact_report.json` to run directory | PIPE-E2-002 |
| FR-E2-006 | P0 | Stage 2 validator enforces `engines_affected >= 2` threshold | PIPE-E2-003 |
| FR-E2-007 | P0 | Stage 2 validator enforces `compound_score >= 0.3` threshold | PIPE-E2-003 |
| FR-E2-008 | P0 | Stage 2 validator produces rejection report with explanation when thresholds not met | PIPE-E2-003 |
| FR-E2-009 | P0 | Stage 3 prompt template includes engine contracts, anti-bolt-on rules, and existing file structure | PIPE-E2-004 |
| FR-E2-010 | P0 | Stage 3 prompt instructs Claude Code to specify exact files that change, new contracts, and cross-engine touchpoints | PIPE-E2-004 |
| FR-E2-011 | P0 | Stage 3 prompt requires output in valid `integration_plan.json` schema | PIPE-E2-004 |
| FR-E2-012 | P0 | Stage 3 orchestrator invokes Claude Code CLI with impact report + engine source + CLAUDE.md as context | PIPE-E2-005 |
| FR-E2-013 | P0 | Stage 3 orchestrator writes `integration_plan.json` to run directory | PIPE-E2-005 |
| FR-E2-014 | P0 | Stage 3 validator rejects plans that create new non-test source files | PIPE-E2-006 |
| FR-E2-015 | P0 | Stage 3 validator rejects plans with missing engine touchpoints (referenced engines not in plan) | PIPE-E2-006 |
| FR-E2-016 | P0 | Stage 3 validator rejects plans with zero cross-engine connections | PIPE-E2-006 |
| FR-E2-017 | P0 | Manifest generator converts `integration_plan.json` into `manifest.json` for Stage 6 Gate 2 | PIPE-E2-007 |
| FR-E2-018 | P0 | Manifest includes must-change files, must-not-change files, and allowed-new-files lists | PIPE-E2-007 |
| FR-E2-019 | P1 | Engine contract extractor parses Swift source for protocol definitions and public API signatures | PIPE-E2-008 |
| FR-E2-020 | P1 | Compound scoring formula: `compound_score = engines_affected * 0.3 + propagation_depth * 0.2 + contract_impact * 0.3 + test_coverage_delta * 0.2` | PIPE-E2-009 |
| FR-E2-021 | P1 | Compound scoring calibrated against 10+ manual improvement decisions | PIPE-E2-009 |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-E2-001 | P0 | Stage 2 + Stage 3 combined execution time | < 30 minutes per finding |
| NFR-E2-002 | P0 | Claude Code CLI sessions use zero API cost | Max subscription only |
| NFR-E2-003 | P0 | Validator false negative rate (passing invalid plans) | 0% |
| NFR-E2-004 | P1 | Prompt templates are version-controlled and human-readable | Markdown format in `prompts/` |
| NFR-E2-005 | P1 | Claude Code session output is deterministically parseable | JSON extraction from session output |
| NFR-E2-006 | P1 | Contract extraction handles all Swift access control levels (public, open, package) | Covers public protocols |

---

## 4. User Stories & Acceptance Criteria

### PIPE-E2-001: Stage 2 Impact Analysis Prompt Template [8 SP]

**As a** Claude Code session (Stage 2),
**I want** a structured prompt with engine graph context and scoring instructions,
**So that** impact analysis traces cross-engine propagation paths accurately.

**AC-E2-001:** Engine Graph Injection
- [ ] GIVEN `engine_graph.json` with 9 engines WHEN prompt is assembled THEN engine names, dependencies, feeds/fed_by relationships are embedded in prompt context

| Metric | Value |
|--------|-------|
| Baseline | N/A — no automated analysis |
| Target | Full graph context in prompt |
| Measurement | Prompt template contains graph placeholder |
| Business Impact | BG-003: multi-engine analysis |

**AC-E2-002:** Propagation Instructions
- [ ] GIVEN a finding affecting RAGEngine WHEN prompt instructs analysis THEN first-order (MetaPrompting, Verification, Strategy) and second-order (Orchestration) paths are expected in output

| Metric | Value |
|--------|-------|
| Baseline | Manual: ~2 hours to trace propagation |
| Target | Automated: < 15 min with correct paths |
| Measurement | Propagation path accuracy on test findings |
| Business Impact | EG-201: automated analysis |

**AC-E2-003:** Output Schema Requirement
- [ ] GIVEN prompt instructions WHEN Claude Code completes THEN output matches `impact_report.json` schema with engines_affected, compound_score, propagation_paths

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Schema-valid JSON output |
| Measurement | JSON Schema validation |
| Business Impact | FR-E2-003: valid output |

**Tasks:**
- [ ] Write `prompts/impact_analysis.md` with sections: Context, Instructions, Engine Graph, Scoring Rules, Output Schema
- [ ] Include compound scoring formula in prompt
- [ ] Include first/second-order propagation tracing instructions
- [ ] Include example input/output for few-shot guidance
- [ ] Test prompt manually with 3 sample findings

---

### PIPE-E2-002: Stage 2 Impact Analysis Orchestrator [5 SP]

**As a** pipeline orchestrator,
**I want** a shell script that invokes Claude Code CLI with structured context for impact analysis,
**So that** each finding is analyzed for cross-engine impact automatically.

**AC-E2-004:** Claude Code CLI Invocation
- [ ] GIVEN a finding in `findings.json` and `engine_graph.json` WHEN orchestrator runs THEN invokes `claude` CLI with prompt template and context files

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Successful CLI invocation |
| Measurement | Claude Code session completes without error |
| Business Impact | EG-201: automated analysis |

**AC-E2-005:** Output Capture
- [ ] GIVEN Claude Code session completes WHEN output is captured THEN `impact_report.json` is written to run directory with valid JSON

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid JSON in run directory |
| Measurement | File existence + JSON parse |
| Business Impact | FR-E2-005: output written |

**AC-E2-006:** Error Handling
- [ ] GIVEN Claude Code CLI session fails (timeout, crash) WHEN orchestrator detects failure THEN logs error and exits with code 1

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Clean error handling |
| Measurement | Exit code + error log |
| Business Impact | TG-001: pipeline completion rate |

**Tasks:**
- [ ] Implement `stage_2_impact_analysis.sh` with `set -euo pipefail`
- [ ] Assemble prompt from template + finding + engine graph
- [ ] Invoke `claude` CLI with assembled context
- [ ] Extract JSON from session output
- [ ] Write `impact_report.json` to run directory
- [ ] Add timeout handling (configurable, default: 15 min)
- [ ] Add structured logging

---

### PIPE-E2-003: Stage 2 Impact Report Validator [5 SP]

**As a** pipeline quality enforcer,
**I want** deterministic validation of impact reports,
**So that** single-engine-only findings are rejected before reaching integration design.

**AC-E2-007:** Engines Affected Threshold
- [ ] GIVEN impact report with `engines_affected: 1` WHEN validator runs with threshold 2 THEN report REJECTED with explanation

| Metric | Value |
|--------|-------|
| Baseline | No automated rejection |
| Target | 100% single-engine findings rejected |
| Measurement | Validator output on test reports |
| Business Impact | BG-003: 100% multi-engine changes |

**AC-E2-008:** Compound Score Threshold
- [ ] GIVEN impact report with `compound_score: 0.2` WHEN validator runs with threshold 0.3 THEN report REJECTED

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% below-threshold findings rejected |
| Measurement | Validator output on test reports |
| Business Impact | EG-202: bolt-on rejection |

**AC-E2-009:** Valid Report Acceptance
- [ ] GIVEN impact report with `engines_affected: 3` and `compound_score: 0.65` WHEN validator runs THEN report ACCEPTED

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid reports pass |
| Measurement | Validator exit code 0 |
| Business Impact | TG-001: pipeline completion |

**AC-E2-010:** Rejection Report
- [ ] GIVEN rejected finding WHEN validator completes THEN produces structured rejection with reason, threshold, actual value

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Human-readable rejection |
| Measurement | Rejection report content |
| Business Impact | FR-E2-008: rejection explanation |

**Tasks:**
- [ ] Implement `validate_impact_report.sh`
- [ ] Parse `impact_report.json` for engines_affected and compound_score
- [ ] Compare against thresholds from `config/thresholds.json`
- [ ] Generate structured rejection report when thresholds not met
- [ ] Add unit tests for accept/reject scenarios

---

### PIPE-E2-004: Stage 3 Integration Design Prompt Template [8 SP]

**As a** Claude Code session (Stage 3),
**I want** a structured prompt with engine contracts and anti-bolt-on rules,
**So that** integration plans specify exact modifications within existing architecture.

**AC-E2-011:** Anti-Bolt-On Rules
- [ ] GIVEN prompt template WHEN reviewed THEN contains explicit rules: no new packages, no standalone modules, modifications to existing files only

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Rules present in prompt |
| Measurement | Template content review |
| Business Impact | FR-E2-009: anti-bolt-on enforcement |

**AC-E2-012:** Contract Context
- [ ] GIVEN engine contract definitions WHEN prompt is assembled THEN public protocols and API signatures from affected engines are embedded

| Metric | Value |
|--------|-------|
| Baseline | Manual: developer reads source code |
| Target | Automated: contracts injected into prompt |
| Measurement | Prompt contains protocol signatures |
| Business Impact | EG-203: plan specifies contracts |

**AC-E2-013:** File Specificity
- [ ] GIVEN prompt instructions WHEN Claude Code completes THEN output specifies exact file paths, not package-level references

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | File-level specificity |
| Measurement | Integration plan contains file paths |
| Business Impact | FR-E2-010: exact files specified |

**Tasks:**
- [ ] Write `prompts/integration_design.md` with sections: Impact Context, Engine Contracts, Design Rules, Anti-Bolt-On Constraints, Output Schema
- [ ] Include CLAUDE.md port/adapter pattern references
- [ ] Include example integration plan for few-shot guidance
- [ ] Include current file structure for affected engines
- [ ] Test prompt manually with 3 sample impact reports

---

### PIPE-E2-005: Stage 3 Integration Design Orchestrator [5 SP]

**As a** pipeline orchestrator,
**I want** a shell script that invokes Claude Code CLI for integration design,
**So that** each accepted finding gets a concrete implementation plan.

**AC-E2-014:** Claude Code CLI Invocation
- [ ] GIVEN impact_report.json WHEN orchestrator runs THEN invokes Claude Code CLI with impact report + engine source + CLAUDE.md as context

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Successful CLI invocation |
| Measurement | Session completes |
| Business Impact | EG-203: integration design |

**AC-E2-015:** Output Capture
- [ ] GIVEN session completes WHEN output captured THEN `integration_plan.json` written to run directory

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid JSON in run directory |
| Measurement | File existence + JSON parse |
| Business Impact | FR-E2-013: output written |

**Tasks:**
- [ ] Implement `stage_3_integration_design.sh` with `set -euo pipefail`
- [ ] Assemble prompt from template + impact report + contracts
- [ ] Invoke `claude` CLI with assembled context
- [ ] Extract JSON from session output
- [ ] Write `integration_plan.json` to run directory
- [ ] Add timeout handling (default: 15 min)
- [ ] Add structured logging

---

### PIPE-E2-006: Stage 3 Integration Plan Validator [5 SP]

**As a** pipeline quality enforcer,
**I want** deterministic validation of integration plans,
**So that** bolt-on designs are rejected before reaching implementation.

**AC-E2-016:** New File Rejection
- [ ] GIVEN plan creating `packages/NewStandaloneModule/` WHEN validator runs THEN plan REJECTED with reason "new non-test source files"

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | 100% standalone module detection |
| Measurement | Validator output |
| Business Impact | FR-E2-014: no new standalone files |

**AC-E2-017:** Missing Touchpoint Detection
- [ ] GIVEN plan referencing engines A, B, C but only modifying A, B WHEN validator runs THEN plan REJECTED with "missing touchpoints for engine C"

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All referenced engines must have modifications |
| Measurement | Validator output |
| Business Impact | FR-E2-015: missing touchpoints |

**AC-E2-018:** Cross-Engine Connection Enforcement
- [ ] GIVEN plan modifying files in only 1 engine WHEN validator runs THEN plan REJECTED with "zero cross-engine connections"

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Minimum 2 engines connected |
| Measurement | Validator output |
| Business Impact | FR-E2-016: cross-engine required |

**AC-E2-019:** Valid Plan Acceptance
- [ ] GIVEN plan modifying files in 3 engines with cross-engine touchpoints WHEN validator runs THEN plan ACCEPTED

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid plans pass |
| Measurement | Exit code 0 |
| Business Impact | TG-001: pipeline completion |

**Tasks:**
- [ ] Implement `validate_integration_plan.sh`
- [ ] Check for new non-test source files (compare plan files against existing)
- [ ] Verify all referenced engines have modifications
- [ ] Verify cross-engine connections >= 2
- [ ] Generate structured validation report
- [ ] Add unit tests

---

### PIPE-E2-007: Manifest Generator [5 SP]

**As a** Stage 6 enforcement gate,
**I want** a manifest.json derived from the integration plan,
**So that** Gate 2 can enforce file constraints deterministically.

**AC-E2-020:** Manifest Generation
- [ ] GIVEN valid `integration_plan.json` WHEN `generate_manifest.py` runs THEN produces `manifest.json` with must_change, must_not_change, allowed_new_files

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Valid manifest from plan |
| Measurement | JSON Schema validation |
| Business Impact | FR-E2-017: automated manifest |

**AC-E2-021:** Must-Change Derivation
- [ ] GIVEN plan specifying files to modify WHEN manifest generated THEN `must_change` array contains exactly those files

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Exact file list match |
| Measurement | Array comparison |
| Business Impact | FR-E2-018: manifest accuracy |

**AC-E2-022:** Must-Not-Change Derivation
- [ ] GIVEN plan specifying affected engines WHEN manifest generated THEN `must_not_change` includes critical files in unaffected engines (Package.swift files, public API)

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Protected files identified |
| Measurement | Array content validation |
| Business Impact | FR-E2-018: protection scope |

**Tasks:**
- [ ] Implement `generate_manifest.py` with argparse
- [ ] Parse integration plan for file lists
- [ ] Derive must_change from plan's modified files
- [ ] Derive must_not_change from unaffected engine critical files
- [ ] Derive allowed_new_files (test files only, matching plan)
- [ ] Output `manifest.json` with schema validation
- [ ] Add unit tests

---

### PIPE-E2-008: Engine Contract Extractor [8 SP]

**As a** prompt assembler (Stages 2, 3),
**I want** engine contracts extracted programmatically from Swift source,
**So that** prompts contain accurate, up-to-date API signatures for affected engines.

**AC-E2-023:** Protocol Extraction
- [ ] GIVEN Swift source with `public protocol FooPort` WHEN extractor runs THEN protocol name, methods, and parameter types captured

| Metric | Value |
|--------|-------|
| Baseline | Manual: developer reads source (~30 min per engine) |
| Target | Automated: < 30 seconds for all engines |
| Measurement | Extraction time + accuracy |
| Business Impact | FR-E2-019: programmatic extraction |

**AC-E2-024:** Public API Surface
- [ ] GIVEN engine package WHEN extractor runs THEN all `public` and `open` declarations captured

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All public API captured |
| Measurement | Compare against manual count |
| Business Impact | EG-203: accurate contracts |

**AC-E2-025:** Output Format
- [ ] GIVEN extracted contracts WHEN output generated THEN produces markdown summary suitable for prompt injection

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Markdown format |
| Measurement | Prompt assembly test |
| Business Impact | NFR-E2-004: human-readable |

**Tasks:**
- [ ] Implement `extract_contracts.py` using regex-based Swift parsing
- [ ] Extract `public protocol`, `public struct`, `public class`, `public func` declarations
- [ ] Group by engine package
- [ ] Output markdown format with code blocks
- [ ] Add `--engine` filter for specific engine extraction
- [ ] Add `--output` for file output
- [ ] Add unit tests with mock Swift files

---

### PIPE-E2-009: Compound Scoring Calibration [5 SP]

**As a** pipeline operator,
**I want** a calibrated compound scoring formula,
**So that** the 0.3 threshold meaningfully separates high-impact from low-impact findings.

**AC-E2-026:** Formula Implementation
- [ ] GIVEN engines_affected=3, propagation_depth=2, contract_impact=0.7, test_coverage_delta=0.3 WHEN formula computed THEN compound_score = 3*0.3 + 2*0.2 + 0.7*0.3 + 0.3*0.2 = 1.57

| Metric | Value |
|--------|-------|
| Baseline | No scoring exists |
| Target | Deterministic formula |
| Measurement | Unit test with known inputs |
| Business Impact | FR-E2-020: compound scoring |

**AC-E2-027:** Calibration Dataset
- [ ] GIVEN 10+ manual improvement decisions (accepted/rejected) WHEN scores computed THEN > 80% agreement between formula and manual decision

| Metric | Value |
|--------|-------|
| Baseline | 0% (no automation) |
| Target | > 80% agreement |
| Measurement | Calibration accuracy |
| Business Impact | FR-E2-021: calibrated scoring |

**Tasks:**
- [ ] Document compound scoring formula
- [ ] Collect 10+ historical improvement decisions with rationale
- [ ] Compute compound scores for historical decisions
- [ ] Measure agreement rate
- [ ] Adjust weights if agreement < 80%
- [ ] Document final calibrated weights in `thresholds.json`

---

## 5. Technical Specification

### 5.1 Data Schemas

#### impact_report.json (Stage 2 Output)

```json
{
  "finding_id": "tv-20260211-001",
  "analysis_timestamp": "2026-02-11T22:05:00Z",
  "engines_affected": 3,
  "compound_score": 0.65,
  "propagation_paths": [
    {
      "order": 1,
      "from": "RAGEngine",
      "to": "VerificationEngine",
      "mechanism": "Contextual BM25 output feeds verification claim decomposition"
    },
    {
      "order": 1,
      "from": "RAGEngine",
      "to": "MetaPromptingEngine",
      "mechanism": "RAG chunks inform template selection"
    },
    {
      "order": 2,
      "from": "MetaPromptingEngine",
      "to": "OrchestrationEngine",
      "mechanism": "Enhanced prompts improve orchestration quality"
    }
  ],
  "affected_engines": ["RAGEngine", "VerificationEngine", "MetaPromptingEngine"],
  "scoring_breakdown": {
    "engines_affected": { "value": 3, "weight": 0.3, "contribution": 0.9 },
    "propagation_depth": { "value": 2, "weight": 0.2, "contribution": 0.4 },
    "contract_impact": { "value": 0.7, "weight": 0.3, "contribution": 0.21 },
    "test_coverage_delta": { "value": 0.3, "weight": 0.2, "contribution": 0.06 }
  },
  "recommendation": "PROCEED",
  "rationale": "Finding affects 3 engines with 2-depth propagation through RAG → MetaPrompting → Orchestration chain"
}
```

#### integration_plan.json (Stage 3 Output)

```json
{
  "finding_id": "tv-20260211-001",
  "plan_timestamp": "2026-02-11T22:10:00Z",
  "affected_engines": ["RAGEngine", "VerificationEngine", "MetaPromptingEngine"],
  "modifications": [
    {
      "engine": "RAGEngine",
      "files": [
        {
          "path": "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift",
          "action": "modify",
          "description": "Update BM25 scoring with contextual weights"
        }
      ],
      "contract_changes": [
        {
          "protocol": "RetrievalPort",
          "method": "search(query:context:)",
          "change": "Add optional `contextWeight` parameter"
        }
      ]
    }
  ],
  "cross_engine_touchpoints": [
    {
      "from_engine": "RAGEngine",
      "to_engine": "VerificationEngine",
      "touchpoint": "RAG output format feeds claim decomposition input",
      "files_affected": ["packages/AIPRDVerificationEngine/Sources/Claims/ClaimDecomposer.swift"]
    }
  ],
  "new_files": [],
  "test_files": [
    "packages/AIPRDRAGEngine/Tests/ContextualBM25Tests.swift"
  ],
  "constraints": {
    "no_new_packages": true,
    "no_standalone_modules": true,
    "existing_dependency_graph_only": true
  }
}
```

#### manifest.json (Stage 3 → Stage 6)

```json
{
  "generated_from": "integration_plan.json",
  "generated_at": "2026-02-11T22:12:00Z",
  "must_change": [
    "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift",
    "packages/AIPRDVerificationEngine/Sources/Claims/ClaimDecomposer.swift"
  ],
  "must_not_change": [
    "packages/AIPRDSharedUtilities/Package.swift",
    "packages/AIPRDEncryptionEngine/Package.swift",
    "library/Package.swift",
    "Makefile"
  ],
  "allowed_new_files": [
    "packages/AIPRDRAGEngine/Tests/ContextualBM25Tests.swift"
  ]
}
```

### 5.2 Prompt Template Structure

```markdown
# prompts/impact_analysis.md

## Context
You are analyzing a Technical Veil finding for cross-engine impact within the AI-PRD Generator.

## Engine Dependency Graph
{{ENGINE_GRAPH_JSON}}

## Finding Under Analysis
{{FINDING_JSON}}

## Instructions
1. Identify which engines are directly affected by this finding
2. Trace first-order propagation (engines that consume output from affected engines)
3. Trace second-order propagation (engines that consume output from first-order engines)
4. Score compound impact using formula:
   compound_score = engines_affected × 0.3 + propagation_depth × 0.2 + contract_impact × 0.3 + test_coverage_delta × 0.2
5. Recommend PROCEED (score >= 0.3, engines >= 2) or REJECT

## Output Format
Respond with a single JSON object matching this schema:
{{IMPACT_REPORT_SCHEMA}}

## Example
{{EXAMPLE_INPUT_OUTPUT}}
```

### 5.3 Claude Code CLI Integration

```bash
# Stage 2 invocation pattern
claude --context "$CONTEXT_FILE" \
       --output-format json \
       --max-turns 5 \
       --prompt "$(cat prompts/impact_analysis.md)" \
       > "$RUN_DIR/impact_report_raw.json"

# Extract clean JSON from Claude Code output
python3 -c "
import json, sys
raw = open(sys.argv[1]).read()
# Extract JSON block from Claude Code output
start = raw.index('{')
end = raw.rindex('}') + 1
print(raw[start:end])
" "$RUN_DIR/impact_report_raw.json" > "$RUN_DIR/impact_report.json"
```

---

## 6. Implementation Roadmap

### Sprint 1 (Week 1-2): Prompts & Extraction [21 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E2-008: Engine Contract Extractor | 8 | Epic 1 (engine graph) |
| PIPE-E2-001: Stage 2 Impact Analysis Prompt | 8 | Contract extractor |
| PIPE-E2-009: Compound Scoring Calibration | 5 | None (parallel) |

**Sprint Goal:** Prompt templates ready with accurate engine contracts and calibrated scoring.

### Sprint 2 (Week 3-4): Stage 2 [10 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E2-002: Stage 2 Orchestrator | 5 | Prompt template |
| PIPE-E2-003: Stage 2 Validator | 5 | Orchestrator (for testing) |

**Sprint Goal:** Stage 2 end-to-end operational — finding → impact report → validation.

### Sprint 3 (Week 5-6): Stage 3 [18 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E2-004: Stage 3 Integration Design Prompt | 8 | Stage 2 output |
| PIPE-E2-005: Stage 3 Orchestrator | 5 | Prompt template |
| PIPE-E2-006: Stage 3 Validator | 5 | Orchestrator |

**Sprint Goal:** Stage 3 end-to-end operational — impact report → integration plan → validation.

### Sprint 4 (Week 7-8): Manifest & Polish [9 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E2-007: Manifest Generator | 5 | Stage 3 output |
| Integration testing & prompt tuning | 4 | All stories |

**Sprint Goal:** Full Stage 2 → Stage 3 → manifest pipeline operational.

### Summary

| Sprint | SP | Cumulative | Theme |
|--------|----|-----------|-------|
| Sprint 1 | 21 | 21 | Prompts + contracts + calibration |
| Sprint 2 | 10 | 31 | Stage 2 end-to-end |
| Sprint 3 | 18 | 49 | Stage 3 end-to-end |
| Sprint 4 | 9 | 58 | Manifest + integration testing |
| **Total** | **58** | - | **8 weeks, 4 sprints** |

---

## 7. Open Questions

| ID | Question | Impact | Decision By |
|----|----------|--------|-------------|
| OQ-E2-001 | Does Claude Code CLI support `--context` flag for file injection? | Orchestrator implementation | Sprint 2, Week 3 |
| OQ-E2-002 | What is the reliable method to extract JSON from Claude Code CLI output? | Output parsing | Sprint 2, Week 3 |
| OQ-E2-003 | Should compound scoring use normalized (0-1) or raw values? | Threshold interpretation | Sprint 1, Week 2 |
| OQ-E2-004 | How many manual improvement decisions are available for calibration? | Calibration quality | Sprint 1, Week 1 |

---

## 8. Appendix

### Dependency on Epic 1

```
Epic 1: engine_graph.json ──▶ Stage 2 prompt context
Epic 1: thresholds.json   ──▶ Stage 2/3 validators
Epic 1: findings.json     ──▶ Stage 2 input
Epic 1: Stage 6 gates     ──▶ manifest.json consumer
```

### Future Epic Dependencies

```
Epic 2: impact_report.json     ──▶ Epic 3 (Stage 4 PRD input)
Epic 2: integration_plan.json  ──▶ Epic 3 (Stage 5 implementation context)
Epic 2: manifest.json          ──▶ Epic 1 (Stage 6 Gate 2 enforcement)
```

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Focused Epic — Intelligence Layer)*
*Fibonacci story points: 58 SP across 9 stories, 4 sprints*
