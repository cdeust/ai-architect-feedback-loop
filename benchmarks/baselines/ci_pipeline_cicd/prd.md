# PRD: Pipeline Feedback — Epic 5: Operational Maturity

**Document Type:** Implementation-Level PRD (Focused Epic)
**Version:** 1.0
**Date:** 2026-02-11
**Status:** Draft
**Parent PRD:** PRD-PipelineFeedback.md (Full Scope Overview)
**Epic:** 5 of 5 — Operational Maturity
**Stages Covered:** Pipeline orchestration, scheduling, monitoring, hardening
**Estimated Effort:** 34 SP (Fibonacci)
**License Tier:** Licensed (Full verification engine + all 15 strategies)

---

## 1. Overview

### 1.1 Epic Scope

Pipeline runs nightly, self-heals on failure, reports results in the morning. This is the "set it and forget it" phase.

| Component | What It Delivers |
|-----------|-----------------|
| Pipeline Orchestrator | Main `pipeline.sh` sequencing all 10 stages with error handling |
| Health Checks | Pre-flight validation of all dependencies |
| Scheduler | launchd plist for nightly pipeline execution |
| macOS Notifications | Morning summary with pipeline results |
| Baseline Update Script | Post-merge baseline refresh |
| Structured Logging | JSON logging across all stages |
| .gitignore Updates | Prevent pipeline artifacts from being committed |

### 1.2 Dependencies

This epic depends on **all 4 previous epics** being operational:
- Epic 1: Stages 1, 6, 8, 9
- Epic 2: Stages 2, 3
- Epic 3: Stages 4, 5
- Epic 4: Stages 7, 10, retry logic

---

## 2. Goals & Success Metrics

| ID | Goal | Baseline | Target | Measurement |
|----|------|----------|--------|-------------|
| EG-501 | Pipeline runs unattended nightly | No automation | 7/7 nights scheduled | launchd job run count |
| EG-502 | Health check catches missing dependencies | No pre-flight validation | 100% of missing deps detected | Test with removed deps |
| EG-503 | Morning notification delivered | No notification | macOS notification after every run | osascript execution |
| EG-504 | Run history preserved | No history | Timestamped dirs under runs/ | Directory count |
| EG-505 | Logs are structured and searchable | No structured logging | All stages log JSON to pipeline.log | jq parse test |

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Priority | Requirement | Story |
|----|----------|-------------|-------|
| FR-E5-001 | P0 | `pipeline.sh` sequences all 10 stages in order with error handling | PIPE-E5-001 |
| FR-E5-002 | P0 | Pipeline exits cleanly on "no findings" (Stage 1 returns 0 findings) | PIPE-E5-001 |
| FR-E5-003 | P0 | Pipeline handles stage failure: logs error, skips to failure handling | PIPE-E5-001 |
| FR-E5-004 | P0 | Pipeline passes run directory path to all stages | PIPE-E5-001 |
| FR-E5-005 | P0 | Health check validates: `claude` CLI, `gh` CLI, `swift`, `swiftc`, `make`, `python3` | PIPE-E5-002 |
| FR-E5-006 | P0 | Health check validates: git repo clean (no uncommitted changes) | PIPE-E5-002 |
| FR-E5-007 | P0 | Health check validates: on correct branch (main) | PIPE-E5-002 |
| FR-E5-008 | P0 | Health check reports all failures before exiting (not fail-fast) | PIPE-E5-002 |
| FR-E5-009 | P1 | launchd plist schedules pipeline after Technical Veil completes (or fixed time, e.g., 2 AM) | PIPE-E5-003 |
| FR-E5-010 | P1 | launchd uses `caffeinate` to prevent sleep during pipeline run | PIPE-E5-003 |
| FR-E5-011 | P1 | macOS notification displays: findings processed, PRs created, failures | PIPE-E5-004 |
| FR-E5-012 | P1 | Notification triggered after pipeline completes or on morning schedule | PIPE-E5-004 |
| FR-E5-013 | P1 | `.gitignore` includes `runs/`, `logs/`, and build artifacts | PIPE-E5-007 |
| FR-E5-014 | P2 | All stages produce structured JSON log entries | PIPE-E5-005 |
| FR-E5-015 | P2 | Log entries include: timestamp, stage name, level, message, duration | PIPE-E5-005 |

### 3.2 Non-Functional Requirements

| ID | Priority | Requirement | Target |
|----|----------|-------------|--------|
| NFR-E5-001 | P0 | Full pipeline orchestration time (10 stages, single finding) | < 90 minutes |
| NFR-E5-002 | P0 | Health check execution time | < 10 seconds |
| NFR-E5-003 | P1 | Log files parseable by `jq` | Valid JSON per line |
| NFR-E5-004 | P1 | Run history disk usage manageable | < 100 MB per run |

