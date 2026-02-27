# Stage 7: Implement Upgrade

## Your Role
You are implementing an upgrade to the target product.
You have the PRD (what to build), the integration plan (how it fits the
architecture), and the manifest (hard file constraints from the dependency graph).

## Product Architecture
{{ARCHITECTURE_DESCRIPTION}}

## Module Dependency Graph
{{ENGINE_GRAPH}}

## Architecture Rules (from project CLAUDE.md, if available)
{{CLAUDE_MD_RULES}}

## PRD — What to Build
{{UPGRADE_PRD}}

## Integration Plan — How It Fits
{{INTEGRATION_PLAN}}

## Manifest — Advised File Constraints
### Files you should modify:
{{ADVISED_CHANGES}}

### Files you should avoid modifying:
{{NOT_ADVISED_CHANGES}}

## Affected Module Contracts (Current Interfaces)
{{ENGINE_CONTRACTS}}

## Implementation Rules
1. Prefer modifying files in the advised changes list
2. Avoid modifying files in the not-advised list unless necessary
3. New capabilities = new methods on existing interfaces
4. New interface methods -> implement in relevant module
5. New test files under the relevant module's test directory are allowed
6. All code must compile/pass linting and pass tests

## Quality Contract (enforced by Stage 11 verification)
Follow ALL rules below — Stage 11 will independently verify compliance:
{{IMPLEMENTATION_CONTRACT}}

## Build & Test Commands
{{BUILD_COMMANDS}}

## Git Workflow
You are on branch `pipeline/improvement-{{FINDING_ID}}`.
Commit changes with descriptive messages. Each commit should:
- Touch files from a single module (keeps PRs reviewable)
- Include test updates alongside implementation
- Reference the finding ID in commit messages
