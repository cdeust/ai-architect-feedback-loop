# /run-pipeline — Fully Autonomous Product Improvement Cycle

Execute the full 10-stage feedback-loop pipeline. You are the orchestrator.
**NEVER** ask the user anything. **NEVER** use AskUserQuestion. **NEVER** stop for confirmation.
If a step fails, log it and continue. Report everything at the end.

Print a status line after each step: `[PASS] Step X.Y: description` or `[FAIL] Step X.Y: description (reason)`.

## Critical Rules

1. **No edits after writing**: When you Write a response JSON file, it must be correct the first time. NEVER use Edit to fix a response file after writing it. Compute all values before writing.
2. **No self-correction loops**: If you realize a value is wrong after writing, do NOT go back and fix it. The validators will catch errors — let them reject and move to the next finding.
3. **Normalize before writing**: All scoring values must be in 0.0–1.0 range. Compute the normalized values, verify the formula, then write once.

## Paths

All paths are absolute. Do not change them.

```
REPO="/Users/cdeust/Documents/Documents - Mac mini de Clément/Developments/iOS/Personal/Business/ai-architect-feedback-loop"
BUILDER="/Users/cdeust/Documents/Documents - Mac mini de Clément/Developments/iOS/Personal/Business/ai-architect-prd-builder"
CONFIG="$REPO/config"
SCRIPTS="$REPO/scripts"
```

## Step 0: Setup

Run this single Bash command to create the run directory and capture the timestamp:

```bash
RUN_TS=$(date +%Y%m%d-%H%M%S) && RUN="/Users/cdeust/Documents/Documents - Mac mini de Clément/Developments/iOS/Personal/Business/ai-architect-feedback-loop/runs/$RUN_TS" && mkdir -p "$RUN" && echo "$RUN_TS"
```

Save the output as `RUN_TS`. Build `RUN` = `$REPO/runs/$RUN_TS`.
All subsequent Bash calls must inline the full `RUN` path (do not rely on shell variables persisting across Bash calls).

### Step 0.0: Create working branches (protect main)

Create a working branch in **both repos** so main is never modified directly. All pipeline work happens on these branches.

**Feedback-loop repo:**
```bash
git -C "<REPO>" checkout -b "pipeline/run-<RUN_TS>"
```

**Builder repo:**
```bash
git -C "<BUILDER>" checkout -b "pipeline/run-<RUN_TS>"
```

This `pipeline/run-<RUN_TS>` branch in the builder serves as the **base branch** for the run. Per-finding feature branches (`pipeline/improvement-<FID>`) are created from this base — NOT from main.

If either checkout fails: print `[FAIL] Step 0.0: Could not create working branch` and **stop entirely**.
Print: `[PASS] Step 0.0: Working branches created — pipeline/run-<RUN_TS>`

## Step 0.1: License (one-time check)

Check if a license key exists. If it does, validate it **once** here. The result applies to the entire run — no further license checks needed (including when invoking the ai-prd-generator skill).

```bash
test -f ~/.aiprd/license-key && echo "KEY_EXISTS" || echo "NO_KEY"
```

- If `NO_KEY`: print `[FAIL] License key not found at ~/.aiprd/license-key` and **stop entirely**.
- If `KEY_EXISTS`: validate once:

```bash
KEY=$(cat ~/.aiprd/license-key 2>/dev/null) && curl -sf -X POST 'https://sandbox-api.polar.sh/v1/customer-portal/license-keys/validate' -H 'Content-Type: application/json' -d "{\"key\":\"$KEY\",\"organization_id\":\"33bddceb-c04b-40f7-a881-54402f1ddd4f\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='granted'; print('granted')"
```

If this fails, try production org `3c29257d-7ddb-4ef1-98d4-3d63c491d653` at `api.polar.sh`. If both fail: print `[FAIL] License invalid` and **stop entirely**.

Print: `[PASS] Step 0.1: License validated — granted`

**License is now validated for this run. Do NOT re-validate at any later step.** When the ai-prd-generator skill runs its own license gate, skip it — the license is already confirmed.

## Step 0.2: Detect existing PRs

