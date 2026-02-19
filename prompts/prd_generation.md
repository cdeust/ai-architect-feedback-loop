# Stage 4: Self-Improvement PRD Generation

## Your Role
You are generating an upgrade PRD for the target product using the ai-prd-generator skill.
Context type: **feature** (11 sections, technical depth focus, 3 RAG hops).
The integration plan below defines exactly which modules, files, and contracts change.

## Product Architecture
{{ARCHITECTURE_DESCRIPTION}}

## Module Dependency Graph
{{ENGINE_GRAPH}}

## PRD Input (from pipeline)
{{PRD_INPUT}}

## SKILL.md Hard Output Rules (ALL 17 — MUST ENFORCE)
1. SP arithmetic must add up across all tables
2. No self-referencing dependencies
3. AC numbering consistent across PRD + JIRA (AC-XXX cross-file)
4. No orphan DDL
5. No NOW() in partial indexes
6. No AnyCodable — use concrete types
7. No placeholder tests — real implementation bodies
8. SP NOT in FR table — only in Implementation Roadmap
9. Uneven SP distribution — reflect real complexity
10. Verification metrics labeled "projected" with disclaimer
11. FR traceability — every FR traces to source
12. Clean Architecture in Technical Spec — show module structure and interfaces
13. Post-generation self-check — verify all 17 rules BLOCKING
14. Mandatory codebase analysis
15. Honest verification verdicts (5-level taxonomy)
16. Code examples use injected interfaces (not framework globals)
17. Test traceability integrity — matrix matches code

## Output Instructions
Generate exactly 4 files in the current directory:
1. `prd.md` — Full feature PRD (11 sections)
2. `prd-verification.md` — Verification report with **Overall Score:** NN% format
3. `prd-jira.md` — JIRA tickets referencing PRD's AC-XXX IDs
4. `prd-tests.md` — Test cases with UT-/IT-/E2E- prefixed IDs

The verification report MUST include `**Overall Score:** NN%` line for quality gate parsing.
The PRD Technical Spec section MUST show module architecture with real paths.

After writing all 4 files, output a JSON summary on stdout:
{{PRD_SUMMARY_SCHEMA}}
