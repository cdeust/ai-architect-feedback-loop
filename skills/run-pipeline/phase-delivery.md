# Phase 3: Implementation + Verification (per finding, max 3 attempts)

For each finding that passed Phase 2:

## Step 3.1: Stage 7 — Implement

For attempt 1 to 3:

**Run 1** — get prompt:
```bash
rm -f "<RUN>/pending_stage.json" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage7-implementation.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --config "<CONFIG>/thresholds.json" --output "<RUN>" --finding-id "<FID>" 2>&1; echo "EXIT:$?"
```

(On retry attempts > 1, add `--failure-context "<RUN>/findings/<FID>/attempts/N/failure_context.md"` if it exists.)

Read descriptor + prompt. Then **implement directly**:

1. Ensure builder is on the run branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" 2>/dev/null`
2. Create feature branch from run branch: `git -C "<BUILDER>" checkout -b "pipeline/improvement-<FID>" 2>/dev/null || git -C "<BUILDER>" checkout "pipeline/improvement-<FID>"`
3. Read the PRD + integration plan
4. **Decompose into work units:** Read the integration plan's `modifications[]` array. Group by engine — each engine's modifications become one work unit. For each work unit:
   - Identify the files to modify
   - Extract the relevant PRD sections for that engine
   - Implement the file changes (Read file, Edit it)
   - Commit per-engine changes separately for reviewability
5. After all work units: verify the full diff against the PRD (reviewer step — check cross-engine consistency)
6. For each modification in the plan: Read the file, Edit it (if not already done via work unit decomposition)
5. Build: Use `BUILD_CMD` (read from `project.json` in Step 0), run in BUILDER:
   ```bash
   cd "<BUILDER>" && eval "<BUILD_CMD>"
   ```
   - **If build fails: read the error output, fix the code, rebuild. Repeat until build succeeds.**
   - Do NOT move on, do NOT skip. Fix the build errors in-place on the feature branch.

6. Test: Use `TEST_CMD` (read from `project.json` in Step 0), run in BUILDER:
   ```bash
   cd "<BUILDER>" && eval "<TEST_CMD>"
   ```
   - **If tests fail: read the error output, fix the code or tests, re-run. Repeat until tests pass.**
   - Do NOT move on, do NOT skip. Fix test failures in-place on the feature branch.

7. Only after build AND tests pass:
   Commit using `COMMIT_MESSAGE` pattern (replace `{finding_id}` with `<FID>`, `{description}` with a brief description): `git -C "<BUILDER>" add -A && git -C "<BUILDER>" commit -m "<COMMIT_MESSAGE>"`
8. Write response: `echo '{"status":"implemented"}' > "<RUN>/findings/<FID>/response_stage7.json"`

**CRITICAL: Build and test failures are NOT stage failures — they are implementation bugs you must fix before proceeding. Only move to retry (next attempt) if Run 2 validation rejects, or if Stage 10/11 rejects. Never skip a finding because of a build error.**

**Run 2** — validate:
Before re-running, ensure builder is on the **run branch** so the script can detect commits on the feature branch:
```bash
git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" 2>/dev/null
```
Then re-run stage7 command (same as Run 1 without rm). Read `<RUN>/stage7_summary.json`. If not ACCEPTED: go to retry.

## Step 3.2: Stage 10 — Gates

Run in the **foreground** with a 10-minute timeout (`timeout: 600000`). Do NOT use `run_in_background`.

Skip gates 2, 5, and 6:
- Gate 2: build diff (skipped, redundant with Gate 4)
- Gate 5: test suite (tests already ran in Step 3.1)
- Gate 6: deployment integrity (checked separately in Step 4.2)

```bash
git -C "<BUILDER>" checkout "pipeline/improvement-<FID>" && "<SCRIPTS>/stage10-gates.sh" --builder-dir "<BUILDER>" --config "<CONFIG>/thresholds.json" --patterns "<CONFIG>/prohibited_patterns.txt" --output "<RUN>" --skip-gate 2 --skip-gate 5 --skip-gate 6 2>&1; echo "EXIT:$?"
```