---

## 4. User Stories & Acceptance Criteria

### PIPE-E5-001: Pipeline Orchestrator [13 SP]

**As a** pipeline operator,
**I want** a main orchestrator that sequences all 10 stages,
**So that** the entire pipeline runs end-to-end with proper error handling.

**AC-E5-001:** Full Sequencing
- [ ] GIVEN all stages available WHEN `pipeline.sh` runs THEN executes Stages 1→2→3→4→5→6→7→8→9→10 in order

| Metric | Value |
|--------|-------|
| Baseline | No orchestration |
| Target | All 10 stages sequenced |
| Measurement | Stage execution log |
| Business Impact | EG-501: nightly execution |

**AC-E5-002:** No-Findings Clean Exit
- [ ] GIVEN Stage 1 returns 0 findings WHEN pipeline runs THEN exits cleanly with "No actionable findings" message

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Clean exit, no error |
| Measurement | Exit code 0 + message |
| Business Impact | TG-001: completion rate |

**AC-E5-003:** Stage Failure Handling
- [ ] GIVEN Stage 2 fails WHEN pipeline detects failure THEN logs error, runs failure handler, exits

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Graceful failure |
| Measurement | Error log + handler execution |
| Business Impact | TG-001: completion rate |

**AC-E5-004:** Batch Processing
- [ ] GIVEN 3 findings from Stage 1 WHEN pipeline processes them THEN each finding goes through Stages 2-10 sequentially

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All findings processed |
| Measurement | Run directory contains 3 finding subdirectories |
| Business Impact | FR-019: batch processing |

**AC-E5-005:** Run Directory Management
- [ ] GIVEN pipeline start WHEN run begins THEN creates `runs/<YYYYMMDD_HHMMSS>/` and passes path to all stages

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Consistent run directory |
| Measurement | All stage outputs in same run dir |
| Business Impact | EG-504: run history |

**Tasks:**
- [ ] Implement `pipeline.sh` as main entry point
- [ ] Sequence all stages with error checking between each
- [ ] Handle Stage 1 no-findings exit
- [ ] Implement batch processing loop (findings → sequential processing)
- [ ] Create run directory and pass to all stages
- [ ] Add `caffeinate -i` wrapper for preventing sleep
- [ ] Add structured logging (start, end, duration per stage)
- [ ] Add summary output at end (findings processed, PRs created, failures)

---

### PIPE-E5-002: Health Check Script [5 SP]

**As a** pipeline operator,
**I want** pre-flight validation of all dependencies,
**So that** the pipeline fails fast with a clear message instead of mid-stage.

**AC-E5-006:** Dependency Detection
- [ ] GIVEN `claude` CLI not installed WHEN health check runs THEN reports "claude CLI not found" and fails

| Metric | Value |
|--------|-------|
| Baseline | No pre-flight |
| Target | All missing deps detected |
| Measurement | Test with removed deps |
| Business Impact | EG-502: dependency detection |

**AC-E5-007:** Git State Validation
- [ ] GIVEN uncommitted changes in repo WHEN health check runs THEN reports "uncommitted changes detected" and fails

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Dirty repo detected |
| Measurement | Test with staged changes |
| Business Impact | FR-E5-006: clean git state |

**AC-E5-008:** Complete Report
- [ ] GIVEN 2 missing dependencies WHEN health check runs THEN reports BOTH (not fail-fast on first)

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All issues in one report |
| Measurement | Report contains all failures |
| Business Impact | FR-E5-008: complete reporting |

**Tasks:**
- [ ] Implement `health_check.sh`
- [ ] Check: `claude --version`, `gh --version`, `swift --version`, `swiftc --version`, `make --version`, `python3 --version`
- [ ] Check: `git status --porcelain` is empty
- [ ] Check: current branch is `main`
- [ ] Accumulate all failures, report at end
- [ ] Exit code 0 if all pass, 1 if any fail

---

### PIPE-E5-003: launchd Scheduler [3 SP]

**As a** pipeline operator,
**I want** nightly pipeline execution via macOS scheduler,
**So that** the pipeline runs automatically without manual intervention.

**AC-E5-009:** Scheduled Execution
- [ ] GIVEN plist installed WHEN 2 AM arrives THEN `pipeline.sh` triggered

| Metric | Value |
|--------|-------|
| Baseline | No scheduling |
| Target | Nightly at 2 AM |
| Measurement | launchd job log |
| Business Impact | EG-501: nightly runs |