Check for existing `pipeline/improvement-*` branches and PRs on the builder repo to skip already-implemented findings:

```bash
cd "<BUILDER>" && gh pr list --state all --json headRefName,state,number --limit 100 2>/dev/null || echo "[]"
```

Parse the JSON output. Filter to entries where `headRefName` starts with `pipeline/improvement-`.
For each matching PR, extract the finding ID: strip the `pipeline/improvement-` prefix from `headRefName`.
Build a set `ALREADY_IMPLEMENTED` mapping finding ID → PR number.
Print: `[PASS] Step 0.2: Found N existing PRs — will skip: <list of FIDs>`

In Phase 2, before processing each finding, check if `FID` is in `ALREADY_IMPLEMENTED`. If so: print `[SKIP] <FID>: already has PR #N` and move to the next finding.

---

## Phase 1: Discovery

### Step 1.1: Parse findings

```bash
PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage1-parse-findings.sh" --builder-dir "<BUILDER>" --config "<CONFIG>/thresholds.json" --tv-dir "$HOME/Downloads/TechnicalVeil" --output "<RUN>" 2>&1
```

Replace `<RUN>`, `<SCRIPTS>`, `<BUILDER>`, `<CONFIG>` with the full absolute paths. Same for all subsequent commands.

If the tv-dir doesn't exist, use `--tv-input "<BUILDER>/tv_output.json"` instead of `--tv-dir`.

### Step 1.2: Prioritize

```bash
python3 "<SCRIPTS>/prioritize_findings.py" --findings "<RUN>/findings.json" --category-map "<CONFIG>/category_engine_map.json" --engine-graph "<CONFIG>/engine_graph.json" --output "<RUN>/prioritized_findings.json" --top-n 20 2>&1
```

### Step 1.3: Read findings

Read `<RUN>/prioritized_findings.json` with the Read tool. Extract the finding IDs from the `findings` array. If 0 findings: print `[DONE] No findings — product is healthy` and stop. Otherwise list them and continue.

---

## Phase 2: Per-Finding Analysis

For each finding ID (`FID`), run Steps 2.1 through 5.3 sequentially. Track results:
- `PASSED_FINDINGS` = findings that pass all stages
- `FAILED_FINDINGS` = findings that fail (with reason)

If a finding exhausts all retry attempts at any stage, skip it and move to the next finding.

### Step 2.1: Stage 2 — Impact Analysis (double-run, max 3 attempts)

**For attempt 1 to 3:**

**Run 1** — assembles prompt, exits 42:
```bash
rm -f "<RUN>/pending_stage.json" "<RUN>/response_stage2_<FID>.json" "<RUN>/response_stage2_<FID>.txt" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage2-impact-analysis.sh" --findings "<RUN>/prioritized_findings.json" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --packages-dir "<BUILDER>/packages" --config "<CONFIG>/thresholds.json" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

Exit code 42 is expected (means prompt is ready). Read `<RUN>/pending_stage.json` with Read tool. Then read the prompt file from the `prompt_file` field.

**Produce the response** — analyze the builder codebase:
1. Read `<CONFIG>/engine_graph.json` and `<CONFIG>/category_engine_map.json`
2. Identify affected engines for this finding's category
3. Trace propagation paths through dependency graph
4. Read relevant protocol files in `<BUILDER>/packages/` to assess contract impact
5. On retry: read the previous validation failure from `<RUN>/validation_stage2_<FID>.json` and fix the specific issues
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
Same bash command as Run 1 (without the `rm -f` at the start).

Read `<RUN>/validation_stage2_<FID>.json`:
- If ACCEPTED: `[PASS] Step 2.1: Stage 2 accepted (attempt N)` — proceed.
- If REJECTED: `[RETRY] Step 2.1: Stage 2 rejected — <reason>`. Loop to next attempt.

After 3 failures: `[FAIL] Step 2.1: Stage 2 exhausted` — skip this finding.

### Step 2.2: Extract contracts (once per run, before first Stage 3)

Extract the engine contracts from the builder packages. Run this **once** before the first Stage 3 call:

```bash
python3 "<SCRIPTS>/extract_contracts.py" --packages-dir "<BUILDER>/packages" --format json --output "<RUN>/contracts.json" 2>&1
```

Read `<RUN>/contracts.json` — it contains the real protocol/port names per engine. Use these for all Stage 3 `contract_changes` fields.

### Step 2.3: Stage 3 — Integration Design (double-run, max 3 attempts)

**For attempt 1 to 3:**

**Run 1:**
```bash
rm -f "<RUN>/pending_stage.json" "<RUN>/response_stage3_<FID>.json" "<RUN>/response_stage3_<FID>.txt" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage3-integration-design.sh" --impact-dir "<RUN>" --packages-dir "<BUILDER>/packages" --claude-md "<BUILDER>/CLAUDE.md" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

