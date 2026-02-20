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
[Check each of the 64 rules below]
```

**The `**Overall Score:** NN%` line is MANDATORY — the pipeline parses it.**
Verification metrics must be labeled "projected" with a disclaimer.
Use honest 5-level verdict taxonomy: STRONG_PASS, PASS, MARGINAL, WEAK, FAIL.

---

## Hard Output Rules (ALL 64 — MUST ENFORCE)

### Core PRD Rules (1-17)

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
13. Post-generation self-check — verify all 64 rules BLOCKING before finishing
14. Mandatory codebase analysis — reference actual files from integration plan
15. Honest verification verdicts (5-level taxonomy)
16. Code examples use injected interfaces (not framework globals)
17. Test traceability integrity — matrix matches test code

### Architecture & Code Quality Rules (18-24)

18. **Generic over specific** — Technical Spec MUST design for the general class of
    problem, not just the immediate finding. Parameters over hardcoded values, composable
    mechanisms over single-purpose fields, reusable abstractions over one-off fixes.
    If the finding is "fix subtitle width", the spec should enable "configure any text
    element's width". Flag narrow solutions that would require reopening shared code
    for the next similar request.
19. **No nested types** — Code examples MUST NOT contain nested struct/class/enum/interface
    declarations. Every type is a top-level declaration. Nested types reduce readability,
    prevent reuse, and make testing harder.
20. **Single responsibility** — Each class/struct has one reason to change. Code examples
    MUST NOT show classes exceeding ~50 lines. The spec MUST discuss separation of concerns.
21. **Explicit access control** — Define what is public vs private. Use access modifiers,
    minimize exposed API surface, enforce encapsulation.
22. **Factory-based injection** — Dependencies injected through factories or DI containers,
    NEVER instantiated directly in business logic. Spec MUST show how dependencies are wired.
23. **SOLID compliance** — Single responsibility, open/closed (extensible without modification),
    and dependency inversion (depend on abstractions, not concretions) at minimum.
24. **Code reusability & readability** — Shared utilities over duplication, descriptive naming,
    consistent patterns. If the same logic appears in two places, extract it.

### Security Rules (25-32)

25. **No hardcoded secrets** — Code examples MUST NOT contain hardcoded credentials, API keys,
    tokens, passwords, or connection strings. Use environment variables, secret managers, or
    configuration injection. Never embed secrets directly in code.
26. **Input validation at all boundaries** — Every external input (API request, user input, file
    upload, webhook) MUST specify validation and sanitization rules. No raw data flows into
    business logic unvalidated.
27. **Output encoding & injection prevention** — Spec MUST address XSS prevention (output encoding),
    SQL injection prevention (parameterized queries only), and command injection prevention. No
    string concatenation in queries.
28. **Authentication & authorization on every endpoint** — Every operation MUST specify authentication
    method (JWT, OAuth2, API key, etc.), required roles/permissions, and access control model
    (RBAC/ABAC). Principle of least privilege.
29. **Security-safe error handling** — Error responses MUST NOT leak stack traces, internal file paths,
    database schemas, server versions, or implementation details. Separate internal logs from
    client-facing error messages.
30. **Cryptographic standards** — No weak algorithms (MD5, SHA-1, DES, RC4). Specify minimum standards:
    AES-256 for encryption, bcrypt/argon2 for passwords, SHA-256+ for hashing. Define key rotation
    and management strategy.
31. **Rate limiting on public endpoints** — All public-facing endpoints MUST specify rate limiting
    strategy: requests per user/IP, throttling behavior, burst limits, and abuse prevention.
32. **Secure communication** — Specify TLS requirements for all data in transit, certificate
    validation, no mixed content. All API communication over HTTPS.

### Data Protection & Compliance Rules (33-38)

33. **Data classification required** — Every data entity MUST be classified by sensitivity level
    (public/internal/confidential/restricted) with specific handling rules per classification.
34. **PII & sensitive data protection** — Sensitive data MUST specify: encryption at rest,
    masking/anonymization strategy, pseudonymization approach, and field-level access restrictions.
    Address at least 2 of: encryption, masking, access control.
35. **No sensitive data in logs/errors/URLs** — PII, credentials, and tokens MUST NOT appear in log
    output, error responses, query parameters, or URLs. Specify log sanitization strategy.
36. **Data minimization** — Collect and store only what's necessary. Every sensitive field MUST be
    justified with a clear purpose. Define purpose limitation.
37. **Audit trail for sensitive operations** — Security-sensitive operations (auth events, data access,
    config changes, admin actions) MUST include audit logging: who/what/when/where.
38. **Consent & erasure support** — Data model MUST support consent tracking, deletion cascades, and
    right to be forgotten (GDPR/CCPA compliance). Specify how erasure propagates through the system.

### Error Handling & Resilience Rules (39-43)

39. **Structured error handling** — Define domain-specific error types with error hierarchies. No
    swallowed exceptions, no generic catch-all without rethrow. Explicit error propagation strategy
    from every layer.
40. **Resilience patterns required** — External dependencies MUST have: circuit breaker for failure
    isolation, retry with exponential backoff, and timeout on every external call. Specify failure
    thresholds.
41. **Graceful degradation** — Spec MUST define fallback behavior when dependencies fail. No cascading
    failures. Define degraded operation modes and what features remain available.
42. **Transaction boundaries & rollback** — Data operations MUST specify transaction scope, isolation
    level, rollback strategy, and idempotency for multi-step operations. Use sagas for distributed
    transactions.
43. **Consistent error response format** — All APIs MUST use a standardized error structure with error
    codes, human-readable messages, and machine-readable details (e.g., RFC 7807 Problem Details).

### Concurrency & State Management Rules (44-46)

44. **Concurrency safety** — Shared mutable state MUST be protected. Spec MUST address thread safety
    guarantees, race condition prevention, and deadlock avoidance. Use actors, locks, or channels as
    appropriate.
45. **Immutability by default** — Prefer immutable data structures (value types, const/let/val). Any
    mutable state MUST be explicitly justified with a clear reason.
46. **Atomic operations & transaction isolation** — Multi-step state changes MUST be atomic. Specify
    transaction isolation levels and optimistic/pessimistic concurrency control strategy.

### Senior Code Quality Standards (47-52)

47. **No magic numbers/strings** — ALL literal values in code examples MUST be named constants. No raw
    numbers or string literals in business logic. Use MAX_RETRY_COUNT, DEFAULT_TIMEOUT_MS, etc.
48. **Defensive coding** — Guard clauses, preconditions, null safety, and bounds checking at ALL entry
    points. Fail fast on invalid state. Validate assumptions explicitly.
49. **Method/function size limits** — No function in code examples should exceed ~30 lines. Extract
    complex logic into well-named helper functions.
50. **Consistent naming conventions** — Establish casing style (camelCase, snake_case, etc.), use
    descriptive names, avoid abbreviations in public APIs, enforce consistent patterns.
51. **API contract documentation** — Every endpoint MUST have typed request/response schemas, status
    codes, error responses, and content-type specifications documented.
52. **Deprecation strategy** — Breaking changes MUST specify migration path, sunset timeline, and
    versioning approach. Define backward compatibility strategy.

### Comprehensive Testing Rules (53-58)

53. **Mandatory test coverage for all public APIs** — Every public method/endpoint MUST have
    corresponding test specifications. Define coverage targets for unit, integration, and overall.
54. **Security testing requirements** — Test spec MUST include SAST/DAST, dependency vulnerability
    scanning, penetration test plan, and OWASP-based test cases.
55. **Performance & load testing** — Define load test scenarios, stress thresholds, baseline
    comparisons, and latency percentile targets (p95, p99).
56. **No production data in tests** — ALL test data MUST be synthetic/anonymized. No real PII in test
    fixtures. Use factories, fakers, and seed data generators.
57. **Edge case & negative path testing** — Tests MUST cover failure scenarios, boundary values,
    invalid inputs, unauthorized access, and concurrent operations — not just happy paths.
58. **Test isolation** — No shared mutable state between tests. Proper setup/teardown. Each test
    independent and repeatable in any order.

### Observability & Monitoring Rules (59-62)

59. **Structured logging with levels** — Define log format (JSON/structured), log levels
    (DEBUG/INFO/WARN/ERROR), and what to log at each level. No unstructured print statements.
60. **Distributed tracing** — Specify correlation IDs for cross-service request tracking, trace
    context propagation, and observability platform integration.
61. **No PII in observability** — Logs, metrics, traces, and dashboards MUST NOT contain sensitive
    personal data. Specify masking/redaction strategy for observability pipelines.
62. **Alerting thresholds & escalation** — Define what triggers alerts, severity levels, escalation
    paths, on-call routing, and runbook references.

### Dependency & Supply Chain Rules (63-64)

63. **Dependency vulnerability scanning** — Spec MUST require SCA tooling (Snyk, Dependabot, Trivy)
    for automated vulnerability detection. CVE monitoring in CI/CD pipeline.
64. **Minimal dependency principle** — New dependencies MUST be justified. Prefer standard library.
    Verify license compliance. Define dependency review and approval process.

---

## Execution Instructions

1. Read the PRD Input and Integration Plan above carefully
2. Analyze the affected modules and file paths
3. Write `prd.md` with all 11 sections (include Implementation Roadmap with SP!)
4. Write `prd-jira.md` with epics, stories, SP, and AC references
5. Write `prd-tests.md` with real test implementations
6. Write `prd-verification.md` with `**Overall Score:** NN%`
7. Run self-check against all 64 hard output rules
8. Output JSON summary:

{{PRD_SUMMARY_SCHEMA}}
