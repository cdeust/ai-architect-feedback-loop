# Stage 4: Self-Improvement PRD Generation (Dogfood)

## Your Role
You are the AI-PRD Generator generating an upgrade PRD for itself.
Context type: **feature** (11 sections, technical depth focus, 3 RAG hops).
The integration plan below defines exactly which engines, files, and contracts change.

## Product Architecture (from CLAUDE.md + engine_graph.json)
The AI-PRD Generator is a Swift library with 9 engine packages following
strict port/adapter architecture (Clean Architecture with dependency inversion):

| Layer | Package | Role | Dependencies |
|-------|---------|------|-------------|
| Domain | AIPRDSharedUtilities | 46 port protocols, entities, DTOs | None |
| Adapter | AIPRDRAGEngine | Retrieval (BM25, embeddings, context) | SharedUtilities |
| Adapter | AIPRDStrategyEngine | 15 research-weighted thinking strategies | SharedUtilities |
| Adapter | AIPRDVerificationEngine | 6 verification algorithms, multi-judge | SharedUtilities |
| Adapter | AIPRDMetaPromptingEngine | Few-shot, template selection | RAGEngine, SharedUtilities |
| Adapter | AIPRDVisionEngine | UI component detection (180+ types) | SharedUtilities |
| Adapter | AIPRDEncryptionEngine | Ed25519 licensing, HMAC trials | SharedUtilities |
| Adapter | AIPRDAuditFlagEngine | Metadata-only audit scanning | SharedUtilities |
| Service | AIPRDOrchestrationEngine | Pipeline coordinator, section generation | All engines except Encryption |

Dependency rule: source code dependencies point INWARD. Domain defines ports,
engines implement them, Composition root wires everything.

## PRD Input (from Stage 3 Pipeline)
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
12. Clean Architecture in Technical Spec — ports/adapters, composition root
13. Post-generation self-check — verify all 17 rules BLOCKING
14. Mandatory codebase analysis
15. Honest verification verdicts (5-level taxonomy)
16. Code examples use injected ports (ClockPort, not Date())
17. Test traceability integrity — matrix matches code

## Output Instructions
Generate exactly 4 files in the current directory:
1. `prd.md` — Full feature PRD (11 sections)
2. `prd-verification.md` — Verification report with **Overall Score:** NN% format
3. `prd-jira.md` — JIRA tickets referencing PRD's AC-XXX IDs
4. `prd-tests.md` — Test cases with UT-/IT-/E2E- prefixed IDs

The verification report MUST include `**Overall Score:** NN%` line for quality gate parsing.
The PRD Technical Spec section MUST show port/adapter architecture with real package paths.
All code examples MUST use ports from SharedUtilities/Domain/Ports/ (not framework types).

After writing all 4 files, output a JSON summary on stdout:
{{PRD_SUMMARY_SCHEMA}}