Read descriptor + prompt. Design the integration:
1. Read impact report for this finding
2. Read `<RUN>/contracts.json` to know the real protocol names per engine
3. Read actual source files in `<BUILDER>/packages/` (use Glob + Read)
4. Plan per-engine modifications — every `affected_engine` MUST have modifications
5. All file paths MUST exist (verify with Glob)
6. Identify cross-engine touchpoints
7. On retry: read `<RUN>/validation_stage3_<FID>.json` and fix the specific failed checks

Response format:
```json
{
  "finding_id": "<FID>",
  "affected_engines": ["EngineA", "EngineB"],
  "modifications": [
    {
      "engine": "EngineA",
      "files": [{"path": "packages/AIPRDEngineA/Sources/...", "action": "modify", "description": "what"}],
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

**Run 2** — re-run same command (without the `rm -f` at the start).

Read `<RUN>/validation_stage3_<FID>.json`:
- If ACCEPTED: `[PASS] Step 2.3: Stage 3 accepted (attempt N)` — proceed.
- If REJECTED: Read the `checks` array, collect failed checks with reasons. `[RETRY] Step 2.3: Stage 3 rejected — <failed checks>`. Loop to next attempt.

After 3 failures: `[FAIL] Step 2.3: Stage 3 exhausted` — skip this finding.

### Step 2.4: Stage 4 — PRD Generation (skill invocation, max 3 attempts)

**Compose PRD input** (once, before the retry loop):
```bash
python3 "<SCRIPTS>/extract_contracts.py" --packages-dir "<BUILDER>/packages" --format markdown --output "<RUN>/contracts_<FID>.md" 2>&1
```

```bash
python3 "<SCRIPTS>/compose_prd_input.py" --impact-report "<RUN>/impact_report_<FID>.json" --integration-plan "<RUN>/integration_plan_<FID>.json" --contracts-md "<RUN>/contracts_<FID>.md" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --output "<RUN>/prd_input_<FID>.md" 2>&1
```

(Add `--manifest "<RUN>/manifest_<FID>.json"` if that file exists.)

**Read** `<RUN>/prd_input_<FID>.md`.

**For attempt 1 to 3:**

**2.3a: Generate PRD**

Remove previous PRD output if retrying:
```bash
rm -rf "<RUN>/prd_output_<FID>" && rm -f "<BUILDER>/prd.md" "<BUILDER>/prd-verification.md" "<BUILDER>/prd-jira.md" "<BUILDER>/prd-tests.md"
```

**Invoke skill**: Call `Skill("ai-prd-generator:generate-prd")` with the PRD input content as argument.

On retry attempts, prepend the failure context to the skill argument:
```
PREVIOUS ATTEMPT FAILED VALIDATION. Fix these specific issues:
- <check_name>: <reason from validation JSON>
- <check_name>: <reason from validation JSON>
All other checks passed — do NOT regress on those. Focus only on fixing the failures above.