```bash
git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>"
```

Read `<RUN>/enforcement_report.json`. If the file doesn't exist (script crashed/timed out), write a manual report based on what gates completed and proceed. If result is FAIL on Gates 1, 3, or 4: go to retry.

## Step 3.3: Stage 11 — Verification (double-run)

**Run 1:**
```bash
rm -f "<RUN>/pending_stage.json" "<RUN>/findings/<FID>/response_stage11.json" "<RUN>/findings/<FID>/response_stage11.txt" && PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage11-semantic-verification.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --config "<CONFIG>/thresholds.json" --patterns "<CONFIG>/prohibited_patterns.txt" --finding-id "<FID>" --branch "pipeline/improvement-<FID>" --output "<RUN>" 2>&1; echo "EXIT:$?"
```

Read descriptor + prompt. Verify:
1. Get diff: `git -C "<BUILDER>" diff "pipeline/run-<RUN_TS>...pipeline/improvement-<FID>"`
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
Then re-run stage11 command (same as Run 1 without rm). Read `<RUN>/findings/<FID>/stage11-verification.json`. If not PASS: go to retry.

## Step 3.4: Retry handling

On failure at Step 3.1/3.2/3.3:
1. Write `<RUN>/findings/<FID>/attempts/<next>/failure_context.md` with what failed and why
2. Delete branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>" && git -C "<BUILDER>" branch -D "pipeline/improvement-<FID>" 2>/dev/null || true`
3. Loop to next attempt

After 3 failures: skip finding.

## Step 3.5: Success

All 3 stages passed: record finding + branch name. Return to run branch: `git -C "<BUILDER>" checkout "pipeline/run-<RUN_TS>"`

---

# Phase 4: Delivery

## Step 4.1: Benchmark (informational, non-blocking)

```bash
"<SCRIPTS>/stage12-benchmark.sh" --config "<CONFIG>/thresholds.json" --baselines "<REPO>/benchmarks/baselines" --output "<RUN>" --mode compare --current-dir "<RUN>" 2>&1 || true
```

## Step 4.2: Deployment simulation (non-blocking)

```bash
"<SCRIPTS>/stage13-deployment.sh" --builder-dir "<BUILDER>" --output "<RUN>" 2>&1 || true
```

## Step 4.3: PR creation (per successful finding)

For each passing finding:

```bash
"<SCRIPTS>/stage14-pull-request.sh" --run-dir "<RUN>" --builder-dir "<BUILDER>" --engine-graph "<CONFIG>/engine_graph.json" --finding-id "<FID>" --branch "pipeline/improvement-<FID>" --output "<RUN>" 2>&1
```

## Step 4.4: Improvement report

```bash
python3 "<SCRIPTS>/compose_improvement_report.py" --run-dir "<RUN>" --engine-graph "<CONFIG>/engine_graph.json" --category-map "<CONFIG>/category_engine_map.json" --baselines "<REPO>/benchmarks/baselines" --output "<RUN>/improvement_report.json" 2>&1
```

---

# Final Output

Print this summary (fill in actual values):

```
=== Pipeline Complete: <RUN_TS> ===

Findings analyzed: N
  [PASS] finding-1: PR https://github.com/...
  [PASS] finding-2: PR https://github.com/...
  [FAIL] finding-3: Stage 7 build failure (3 attempts exhausted)

Benchmark: PASS/FAIL
Deployment: PASS/FAIL
PRs created: P

Run directory: <RUN>
```

# Cleanup

Return both repos to their base branches when done:
```bash
git -C "<BUILDER>" checkout "<BASE_BRANCH>" 2>/dev/null || true
git -C "<REPO>" checkout main 2>/dev/null || true
```

The working branches (`pipeline/run-<RUN_TS>`) are left intact for review. To discard a failed run:
```
git -C "<BUILDER>" branch -D "pipeline/run-<RUN_TS>"
git -C "<REPO>" branch -D "pipeline/run-<RUN_TS>"
```
