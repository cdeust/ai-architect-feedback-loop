# Implementation Quality Contract
# These rules are enforced by Stage 11 verification. Stage 7 MUST follow them.

## Code Structure
- No function/method exceeds 30 lines of non-blank code (Rule 49)
- No nested type declarations — every struct/class/enum at top level (Rule 19)
- No magic numbers/strings — use named constants (Rule 47)
- Single responsibility — each class/module has one reason to change (Rule 20)

## Error Handling
- Distinct error codes for semantically distinct failure paths (Rules 39, 43)
- No swallowed exceptions — explicit propagation strategy (Rule 39)

## Testing
- Test IDs MUST use UT-/IT-/E2E- prefixes matching prd-tests.md (Rule 53)
- No placeholder test bodies — every test has a real assertion (Rule 7)
- Each new/changed public method has a corresponding test (Rule 53)

## Design Quality
- No caller-specific constants in shared code — use parameters (Rule 18)
- General mechanisms over single-purpose fields (Rule 18)
- Naming reflects what things DO, not what bug they fix (Rule 18)
- Reusable utilities — don't scope helpers to one call site (Rule 24)

## Architecture
- New files placed in correct module per dependency graph
- No unauthorized cross-module imports
- Dependencies injected, not directly instantiated (Rule 22)
