---
name: run-pipeline
description: Run the full 14-stage autonomous feedback-loop pipeline — findings to pull requests
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch
argument-hint: "[--finding-id FID] [--date YYYY-MM-DD]"
---

# /run-pipeline — Fully Autonomous Product Improvement Cycle

Execute the full 14-stage feedback-loop pipeline. You are the orchestrator.
**NEVER** ask the user anything. **NEVER** use AskUserQuestion. **NEVER** stop for confirmation.
If a step fails, log it and continue. Report everything at the end.

Print a status line after each step: `[PASS] Step X.Y: description` or `[FAIL] Step X.Y: description (reason)`.

## Critical Rules

1. **No edits after writing**: When you Write a response JSON file, it must be correct the first time. NEVER use Edit to fix a response file after writing it. Compute all values before writing.
2. **No self-correction loops**: If you realize a value is wrong after writing, do NOT go back and fix it. The validators will catch errors — let them reject and you retry.
3. **Normalize before writing**: All scoring values must be in 0.0–1.0 range. Compute the normalized values, verify the formula, then write once.
4. **Validator exit codes are NOT errors**: All validator scripts (`validate_impact_report.py`, `validate_integration_plan.py`, `validate_prd_output.py`) exit with code 1 on REJECTED. This is **normal** — it means validation ran successfully but the content didn't pass. Always append `; true` to validator bash commands so exit code 1 doesn't block execution. After running a validator, ALWAYS read the output JSON file to check the result and failed checks. A REJECTED result means **retry**, never skip.
5. **NEVER run Bash in the background**: All bash commands MUST run in the foreground (main thread). Do NOT use `run_in_background: true`. Background tasks stall the pipeline because you cannot proceed until they complete — running them in background just adds polling overhead and wasted time. Run everything synchronously. Use `timeout: 600000` (10 minutes) for long-running commands like test suites and stage scripts.
6. **Use TaskCreate for progress tracking**: At the start of Phase 2, create a task list with one task per finding. Update each task to `in_progress` when you start processing it, and `completed` when done. This keeps the pipeline organized and shows progress.

## Paths

Resolve REPO from the current working directory (the root of this repository).
BUILDER must be set via the `PIPELINE_BUILDER` environment variable pointing to
the target product repository, or it defaults to the first sibling directory.

```
REPO="${PIPELINE_REPO:-$(pwd)}"
BUILDER="${PIPELINE_BUILDER:?Set PIPELINE_BUILDER to the target product repo path}"
CONFIG="$REPO/config"
SCRIPTS="$REPO/scripts"
```

## Step 0: Setup

Run this single Bash command to create the run directory, read project config, and capture key variables:

```bash
REPO="${PIPELINE_REPO:-$(pwd)}" && RUN_TS=$(date +%Y%m%d-%H%M%S) && RUN="$REPO/runs/$RUN_TS" && mkdir -p "$RUN" && echo "$RUN_TS"
```

Save the output as `RUN_TS`. Build `RUN` = `$REPO/runs/$RUN_TS`.
All subsequent Bash calls must inline the full `RUN` path (do not rely on shell variables persisting across Bash calls).

**Read project config** — Read `<CONFIG>/project.json` with the Read tool and extract:
- `MODULES_DIR` = value of `modules_dir` (default: `"packages"`)
- `BASE_BRANCH` = value of `base_branch` (default: `"main"`)
- `BUILD_CMD` = value of `build_command`
- `TEST_CMD` = value of `test_command`

Derive `PACKAGES_DIR`:
- If `MODULES_DIR` is `"."` → `PACKAGES_DIR` = `<BUILDER>`
- Otherwise → `PACKAGES_DIR` = `<BUILDER>/<MODULES_DIR>`

Use `PACKAGES_DIR` and `BASE_BRANCH` in ALL subsequent steps instead of hardcoded values.

**Read pipeline preferences** — If `<CONFIG>/pipeline_preferences.json` exists, read it and extract:
- `RUN_BRANCH_PATTERN` = `git.run_branch_pattern` (default: `"pipeline/run-{run_ts}"`)
- `FEATURE_BRANCH_PATTERN` = `git.feature_branch_pattern` (default: `"pipeline/improvement-{finding_id}"`)
- `COMMIT_MESSAGE` = `git.commit_message` (default: `"pipeline: {finding_id} — {description}"`)
- `GIT_REMOTE` = `git.remote` (default: `"origin"`)
- `LICENSE_KEY_FILE` = `license.key_file` (default: `"~/.aiprd/license-key"`)
- `VALIDATE_LICENSE` = `license.validate_on_run` (default: `true`)
- `CLAUDE_MAX_TURNS_IMPL` = `pipeline.claude_max_turns.implementation` (default: `30`)
- `CLAUDE_MAX_TURNS_ANALYSIS` = `pipeline.claude_max_turns.analysis` (default: `5`)
- `CLAUDE_TIMEOUT_IMPL` = `pipeline.claude_timeout.implementation` (default: `1800`)
- `TOP_N` = `pipeline.top_n_findings` (default: `20`)
- `EXCLUDE_CATS` = `pipeline.exclude_categories` (default: `["benchmarks"]`)