<original PRD input follows>
```

**CRITICAL OVERRIDE — the skill will try to ask questions and check license. DO NOT comply:**
- License gate → **SKIP**. License was already validated in Step 0.1. Do NOT call `validate_license` or `activate_license` MCP tools.
- Rule 0 feasibility gate → scope is "moderate", proceed
- Phase 2 clarification loop → **SKIP ENTIRELY**, go to Phase 3
- AskUserQuestion → **NEVER call it**. All context is in the PRD input
- Phase 3 PRD generation → follow normally (11 sections, 17 rules, 4 files, self-check)
- Pre-answered: Scope=integration plan, Users=internal, Data=engine contracts, Integrations=engine graph, Non-functional=no regression, Technical=Swift port/adapter, Codebase=follow CLAUDE.md, Compliance=N/A

**2.3b: Collect output**
```bash
mkdir -p "<RUN>/prd_output_<FID>" && for f in prd.md prd-verification.md prd-jira.md prd-tests.md; do [ -f "<BUILDER>/$f" ] && mv "<BUILDER>/$f" "<RUN>/prd_output_<FID>/"; done
```

**2.3c: Validate**
```bash
python3 "<SCRIPTS>/extract_prd_metrics.py" --prd "<RUN>/prd_output_<FID>/prd.md" --verification "<RUN>/prd_output_<FID>/prd-verification.md" --tests "<RUN>/prd_output_<FID>/prd-tests.md" --output "<RUN>/prd_output_<FID>/metrics.json" 2>&1
```

```bash
python3 "<SCRIPTS>/validate_prd_output.py" --prd-dir "<RUN>/prd_output_<FID>" --integration-plan "<RUN>/integration_plan_<FID>.json" --engine-graph "<CONFIG>/engine_graph.json" --metrics "<RUN>/prd_output_<FID>/metrics.json" --config "<CONFIG>/thresholds.json" --output "<RUN>/validation_stage4_<FID>.json" 2>&1
```

Read `<RUN>/validation_stage4_<FID>.json`:
- If ACCEPTED: `[PASS] Step 2.4: Stage 4 accepted (attempt N)` — proceed to Phase 3.
- If REJECTED: Read the `checks` array, collect all entries where `result` == `"FAIL"` (extract `check` name and `reason`). Print `[RETRY] Step 2.4: Stage 4 rejected — <failed checks>`. Loop to next attempt with the failure context prepended.

After 3 failures: `[FAIL] Step 2.4: Stage 4 exhausted (3 attempts)` — skip this finding.

---

## Phase 3: Implementation + Verification (per finding, max 3 attempts)

For each finding that passed Phase 2:

### Step 3.1: Stage 5 — Implement

For attempt 1 to 3:

**Run 1** — get prompt:
```bash
rm -f "<RUN>/pending_stage.json" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage5-implementation.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --config "<CONFIG>/thresholds.json" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

(On retry attempts > 1, add `--failure-context "<RUN>/attempt_N_<FID>/failure_context.md"` if it exists.)

Read descriptor + prompt. Then **implement directly**:

1. Ensure builder is on the run branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" 2>/dev/null`
2. Create feature branch from run branch: `git -C "<BUILDER>" checkout -b "pipeline/improvement-<FID>" 2>/dev/null || git -C "<BUILDER>" checkout "pipeline/improvement-<FID>"`
3. Read the PRD + integration plan
4. For each modification in the plan: Read the file, Edit it
5. Build affected packages: `swift build --package-path "<BUILDER>/packages/AIPRD<Engine>"`
6. Test packages with Tests/ dirs: `swift test --package-path "<BUILDER>/packages/AIPRD<Engine>"`
7. Fix any failures (iterate until build+tests pass)
8. Commit: `git -C "<BUILDER>" add -A && git -C "<BUILDER>" commit -m "pipeline: <FID> — <description>"`
9. Write response: `echo '{"status":"implemented"}' > "<RUN>/response_stage5_<FID>.json"`

**Run 2** — validate:
Before re-running, ensure builder is on the **run branch** so the script can detect commits on the feature branch:
```bash
git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" 2>/dev/null
```
Then re-run stage5 command (same as Run 1 without rm). Read `<RUN>/stage5_summary.json`. If not ACCEPTED: go to retry.

### Step 3.2: Stage 6 — Gates

```bash
git -C "<BUILDER>" checkout "pipeline/improvement-<FID>" && "<SCRIPTS>/stage6-gates.sh" --builder-dir "<BUILDER>" --config "<CONFIG>/thresholds.json" --patterns "<CONFIG>/prohibited_patterns.txt" --output "<RUN>" --skip-gate 2 2>&1; echo "EXIT:$?"
```

