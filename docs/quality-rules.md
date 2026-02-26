# Quality Enforcement Rules

The pipeline enforces **64 hard output rules** across PRD generation, implementation, and verification. These rules are stack-agnostic and ensure every generated artifact meets production-quality standards expected by senior engineers, compliance officers, and security teams.

**These are enforced automatically. You don't need to configure them.**

---

## Core PRD rules (1-17)

Rules enforced during Stage 5 PRD generation:

| Rule | What it enforces |
|---|---|
| 1. SP Arithmetic | Story points must add up across stories, epics, and totals |
| 2. No Self-Referencing Deps | No item depends on itself |
| 3. AC Numbering | Acceptance criteria numbered consistently across all files |
| 4. No Orphan DDL | Every CREATE TYPE must be referenced by a table |
| 5. No NOW() in Indexes | Volatile functions forbidden in partial index predicates |
| 6. No AnyCodable | Concrete types only — no type-erased wrappers |
| 7. No Placeholder Tests | Every test must have a real implementation body |
| 8. SP Not in FR Table | Story points belong in roadmap and JIRA only |
| 9. Uneven SP Distribution | Sprints must reflect real complexity differences |
| 10. Metrics Disclaimer | Verification metrics labeled as "projected" |
| 11. FR Traceability | Every requirement traces to a concrete source |
| 12. Clean Architecture | Technical spec must show module structure and real file paths |
| 13. Self-Check | Post-generation verification of all 64 rules |
| 14. Codebase Analysis | Must reference actual files from integration plan |
| 15. Honest Verdicts | 5-level taxonomy (STRONG_PASS / PASS / MARGINAL / WEAK / FAIL) |
| 16. Port Compliance | Code examples use injected interfaces, not framework globals |
| 17. Test Traceability | Every test in the matrix must exist with a real body |

## Architecture & code quality rules (18-24)

| Rule | What it enforces |
|---|---|
| 18. Generic Over Specific | Solutions must be parameterized and scalable, not single-purpose |
| 19. No Nested Types | Every struct/class/enum must be a top-level declaration |
| 20. Single Responsibility | Each class has one reason to change, max ~50 lines in examples |
| 21. Explicit Access Control | Visibility modifiers required, minimal public API surface |
| 22. Factory-Based Injection | Dependencies wired through factories/DI, not direct instantiation |
| 23. SOLID Compliance | Single responsibility, open/closed, and dependency inversion enforced |
| 24. Code Reusability | Shared utilities over duplication, consistent naming conventions |

## Security rules (25-32)

| Rule | What it enforces |
|---|---|
| 25. No Hardcoded Secrets | No credentials, API keys, or tokens in code — use env vars, vault, or secret managers |
| 26. Input Validation | Validate and sanitize every external input at system boundaries |
| 27. Injection Prevention | Parameterized queries only, output encoding for XSS, no string concatenation in queries |
| 28. Auth on Every Endpoint | Every operation specifies authentication method, roles, and permission checks |
| 29. Security-Safe Errors | Error responses never leak stack traces, internal paths, or DB schemas |
| 30. Cryptographic Standards | AES-256+ encryption, bcrypt/argon2 for passwords, no MD5/SHA-1/DES |
| 31. Rate Limiting | Throttling strategy for all public-facing endpoints |
| 32. Secure Communication | TLS requirements, certificate management, encrypted data in transit |

## Data protection & compliance rules (33-38)

| Rule | What it enforces |
|---|---|
| 33. Data Classification | Every data entity classified by sensitivity (public/internal/confidential/restricted) |
| 34. PII & Sensitive Data Protection | Encryption at rest, masking in non-prod, anonymization — at least 2 of 3 strategies |
| 35. No Sensitive Data in Logs | PII, credentials, and tokens never appear in log output, error responses, or URLs |
| 36. Data Minimization | Collect only what's necessary, justify each sensitive field with a clear purpose |
| 37. Audit Trail | Who/what/when logging for all security-sensitive operations |
| 38. Consent & Erasure | Data model supports consent tracking, deletion cascades, GDPR/CCPA compliance |

