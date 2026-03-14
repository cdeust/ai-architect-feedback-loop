# Phase 2: Per-Finding Analysis

For each finding ID (`FID`), run Steps 2.1 through 5.3 sequentially. Track results:
- `PASSED_FINDINGS` = findings that pass all stages
- `FAILED_FINDINGS` = findings that fail (with reason)

If a finding exhausts all retry attempts at any stage, skip it and move to the next finding.

## Step 2.1: Stage 2 — Impact Analysis (double-run, max 3 attempts)

**For attempt 1 to 3:**

**Run 1** — assembles prompt, exits 42:
```bash
mkdir -p "<RUN>/findings/<FID>" && rm -f "<RUN>/pending_stage.json" "<RUN>/findings/<FID>/response_stage2.json" "<RUN>/findings/<FID>/response_stage2.txt" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage2-impact-analysis.sh" --findings "<RUN>/prioritized_findings.json" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --packages-dir "<PACKAGES_DIR>" --config "<CONFIG>/thresholds.json" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

Exit code 42 is expected (means prompt is ready). Read `<RUN>/pending_stage.json` with Read tool. Then read the prompt file from the `prompt_file` field.

**Produce the response** — analyze the builder codebase:
1. Read `<CONFIG>/engine_graph.json` and `<CONFIG>/category_engine_map.json`
2. Identify affected engines for this finding's category
3. Trace propagation paths through dependency graph
4. Read relevant protocol files in `<PACKAGES_DIR>/` to assess contract impact
5. On retry: read the previous validation failure from `<RUN>/findings/<FID>/stage2-validation.json` and fix the specific issues
6. Write response JSON to the `expected_response` path from the descriptor

Response format:
```json
{
  "finding_id": "<FID>",
  "engines_affected": 3,
  "compound_score": 0.36,
  "affected_engines": ["EngineA", "EngineB"],
  "propagation_paths": [
    {"from": "A", "to": "B", "order": 1, "mechanism": "description"}
  ],
  "scoring_breakdown": {
    "engines_affected": {"value": 0.33, "weight": 0.3},
    "propagation_depth": {"value": 0.40, "weight": 0.2},
    "contract_impact": {"value": 0.70, "weight": 0.3},
    "test_coverage_delta": {"value": 0.40, "weight": 0.2}
  },
  "recommendation": "PROCEED",
  "rationale": "explanation"
}
```

**Scoring rules** (the validator recomputes `compound_score` as `sum(value * weight)` — it MUST match):
- `engines_affected.value` = (number of engines) / 9, clamped to 0.0–1.0. Weight = 0.3.
- `propagation_depth.value` = (max propagation depth) / 5, clamped to 0.0–1.0. Weight = 0.2.
- `contract_impact.value` = estimated contract disruption, 0.0–1.0. Weight = 0.3.
- `test_coverage_delta.value` = estimated test coverage change, 0.0–1.0. Weight = 0.2.
- `compound_score` = sum of (value × weight) for all 4 dimensions. All values MUST be in 0.0–1.0 range.
- Recommendation = "PROCEED" if compound_score >= 0.3 AND engines_affected >= 2; otherwise "REJECT".

Compute the score BEFORE writing. Do NOT edit the file after writing.

**Run 2** — re-run same command (response file now exists, script validates):
Same bash command as Run 1 but without `rm -f` of response files. Keep the `echo "EXIT:$?"` suffix. **Non-zero exit codes are normal for REJECTED results — always read the validation JSON.**

Read `<RUN>/findings/<FID>/stage2-validation.json`:
- If ACCEPTED: `[PASS] Step 2.1: Stage 2 accepted (attempt N)` — proceed.
- If REJECTED: Read the `reason` field. `[RETRY] Step 2.1: Stage 2 rejected — <reason>`. Loop to next attempt.

After 3 failures: `[FAIL] Step 2.1: Stage 2 exhausted` — skip this finding.

## Step 2.2: Extract contracts (once per run, before first Stage 3)

Extract the engine contracts from the builder packages. Run this **once** before the first Stage 3 call:

```bash
python3 "<SCRIPTS>/extract_contracts.py" --packages-dir "<PACKAGES_DIR>" --format json --output "<RUN>/contracts.json" 2>&1
```

Read `<RUN>/contracts.json` — it contains the real protocol/port names per engine. Use these for all Stage 3 `contract_changes` fields.

## Step 2.3: Stage 3 — Integration Design (double-run, max 3 attempts)

**For attempt 1 to 3:**

**Run 1:**
```bash
rm -f "<RUN>/pending_stage.json" "<RUN>/findings/<FID>/response_stage3.json" "<RUN>/findings/<FID>/response_stage3.txt" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage3-integration-design.sh" --impact-dir "<RUN>" --packages-dir "<PACKAGES_DIR>" --claude-md "<BUILDER>/CLAUDE.md" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