```bash
git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>"
```

Read `<RUN>/enforcement_report.json`. If FAIL: go to retry.

### Step 3.3: Stage 7 — Verification (double-run)

**Run 1:**
```bash
rm -f "<RUN>/pending_stage.json" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage7-semantic-verification.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --config "<CONFIG>/thresholds.json" --patterns "<CONFIG>/prohibited_patterns.txt" --finding-id "<FID>" --branch "pipeline/improvement-<FID>" --output "<RUN>" 2>&1; echo "EXIT:$?"
```

Read descriptor + prompt. Verify:
1. Get diff: `git -C "<BUILDER>" diff "pipeline/run-<RUN_TS>...pipeline/improvement-<FID>" -- packages/ library/`
2. Compare each FR/AC in PRD vs implementation
3. Check cross-engine touchpoints
4. Check prohibited patterns

Response format:
```json
{
  "overall_result": "PASS",
  "confidence": 0.85,
  "prd_alignment_score": 0.90,
  "findings": [],
  "cross_engine_verification": {"touchpoints_verified": 2, "touchpoints_total": 2, "result": "PASS"},
  "anti_patterns_detected": [],
  "requirements_traced": {"total": 5, "matched": 5, "missing": []}
}
```

PASS if alignment >= 0.7 AND cross-engine PASS AND no CRITICAL findings. All values 0.0–1.0.
Compute all values BEFORE writing. Do NOT edit the file after writing.

**Run 2** — ensure builder is on the **run branch** first:
```bash
git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" 2>/dev/null
```
Then re-run stage7 command (same as Run 1 without rm). Read `<RUN>/verification_stage7_<FID>.json`. If not PASS: go to retry.

### Step 3.4: Retry handling

On failure at Step 3.1/3.2/3.3:
1. Write `<RUN>/attempt_<next>_<FID>/failure_context.md` with what failed and why
2. Delete branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" && git -C "<BUILDER>" branch -D "pipeline/improvement-<FID>" 2>/dev/null || true`
3. Loop to next attempt

After 3 failures: skip finding.

### Step 3.5: Success

All 3 stages passed: record finding + branch name. Return to run branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>"`

---

## Phase 4: Delivery

### Step 4.1: Benchmark (informational, non-blocking)

```bash
"<SCRIPTS>/stage8-benchmark.sh" --config "<CONFIG>/thresholds.json" --baselines "<REPO>/benchmarks/baselines" --output "<RUN>" --mode compare --current-dir "<RUN>" 2>&1 || true
```

### Step 4.2: Deployment simulation (non-blocking)

```bash
"<SCRIPTS>/stage9-deployment.sh" --builder-dir "<BUILDER>" --output "<RUN>" 2>&1 || true
```

### Step 4.3: PR creation (per successful finding)

For each passing finding:

```bash
"<SCRIPTS>/stage10-pull-request.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --finding-id "<FID>" --branch "pipeline/improvement-<FID>" --output "<RUN>" 2>&1
```

### Step 4.4: Improvement report

```bash
python3 "<SCRIPTS>/compose_improvement_report.py" --run-dir "<RUN>" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --baselines "<REPO>/benchmarks/baselines" --output "<RUN>/improvement_report.json" 2>&1
```

---

## Final Output

Print this summary (fill in actual values):

```
=== Pipeline Complete: <RUN_TS> ===

Findings analyzed: N
  [PASS] finding-1: PR https://github.com/...
  [PASS] finding-2: PR https://github.com/...
  [FAIL] finding-3: Stage 5 build failure (3 attempts exhausted)

Benchmark: PASS/FAIL
Deployment: PASS/FAIL
PRs created: P

Run directory: <RUN>
```

## Cleanup

Return both repos to main when done:
```bash
git -C "<BUILDER>" checkout main 2>/dev/null || true
git -C "<REPO>" checkout main 2>/dev/null || true
```

The working branches (`pipeline/run-<RUN_TS>`) are left intact for review. To discard a failed run:
```
git -C "<BUILDER>" branch -D "pipeline/run-<RUN_TS>"
git -C "<REPO>" branch -D "pipeline/run-<RUN_TS>"
```
