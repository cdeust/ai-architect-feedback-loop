# Stage 5: Implement Upgrade on AI-PRD Generator

## Your Role
You are implementing an upgrade to the AI-PRD Generator Swift library.
You have the PRD (what to build), the integration plan (how it fits the
architecture), and the manifest (hard file constraints from the dependency graph).

## Product Architecture
The codebase follows strict port/adapter architecture:
- **Domain (SharedUtilities):** 46 port protocols in Sources/Domain/Ports/ — ZERO external deps
- **Engine adapters:** Each AIPRD{Engine} package implements ports from SharedUtilities
- **Service layer (OrchestrationEngine):** Coordinates engines via ports, NEVER imports adapters
- **Composition root (library/Composition):** Wires all concrete types, only place that knows implementations

Package dependency graph (from engine_graph.json):
{{ENGINE_GRAPH}}

## CLAUDE.md Architecture Rules
{{CLAUDE_MD_RULES}}

## Swift Anti-Patterns (NEVER use)
- NO `@_exported import` — each module declares its own imports
- NO `typealias` — use concrete types or protocols directly
- NO casting to `Any` — use correct types or generics
- NO AnyCodable — use JSONValue enum or concrete types

## PRD — What to Build
{{UPGRADE_PRD}}

## Integration Plan — How It Fits
{{INTEGRATION_PLAN}}

## Manifest — Hard File Constraints
### Files you MUST modify:
{{MUST_CHANGE}}

### Files you MUST NOT modify:
{{MUST_NOT_CHANGE}}

## Affected Engine Contracts (Current Swift Protocols)
{{ENGINE_CONTRACTS}}

## Implementation Rules
1. Modify ONLY files in must_change list
2. DO NOT touch files in must_not_change list
3. New capabilities = new methods on existing ports in SharedUtilities/Domain/Ports/
4. New port methods -> implement in relevant engine adapter -> wire in Composition if needed
5. OrchestrationEngine consumes via ports, NEVER imports engine adapter packages
6. New test files under the relevant package's Tests/ directory are allowed
7. All code must compile and pass tests

## Build & Test Commands (per affected engine)
{{BUILD_COMMANDS}}

## Git Workflow
You are on branch `pipeline/improvement-{{FINDING_ID}}`.
Commit changes with descriptive messages. Each commit should:
- Touch files from a single engine package (keeps PRs reviewable)
- Include test updates alongside implementation
- Reference the finding ID in commit messages
