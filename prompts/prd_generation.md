# Stage 4: PRD Generation (Non-Interactive Pipeline Mode)

## Your Role
You are generating a production-ready PRD for a code improvement. This runs
in non-interactive pipeline mode — do NOT use AskUserQuestion, do NOT ask
for clarification. All context is provided below. Generate all 4 output files
immediately using the Write tool.

**PRD context type:** feature (11 sections, technical depth focus)

## Product Architecture
{{ARCHITECTURE_DESCRIPTION}}

## Module Dependency Graph
{{ENGINE_GRAPH}}

## PRD Input (from pipeline)
{{PRD_INPUT}}

---

## OUTPUT FORMAT SPECIFICATIONS

You MUST generate exactly **4 files** using the Write tool. Every file must
be complete — no placeholders, no TODOs, no skeleton sections.

### File 1: `prd.md` — Full Feature PRD (11 sections)

```
Table of Contents
1. Overview
2. Goals & Metrics
3. Requirements (Functional + Non-Functional)
   - FR-001, FR-002, ... (each traces to source finding)
4. User Stories
5. Technical Specification
   - Module architecture with REAL file paths from the integration plan
   - Domain models / data classes affected
   - Code examples using injected interfaces (not framework globals)
6. Acceptance Criteria
   - AC-001, AC-002, ... (cross-referenced in JIRA file)
   - Each AC has: GIVEN/WHEN/THEN format
7. Dependencies
8. Risks & Mitigations
9. Implementation Roadmap
   - Phases with Fibonacci story points (1, 2, 3, 5, 8, 13)
   - SP per phase, total SP at bottom
   - Single story > 13 SP = must split into sub-stories
   - UNEVEN SP distribution — reflect real complexity differences
10. Open Questions
11. Appendix
```

**CRITICAL — Implementation Roadmap MUST include story points:**
```
Phase 1 (Week 1): [Description] [XX SP]
  - Story 1.1: [Name] [X SP]
  - Story 1.2: [Name] [Y SP]

Phase 2 (Week 2): [Description] [YY SP]
  - Story 2.1: [Name] [X SP]

Total: XX SP (~N weeks, 1-person team)
```

### File 2: `prd-jira.md` — JIRA Tickets

```
# JIRA Tickets: [Project Name]

## Summary
Total Story Points: XXX SP

## Epic Overview
| Epic | Stories | Story Points |
|------|---------|-------------|
| Epic 1: {Name} | X | XX SP |

## Detailed Tickets

Epic 1: [Name] [XX SP]

Story 1.1: [Name] [X SP]
  - Task: [description]
  - Task: [description]

  **AC-001:** [Title]
  - [ ] GIVEN ... WHEN ... THEN ...

[CSV section for import:]
Summary,Issue Type,Priority,Story Points,Epic Link,Labels,Description
```

**Story points MUST use Fibonacci: 1, 2, 3, 5, 8, 13**
**SP arithmetic MUST add up: story SPs sum to epic SP, epic SPs sum to total**

### File 3: `prd-tests.md` — Test Cases

```
# Test Cases: [Project Name]

## PART A: Coverage Tests
UT-001: [Unit test name]
  - Setup: ...
  - Action: ...
  - Assert: ...

IT-001: [Integration test name]
  - Setup: ...
  - Action: ...
  - Assert: ...

E2E-001: [End-to-end test name] (if applicable)

## PART B: Acceptance Criteria Validation Tests
[Each AC-XXX linked to specific test IDs]

## PART C: AC-to-Test Traceability Matrix
| AC | Test IDs | Status |
|----|----------|--------|
| AC-001 | UT-001, IT-001 | Planned |
```

**No placeholder tests — every test must have real implementation bodies.**
**Test IDs MUST use prefixes: UT- (unit), IT- (integration), E2E- (end-to-end)**

### File 4: `prd-verification.md` — Verification Report

```
# Verification Report: [Project Name]

Generated: [date]
PRD File: prd.md

**Overall Score:** NN%

## Executive Summary
| Metric | Result |
|--------|--------|
| Overall Quality | NN% |
| Completeness | X/11 sections |
| FR Count | N |
| AC Count | N |
| Total SP | N |

## Section-by-Section Verification
### 1. Overview
- Score: NN%
- Verdict: [STRONG_PASS|PASS|MARGINAL|WEAK|FAIL]
[repeat for each section]

## Hard Output Rules Compliance
[Check each of the 17 rules below]
```

**The `**Overall Score:** NN%` line is MANDATORY — the pipeline parses it.**
Verification metrics must be labeled "projected" with a disclaimer.
Use honest 5-level verdict taxonomy: STRONG_PASS, PASS, MARGINAL, WEAK, FAIL.

---

## Hard Output Rules (ALL 18 — MUST ENFORCE)

1. **SP arithmetic must add up** across all tables (stories→epics→total)
2. No self-referencing dependencies
3. AC numbering consistent across PRD + JIRA (AC-XXX cross-file)
4. No orphan DDL
5. No NOW() in partial indexes
6. No AnyCodable — use concrete types
7. No placeholder tests — real implementation bodies
8. SP NOT in FR table — only in Implementation Roadmap and JIRA
9. Uneven SP distribution — reflect real complexity
10. Verification metrics labeled "projected" with disclaimer
11. FR traceability — every FR traces to source finding
12. Clean Architecture in Technical Spec — show module structure and real file paths
13. Post-generation self-check — verify all 18 rules BLOCKING before finishing
14. Mandatory codebase analysis — reference actual files from integration plan
15. Honest verification verdicts (5-level taxonomy)
16. Code examples use injected interfaces (not framework globals)
17. Test traceability integrity — matrix matches test code
18. **Generic over specific** — Technical Spec MUST design for the general class of
    problem, not just the immediate finding. Parameters over hardcoded values, composable
    mechanisms over single-purpose fields, reusable abstractions over one-off fixes.
    If the finding is "fix subtitle width", the spec should enable "configure any text
    element's width". Flag narrow solutions that would require reopening shared code
    for the next similar request.

---

## Execution Instructions

1. Read the PRD Input and Integration Plan above carefully
2. Analyze the affected modules and file paths
3. Write `prd.md` with all 11 sections (include Implementation Roadmap with SP!)
4. Write `prd-jira.md` with epics, stories, SP, and AC references
5. Write `prd-tests.md` with real test implementations
6. Write `prd-verification.md` with `**Overall Score:** NN%`
7. Run self-check against all 18 hard output rules
8. Output JSON summary:

{{PRD_SUMMARY_SCHEMA}}