Use these variables instead of hardcoded values throughout the pipeline steps. If the file doesn't exist, use the defaults listed above.

### Step 0.0: Create working branches (protect base branch)

Create a working branch in **both repos** so the base branch is never modified directly. All pipeline work happens on these branches.

Use `RUN_BRANCH_PATTERN` to derive the run branch name: replace `{run_ts}` with `<RUN_TS>`. Default: `pipeline/run-<RUN_TS>`.

**Feedback-loop repo:**
```bash
git -C "<REPO>" checkout -b "<RUN_BRANCH>"
```

**Builder repo** — ensure we branch from the configured base branch (`BASE_BRANCH`):
```bash
git -C "<BUILDER>" checkout "<BASE_BRANCH>" && git -C "<BUILDER>" checkout -b "<RUN_BRANCH>"
```

This `<RUN_BRANCH>` branch in the builder serves as the **working base** for the run. Per-finding feature branches are created from this base using `FEATURE_BRANCH_PATTERN` (replace `{finding_id}` with `<FID>`) — NOT from `<BASE_BRANCH>` directly.

If either checkout fails: print `[FAIL] Step 0.0: Could not create working branch` and **stop entirely**.
Print: `[PASS] Step 0.0: Working branches created — pipeline/run-<RUN_TS>`

## Step 0.1: License (one-time check)

Determine the license tier. The result applies to the entire run — no further license checks needed (including when invoking the ai-prd-generator skill). Save the result as `LICENSE_TIER`.

Use `LICENSE_KEY_FILE` from pipeline preferences (default: `~/.aiprd/license-key`). If `VALIDATE_LICENSE` is `false`, skip this entire step and print `[SKIP] Step 0.1: License validation disabled`. Set `LICENSE_TIER=pro` (assume valid).

```bash
python3 "<SCRIPTS>/license.py" --check --key-file "<LICENSE_KEY_FILE>" 2>&1
```

The script returns the tier (`pro` or `free`) on stdout, exits 0. Only exits 1 if the key is provably invalid (exists but rejected by the API).

- If exit 0 and output is `pro`: set `LICENSE_TIER=pro`. Print `[PASS] Step 0.1: License validated — pro tier`
- If exit 0 and output is `free`: set `LICENSE_TIER=free`. Print `[INFO] Step 0.1: No license — using free tier`
- If exit 1: print `[FAIL] Step 0.1: License invalid` and **stop entirely**.

**License tier is now set for this run. Do NOT re-validate at any later step.** When the ai-prd-generator skill runs its own license gate, skip it — the license is already confirmed.

Stage 5 behavior adapts based on `LICENSE_TIER`:
- `pro`: Full skill invocation with all 11 sections
- `free`: Simplified PRD generation (5 core sections: Overview, Requirements, Design, Testing, Constraints; no JIRA export, no verification scoring)

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

Determine the findings input source. Check in order:
1. If `$HOME/Downloads/TechnicalVeil` directory exists → use `--tv-dir "$HOME/Downloads/TechnicalVeil"`
2. Else if `<REPO>/runs/findings_input.json` exists → use `--tv-input "<REPO>/runs/findings_input.json"`
3. Else if `<BUILDER>/tv_output.json` exists → use `--tv-input "<BUILDER>/tv_output.json"`
4. Else → `[FAIL] Step 1.1: No findings input found`

```bash
PIPELINE_AUTO_MODE=1 OUTPUT_DIR="<RUN>" "<SCRIPTS>/stage1-parse-findings.sh" --builder-dir "<BUILDER>" --config "<CONFIG>/thresholds.json" <FINDINGS_FLAG> --output "<RUN>" 2>&1
```

Replace `<RUN>`, `<SCRIPTS>`, `<BUILDER>`, `<CONFIG>`, `<FINDINGS_FLAG>` with the full absolute paths. Same for all subsequent commands.

### Step 1.2: Prioritize

```bash
python3 "<SCRIPTS>/prioritize_findings.py" --findings "<RUN>/findings.json" --category-map "<CONFIG>/category_engine_map.json" --engine-graph "<CONFIG>/engine_graph.json" --output "<RUN>/prioritized_findings.json" --top-n <TOP_N> --exclude-categories <EXCLUDE_CATS> 2>&1
```

Use `TOP_N` and `EXCLUDE_CATS` from pipeline preferences (defaults: 20, benchmarks).

### Step 1.3: Read findings

Read `<RUN>/prioritized_findings.json` with the Read tool. Extract the finding IDs from the `findings` array. If 0 findings: print `[DONE] No findings — product is healthy` and stop. Otherwise list them and continue.

---

## SUPPORTING CONTEXT — READ BEFORE CONTINUING

Before proceeding to Phase 2, read the following files for complete pipeline instructions:

1. Read `${CLAUDE_SKILL_DIR}/phase-implementation.md` — Phase 2: Per-Finding Analysis (Steps 2.1–2.4)
2. Read `${CLAUDE_SKILL_DIR}/phase-delivery.md` — Phase 3: Implementation + Verification, Phase 4: Delivery, Final Output, Cleanup