(If `<BUILDER>/CLAUDE.md` doesn't exist, pass `--claude-md /dev/null` instead.)

Read descriptor + prompt. Design the integration:
1. Read impact report for this finding
2. Read `<RUN>/contracts.json` to know the real protocol names per engine
3. Read actual source files in `<PACKAGES_DIR>/` (use Glob + Read)
4. Plan per-engine modifications — every `affected_engine` MUST have modifications
5. All file paths MUST exist (verify with Glob)
6. Identify cross-engine touchpoints
7. On retry: read `<RUN>/findings/<FID>/stage3-validation.json` and fix the specific failed checks

Response format:
```json
{
  "finding_id": "<FID>",
  "affected_engines": ["EngineA", "EngineB"],
  "modifications": [
    {
      "engine": "EngineA",
      "files": [{"path": "module_a/src/...", "action": "modify", "description": "what"}],
      "contract_changes": [{"protocol": "Name", "change": "add method", "description": "what"}]
    }
  ],
  "cross_engine_touchpoints": [
    {"from": "A", "to": "B", "via": "PortName", "description": "how"}
  ],
  "new_files": [],
  "test_files": [],
  "constraints": {"no_new_packages": true, "no_standalone_modules": true, "existing_dependency_graph_only": true}
}
```

**contract_changes rules:**
- The `protocol` field MUST be a real protocol name from the extracted `<RUN>/contracts.json` (e.g. `RAGEngineProtocol`, `MetaPromptingEngineProtocol`). NEVER use `"N/A"`, `"none"`, or placeholder names.
- If an engine modification does NOT change any protocol (e.g. DTO-only or internal-only changes), use an **empty array**: `"contract_changes": []`
- Only list contract_changes when an actual protocol method signature or port interface changes.

All file paths in `modifications[].files[].path` MUST exist in the builder repo (verify with Glob before writing).
Every engine in `affected_engines` MUST have at least one entry in `modifications`.
Compute the full response BEFORE writing. Do NOT edit the file after writing.

**Run 2** — re-run same command but without `rm -f` of response files. Keep the `echo "EXIT:$?"` suffix. **Non-zero exit codes are normal for REJECTED results — always read the validation JSON.**

Read `<RUN>/findings/<FID>/stage3-validation.json`:
- If ACCEPTED: `[PASS] Step 2.3: Stage 3 accepted (attempt N)` — proceed.
- If REJECTED: Read the `checks` array, collect failed checks with reasons. `[RETRY] Step 2.3: Stage 3 rejected — <failed checks>`. Loop to next attempt.

After 3 failures: `[FAIL] Step 2.3: Stage 3 exhausted` — skip this finding.

## Step 2.4: Stage 5 — PRD Generation (skill invocation, max 3 attempts)

**Compose PRD input** (once, before the retry loop):
```bash
python3 "<SCRIPTS>/extract_contracts.py" --packages-dir "<PACKAGES_DIR>" --format markdown --output "<RUN>/contracts_<FID>.md" 2>&1
```

```bash
python3 "<SCRIPTS>/compose_prd_input.py" --impact-report "<RUN>/findings/<FID>/stage2-impact.json" --integration-plan "<RUN>/findings/<FID>/stage3-integration.json" --contracts-md "<RUN>/contracts_<FID>.md" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --output "<RUN>/prd_input_<FID>.md" 2>&1
```

(Add `--manifest "<RUN>/findings/<FID>/stage3-manifest.json"` if that file exists.)

**Read** `<RUN>/prd_input_<FID>.md`.

**For attempt 1 to 3:**

**2.3a: Generate PRD**

Remove previous PRD output if retrying:
```bash
rm -rf "<RUN>/findings/<FID>/stage5-prd" && rm -f "<BUILDER>/prd.md" "<BUILDER>/prd-verification.md" "<BUILDER>/prd-jira.md" "<BUILDER>/prd-tests.md"
```

**BEFORE calling the skill**, determine the scope from the pipeline artifacts:

**Scope derivation** (from Stage 2 impact report + Stage 3 integration plan for this finding):
- Count total files across all `modifications[].files[]` in the integration plan
- Count `affected_engines` from the impact report
- Read the finding description for architectural significance

| Engines | Files | Architectural change? | Scope |
|---------|-------|-----------------------|-------|
| 1–2 | ≤ 3 | No | simple |
| 2–4 | 4–10 | No | moderate |
| 4+ | 10+ | OR introduces new strategy/pattern/replaces existing approach | complex |

Record the derived scope as `FINDING_SCOPE` for this finding.

**Now remember these overrides.** When the skill's SKILL.md loads, it will instruct you to do things. You MUST override them:

| SKILL.md says | YOU DO INSTEAD |
|---|---|
| Validate/activate license | **SKIP ENTIRELY**. License confirmed in Step 0.1. Do NOT call `validate_license`, `activate_license`, or `get_license_features` MCP tools. Do NOT read license files. |
| Rule 0 feasibility gate (AskUserQuestion) | **SKIP the question**. Use `FINDING_SCOPE` (derived above). If "complex", the skill may select a more thorough generation strategy — that's fine, just don't ask the user. |
| Phase 2 clarification loop (AskUserQuestion) | **SKIP ENTIRELY**. Go straight to Phase 3 PRD generation. |
| Any AskUserQuestion call | **NEVER call it**. All context is in the PRD input. |

When the skill loads, jump directly to **Phase 3: PRD Generation** using context type "feature" (11 sections). Follow the skill's 17 hard output rules and self-check normally. Pass the derived `FINDING_SCOPE` as the scope context.

Pre-answered context: Scope=`FINDING_SCOPE` (derived above) with details from integration plan, Users=internal, Data=module contracts, Integrations=module dependency graph, Non-functional=no regression, Technical=follow CLAUDE.md, Codebase=follow CLAUDE.md, Compliance=N/A.

**Invoke skill**: Call `Skill("ai-prd-generator:generate-prd")` with the PRD input content as argument.

On retry attempts, prepend failure context to the skill argument:
```
PREVIOUS ATTEMPT FAILED VALIDATION. Fix these specific issues:
- <check_name>: <reason from validation JSON>
All other checks passed — do NOT regress on those. Focus only on fixing the failures above.

<original PRD input follows>
```

**2.3b: Collect output**
```bash
mkdir -p "<RUN>/findings/<FID>/stage5-prd" && for f in prd.md prd-verification.md prd-jira.md prd-tests.md; do [ -f "<BUILDER>/$f" ] && mv "<BUILDER>/$f" "<RUN>/findings/<FID>/stage5-prd/"; done
```

**2.3c: Validate**
```bash
python3 "<SCRIPTS>/extract_prd_metrics.py" --prd "<RUN>/findings/<FID>/stage5-prd/prd.md" --verification "<RUN>/findings/<FID>/stage5-prd/prd-verification.md" --tests "<RUN>/findings/<FID>/stage5-prd/prd-tests.md" --output "<RUN>/findings/<FID>/stage5-prd/metrics.json" 2>&1
```

```bash
python3 "<SCRIPTS>/validate_prd_output.py" --prd-dir "<RUN>/findings/<FID>/stage5-prd" --integration-plan "<RUN>/findings/<FID>/stage3-integration.json" --engine-graph "<CONFIG>/engine_graph.json" --metrics "<RUN>/findings/<FID>/stage5-prd/metrics.json" --config "<CONFIG>/thresholds.json" --output "<RUN>/findings/<FID>/stage5-validation.json" 2>&1; true
```

Read `<RUN>/findings/<FID>/stage5-validation.json`:
- If ACCEPTED: `[PASS] Step 2.4: Stage 5 accepted (attempt N)` — proceed to Phase 3.
- If REJECTED: Read the `checks` array, collect all entries where `result` == `"FAIL"` (extract `check` name and `reason`). Print `[RETRY] Step 2.4: Stage 5 rejected — <failed checks>`. Loop to next attempt with the failure context prepended.

After 3 failures: `[FAIL] Step 2.4: Stage 5 exhausted (3 attempts)` — skip this finding.
