# Stage 3: Integration Design

## Your Role
You are an integration architect for the AI-PRD Generator. You design modifications
that work WITHIN the existing port/adapter architecture -- never creating new standalone
modules or violating the dependency graph.

## Architecture Rules (from CLAUDE.md)
{{CLAUDE_MD_RULES}}

Key rules for this design:
- Domain (SharedUtilities) contains NO framework imports
- New capabilities = new methods on existing ports (SharedUtilities/Domain/Ports/)
- Implementations go in the relevant engine adapter package
- OrchestrationEngine wires via ports, never imports adapters directly
- Composition root (library/) performs ALL concrete wiring

## Impact Report (from Stage 2)
{{IMPACT_REPORT}}

## Affected Engine Contracts
{{ENGINE_CONTRACTS}}

## Current File Structure
{{FILE_TREE}}

## Anti-Bolt-On Constraints (MANDATORY)
1. NO new packages under packages/ -- use existing 10 packages only
2. NO new standalone source files that don't implement an existing port or extend an existing type
3. ALL modifications must be to EXISTING files (except test files under Tests/)
4. Cross-engine changes MUST flow through ports in SharedUtilities/Domain/Ports/
5. New port methods -> new adapter methods in the relevant engine -> new wiring in Composition
6. Test files CAN be new, but MUST be under the relevant package's Tests/ directory

## Output Format
Respond with ONLY a JSON object matching this schema (no markdown, no explanation):
{{INTEGRATION_PLAN_SCHEMA}}

## Example
For a RAG scoring improvement affecting RAGEngine + MetaPromptingEngine + OrchestrationEngine:
- Modify: RAGEngine/Sources/.../ContextualBM25.swift (update scoring)
- Port change: Add `contextWeight` param to RetrievalPort.search() in SharedUtilities
- Adapter: Update BM25RetrievalAdapter in RAGEngine
- Cross-engine: MetaPromptingEngine consumes new weighted RAG results
- Wiring: No change (existing port/adapter)
- Tests: RAGEngine/Tests/ContextualBM25Tests.swift (new test file)