**AC-E5-010:** Sleep Prevention
- [ ] GIVEN pipeline running WHEN Mac attempts sleep THEN `caffeinate` prevents sleep

| Metric | Value |
|--------|-------|
| Baseline | Mac may sleep during long runs |
| Target | Awake during pipeline |
| Measurement | caffeinate process check |
| Business Impact | FR-E5-010: sleep prevention |

**Tasks:**
- [ ] Create `com.ai-architect.pipeline-feedback.plist`
- [ ] Configure `StartCalendarInterval` for 2 AM daily
- [ ] Set `StandardOutPath` and `StandardErrorPath` to log files
- [ ] Include `caffeinate -i` in pipeline invocation
- [ ] Add install/uninstall commands to Makefile

---

### PIPE-E5-004: macOS Notification Script [3 SP]

**As a** developer waking up in the morning,
**I want** a notification summarizing overnight pipeline results,
**So that** I know what happened without opening the terminal.

**AC-E5-011:** Notification Content
- [ ] GIVEN pipeline completed with 2 findings processed, 1 PR, 1 failure WHEN notification triggers THEN displays "Pipeline: 2 findings, 1 PR, 1 failure"

| Metric | Value |
|--------|-------|
| Baseline | No notification |
| Target | Informative summary |
| Measurement | Notification content |
| Business Impact | EG-503: morning notification |

**AC-E5-012:** Notification Delivery
- [ ] GIVEN macOS notification center available WHEN `notify.sh` runs THEN notification appears

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | Notification displayed |
| Measurement | osascript exit code |
| Business Impact | FR-E5-012: notification trigger |

**Tasks:**
- [ ] Implement `notify.sh` using `osascript -e 'display notification ...'`
- [ ] Parse pipeline summary from run directory
- [ ] Compose notification message (findings, PRs, failures)
- [ ] Integrate into pipeline.sh as final step

---

### PIPE-E5-005: Structured Logging [3 SP]

**As a** pipeline debugger,
**I want** structured JSON logging from all stages,
**So that** I can filter and search pipeline execution history.

**AC-E5-013:** JSON Format
- [ ] GIVEN stage execution WHEN log entries written THEN each line is valid JSON parseable by `jq`

| Metric | Value |
|--------|-------|
| Baseline | No structured logging |
| Target | 100% JSON-parseable |
| Measurement | `jq '.' logs/pipeline.log` |
| Business Impact | EG-505: searchable logs |

**AC-E5-014:** Required Fields
- [ ] GIVEN log entry WHEN examined THEN contains: timestamp, stage, level, message

| Metric | Value |
|--------|-------|
| Baseline | N/A |
| Target | All fields present |
| Measurement | jq field extraction |
| Business Impact | FR-E5-015: log completeness |

**Tasks:**
- [ ] Create shared `log()` function for all scripts
- [ ] Format: `{"timestamp":"...", "stage":"...", "level":"...", "message":"..."}`
- [ ] Add optional `duration` field for stage timing
- [ ] Ensure log file is append-only across pipeline run

---

### PIPE-E5-006: Baseline Update Integration [2 SP]

**As a** post-merge process,
**I want** baselines updated after accepted improvements,
**So that** quality gate baselines stay current.

*Note: `update_baselines.sh` was implemented in Epic 1. This story integrates it into the operational workflow.*

**AC-E5-015:** Post-Merge Trigger
- [ ] GIVEN PR merged to main WHEN developer runs `make update-baselines` THEN baselines refreshed from latest quality gate run

| Metric | Value |
|--------|-------|
| Baseline | Manual baseline management |
| Target | Single-command update |
| Measurement | Makefile target execution |
| Business Impact | R-003: prevent stale baselines |

**Tasks:**
- [ ] Document baseline update process in README
- [ ] Add post-merge checklist to PR template
- [ ] Verify `make update-baselines` works end-to-end

---

### PIPE-E5-007: .gitignore & Cleanup [2 SP]

**As a** repository maintainer,
**I want** pipeline artifacts excluded from git,
**So that** runs/ and logs/ directories don't pollute the repository.

**AC-E5-016:** gitignore Entries
- [ ] GIVEN `.gitignore` WHEN checked THEN includes `runs/`, `logs/`, and pipeline temp files

| Metric | Value |
|--------|-------|
| Baseline | No pipeline entries |
| Target | All artifacts excluded |
| Measurement | `git status` shows clean after pipeline run |
| Business Impact | NFR-007: no artifacts committed |

**Tasks:**
- [ ] Add entries to `.gitignore`: `runs/`, `logs/`, `*.pyc`, `__pycache__/`
- [ ] Verify with test pipeline run

---

## 5. Technical Specification

### 5.1 Pipeline Orchestrator Flow