## Error handling & resilience rules (39-43)

| Rule | What it enforces |
|---|---|
| 39. Structured Error Handling | Domain-specific error types, no swallowed exceptions, explicit propagation strategy |
| 40. Resilience Patterns | Circuit breaker, retry with exponential backoff, timeout on every external call |
| 41. Graceful Degradation | Fallback behavior when dependencies fail, no cascading failures |
| 42. Transaction Boundaries | Scope, isolation level, rollback strategy for multi-step operations |
| 43. Consistent Error Format | Standardized error response structure (RFC 7807 or equivalent) |

## Concurrency & state management rules (44-46)

| Rule | What it enforces |
|---|---|
| 44. Concurrency Safety | Shared mutable state protected, thread safety guarantees, race condition prevention |
| 45. Immutability by Default | Prefer immutable data structures, mutable state explicitly justified |
| 46. Atomic Operations | Multi-step state changes must be atomic with defined isolation |

## Senior code quality rules (47-52)

| Rule | What it enforces |
|---|---|
| 47. No Magic Numbers | All literal values in code must be named constants |
| 48. Defensive Coding | Guard clauses, preconditions, null safety, fail fast on invalid state |
| 49. Method Size Limits | No function exceeds ~30 lines in code examples |
| 50. Consistent Naming | Established casing style, descriptive names, no abbreviations in public APIs |
| 51. API Contract Documentation | Every endpoint has typed request/response schemas, status codes, error responses |
| 52. Deprecation Strategy | Breaking changes specify migration path, sunset timeline, versioning approach |

## Comprehensive testing rules (53-58)

| Rule | What it enforces |
|---|---|
| 53. Mandatory Test Coverage | Every public method/endpoint has test specifications with coverage targets |
| 54. Security Testing | SAST/DAST, dependency vulnerability scanning, penetration test plan, OWASP test cases |
| 55. Performance Testing | Load test scenarios, stress thresholds, baseline comparisons, latency percentile targets |
| 56. No Production Data in Tests | All test data must be synthetic/anonymized — no real PII in test fixtures |
| 57. Edge Case & Negative Tests | Tests cover failure scenarios, boundary values, invalid inputs, concurrent operations |
| 58. Test Isolation | No shared mutable state between tests, proper setup/teardown, independent execution |

## Observability & monitoring rules (59-62)

| Rule | What it enforces |
|---|---|
| 59. Structured Logging | JSON format, log levels (DEBUG/INFO/WARN/ERROR), what to log at each level |
| 60. Distributed Tracing | Correlation IDs, trace context propagation across services |
| 61. No PII in Observability | Logs, metrics, and traces must not contain sensitive personal data |
| 62. Alerting Thresholds | Alert triggers, severity levels, escalation paths, on-call routing |

## Dependency & supply chain rules (63-64)

| Rule | What it enforces |
|---|---|
| 63. Dependency Vulnerability Scanning | SCA tooling (Snyk, Dependabot, Trivy) required in CI/CD pipeline |
| 64. Minimal Dependency Principle | New dependencies justified, prefer standard library, license compliance verified |

## Design principles in implementation

Stage 7 (Implementation) and Stage 11 (Verification) enforce scalable design:

- **Parameterize, don't hardcode** — caller-specific values belong in the caller, not in shared code
- **Centralize decisions** — one change should propagate everywhere, not require editing 500 files
- **Compose over specialize** — prefer composable building blocks over single-purpose parameters
- **Backward compatibility via defaults** — new parameters must default to existing behavior
- **Scalability test** — "If three more teams hit a similar problem, would this design handle their cases without changes?"

Stage 11 independently flags violations: hardcoded constants in shared code, single-purpose parameters, bug-specific naming, code duplication, and non-extensible shared components.