```bash
#!/usr/bin/env bash
set -euo pipefail

# Health check
scripts/pipeline/health_check.sh || exit 1

# Create run directory
RUN_DIR="runs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

# Stage 1: Parse findings
scripts/pipeline/stage_1_trigger.sh --run-dir "$RUN_DIR"
FINDINGS_COUNT=$(jq '.findings | length' "$RUN_DIR/findings.json")

if [ "$FINDINGS_COUNT" -eq 0 ]; then
    log "INFO" "No actionable findings. Pipeline complete."
    scripts/pipeline/notify.sh --message "No findings today"
    exit 0
fi

# Process each finding
for finding in $(jq -r '.findings[].id' "$RUN_DIR/findings.json"); do
    FINDING_DIR="$RUN_DIR/$finding"
    mkdir -p "$FINDING_DIR"

    # Stage 2: Impact analysis
    scripts/pipeline/stage_2_impact_analysis.sh --finding "$finding" --run-dir "$FINDING_DIR"

    # Stage 2 validation
    scripts/pipeline/validate_impact_report.sh --run-dir "$FINDING_DIR" || continue

    # Stage 3: Integration design
    scripts/pipeline/stage_3_integration_design.sh --run-dir "$FINDING_DIR"

    # Stage 3 validation
    scripts/pipeline/validate_integration_plan.sh --run-dir "$FINDING_DIR" || continue

    # Generate manifest
    scripts/pipeline/generate_manifest.py --run-dir "$FINDING_DIR"

    # Stage 4: Dogfood PRD
    scripts/pipeline/stage_4_dogfood.sh --run-dir "$FINDING_DIR"

    # Stage 5→6→7 with retry
    scripts/pipeline/retry_orchestrator.sh --run-dir "$FINDING_DIR"

    # Stage 8: Quality gate
    scripts/pipeline/stage_8_quality_gate.sh --run-dir "$FINDING_DIR"

    # Stage 9: Deployment simulation
    scripts/pipeline/stage_9_deployment.sh --run-dir "$FINDING_DIR"

    # Stage 10: PR creation
    scripts/pipeline/stage_10_pull_request.sh --run-dir "$FINDING_DIR"
done

# Notification
scripts/pipeline/notify.sh --run-dir "$RUN_DIR"
```

### 5.2 launchd Plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ai-architect.pipeline-feedback</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-i</string>
        <string>/path/to/ai-architect-prd-builder/pipeline.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/path/to/ai-architect-prd-builder/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/path/to/ai-architect-prd-builder/logs/launchd-stderr.log</string>
    <key>WorkingDirectory</key>
    <string>/path/to/ai-architect-prd-builder</string>
</dict>
</plist>
```

### 5.3 Notification Script

```bash
#!/usr/bin/env bash
# notify.sh — macOS notification with pipeline summary

TITLE="AI-Architect Pipeline"
MESSAGE="$1"

osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"Glass\""
```

---

## 6. Implementation Roadmap

### Sprint 1 (Week 1-2): Core Orchestration [21 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E5-001: Pipeline Orchestrator | 13 | All stages (Epics 1-4) |
| PIPE-E5-002: Health Check | 5 | None |
| PIPE-E5-005: Structured Logging | 3 | None |

### Sprint 2 (Week 3-4): Operations [13 SP]

| Story | SP | Dependencies |
|-------|----|-------------|
| PIPE-E5-003: launchd Scheduler | 3 | Orchestrator |
| PIPE-E5-004: Notification Script | 3 | Orchestrator |
| PIPE-E5-006: Baseline Integration | 2 | Epic 1 baselines |
| PIPE-E5-007: .gitignore & Cleanup | 2 | None |
| Integration testing + hardening | 3 | All |

### Summary

| Sprint | SP | Theme |
|--------|----|-------|
| Sprint 1 | 21 | Orchestrator + health + logging |
| Sprint 2 | 13 | Scheduling + notifications + polish |
| **Total** | **34** | **4 weeks** |

---

## 7. Open Questions

| ID | Question | Impact | Decision By |
|----|----------|--------|-------------|
| OQ-E5-001 | Should pipeline run trigger be time-based (2 AM) or event-based (TV output file watch)? | Scheduling design | Sprint 2 |
| OQ-E5-002 | How long should run history be retained before cleanup? | Disk usage | Sprint 2 |
| OQ-E5-003 | Should notification include deep link to latest PR? | UX | Sprint 2 |

---

*PRD generated by AI PRD Generator v7.0 | Licensed Edition*
*Context: Feature PRD (Focused Epic — Operational Maturity)*
*Fibonacci story points: 34 SP across 7 stories, 2 sprints*
