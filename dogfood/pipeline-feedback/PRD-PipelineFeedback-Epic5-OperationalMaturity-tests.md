# Test Cases: Pipeline Feedback — Epic 5: Operational Maturity

**Generated:** 2026-02-11
**Total Tests:** 30 tests
**Coverage:** 15 FRs + 4 NFRs → 16 ACs

---

## PART A: Coverage Tests

### A.1 Unit Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| UT-E5-001 | log() function | Outputs valid JSON per line | AC-E5-013 |
| UT-E5-002 | log() function | Includes timestamp, stage, level, message fields | AC-E5-014 |
| UT-E5-003 | log() function | Optional duration field present when provided | AC-E5-014 |
| UT-E5-004 | notify.sh | Constructs correct osascript command from summary | AC-E5-011 |
| UT-E5-005 | notify.sh | Handles zero findings gracefully | AC-E5-011 |
| UT-E5-006 | notify.sh | Handles mixed results (PRs + failures) | AC-E5-011 |
| UT-E5-007 | pipeline.sh | Creates timestamped run directory in correct format | AC-E5-005 |
| UT-E5-008 | pipeline.sh | Parses findings count from Stage 1 output | AC-E5-002 |
| UT-E5-009 | health_check.sh | Detects missing `claude` CLI | AC-E5-006 |
| UT-E5-010 | health_check.sh | Detects missing `gh` CLI | AC-E5-006 |
| UT-E5-011 | health_check.sh | Detects dirty git state | AC-E5-007 |
| UT-E5-012 | health_check.sh | Reports multiple failures (not fail-fast) | AC-E5-008 |

### A.2 Integration Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| IT-E5-001 | pipeline.sh + stage_1 | Zero findings → clean exit with message | AC-E5-002 |
| IT-E5-002 | pipeline.sh + stage_2 | Stage failure → error log + failure handler | AC-E5-003 |
| IT-E5-003 | pipeline.sh | 3 mock findings → 3 finding subdirectories created | AC-E5-004 |
| IT-E5-004 | pipeline.sh | Run directory path passed to all stages | AC-E5-005 |
| IT-E5-005 | health_check.sh + pipeline.sh | Health check failure blocks pipeline start | AC-E5-006 |
| IT-E5-006 | health_check.sh | Correct branch check (main vs feature branch) | AC-E5-007 |
| IT-E5-007 | log() + pipeline.sh | Log file contains valid JSON lines after full run | AC-E5-013 |
| IT-E5-008 | log() + pipeline.sh | Log entries have all required fields | AC-E5-014 |
| IT-E5-009 | .gitignore | Pipeline run artifacts not tracked by git | AC-E5-016 |
| IT-E5-010 | launchd plist | Plist valid XML and loads without error | AC-E5-009 |
| IT-E5-011 | notify.sh + osascript | Notification displays on macOS | AC-E5-012 |
| IT-E5-012 | update_baselines.sh | Makefile target refreshes baselines | AC-E5-015 |

### A.3 End-to-End Tests

| Test ID | Component | What It Validates | AC Ref |
|---------|-----------|-------------------|--------|
| E2E-E5-001 | Full pipeline (mock stages) | 10 stages execute in order with mock scripts | All Stage ACs |
| E2E-E5-002 | Zero-findings flow | Stage 1 returns empty → clean exit → notification | AC-E5-002, AC-E5-011 |
| E2E-E5-003 | Multi-finding flow | 3 findings → 3 sequential pipelines → summary | AC-E5-004, AC-E5-011 |
| E2E-E5-004 | Failure recovery flow | Stage fails → error logged → failure handler → notification | AC-E5-003, AC-E5-011 |
| E2E-E5-005 | Health → Pipeline → Notify | Full lifecycle: health check pass → run → notify | AC-E5-006, AC-E5-001, AC-E5-012 |
| E2E-E5-006 | Logging completeness | Full run → all log entries valid JSON with required fields | AC-E5-013, AC-E5-014 |

---

## PART B: AC Validation Tests

### AC-E5-001: Full Sequencing
**Criteria:** GIVEN all stages available WHEN `pipeline.sh` runs THEN executes Stages 1→10 in order
**Tests:** E2E-E5-001
**Assertions:**
- Stage execution log shows 10 entries in order
- Each stage receives correct `--run-dir` argument
- Exit code 0 on full success

### AC-E5-002: No-Findings Clean Exit
**Criteria:** GIVEN Stage 1 returns 0 findings WHEN pipeline runs THEN exits cleanly
**Tests:** UT-E5-008, IT-E5-001, E2E-E5-002
**Assertions:**
- Exit code is 0
- Stdout contains "No actionable findings"
- No Stage 2+ scripts invoked

### AC-E5-003: Stage Failure Handling
**Criteria:** GIVEN Stage 2 fails WHEN pipeline detects failure THEN logs error, runs handler, exits
**Tests:** IT-E5-002, E2E-E5-004
**Assertions:**
- Error logged with level "ERROR"
- Failure handler script invoked
- Pipeline exits with non-zero code

### AC-E5-004: Batch Processing
**Criteria:** GIVEN 3 findings WHEN pipeline processes THEN each goes through Stages 2-10
**Tests:** IT-E5-003, E2E-E5-003
**Assertions:**
- Run directory contains 3 finding subdirectories
- Each subdirectory has stage outputs
- Summary shows 3 findings processed

### AC-E5-005: Run Directory Management
**Criteria:** GIVEN pipeline start WHEN run begins THEN creates timestamped dir
**Tests:** UT-E5-007, IT-E5-004
**Assertions:**
- Directory matches `runs/YYYYMMDD_HHMMSS/` pattern
- All stage outputs land in this directory
- Path accessible from all stages

### AC-E5-006: Dependency Detection
**Criteria:** GIVEN `claude` CLI missing WHEN health check runs THEN reports and fails
**Tests:** UT-E5-009, UT-E5-010, IT-E5-005
**Assertions:**
- Stderr contains "claude CLI not found"
- Exit code is 1
- Pipeline does not start

### AC-E5-007: Git State Validation
**Criteria:** GIVEN uncommitted changes WHEN health check runs THEN reports and fails
**Tests:** UT-E5-011, IT-E5-006
**Assertions:**
- Stderr contains "uncommitted changes detected"
- Exit code is 1
- Also validates branch name is `main`

### AC-E5-008: Complete Report
**Criteria:** GIVEN 2 missing deps WHEN health check runs THEN reports BOTH
**Tests:** UT-E5-012
**Assertions:**
- Output contains both missing dependency names
- Not fail-fast (second check runs after first fails)
- Final count shows "2 issues found"

### AC-E5-009: Scheduled Execution
**Criteria:** GIVEN plist installed WHEN 2 AM arrives THEN pipeline triggered
**Tests:** IT-E5-010
**Assertions:**
- Plist is valid XML
- `launchctl load` succeeds
- `StartCalendarInterval` has Hour=2, Minute=0

### AC-E5-010: Sleep Prevention
**Criteria:** GIVEN pipeline running WHEN Mac sleeps THEN caffeinate prevents
**Tests:** (Manual verification required)
**Assertions:**
- ProgramArguments starts with `/usr/bin/caffeinate -i`
- caffeinate process present during pipeline run

### AC-E5-011: Notification Content
**Criteria:** GIVEN results WHEN notification triggers THEN displays summary
**Tests:** UT-E5-004, UT-E5-005, UT-E5-006, E2E-E5-002, E2E-E5-003, E2E-E5-004
**Assertions:**
- Message includes findings count
- Message includes PR count
- Message includes failure count

### AC-E5-012: Notification Delivery
**Criteria:** GIVEN macOS available WHEN notify.sh runs THEN notification appears
**Tests:** IT-E5-011, E2E-E5-005
**Assertions:**
- `osascript` exit code is 0
- Notification title is "AI-Architect Pipeline"

### AC-E5-013: JSON Format
**Criteria:** GIVEN stage execution WHEN log entries written THEN valid JSON per line
**Tests:** UT-E5-001, IT-E5-007, E2E-E5-006
**Assertions:**
- `jq '.' logs/pipeline.log` parses without error
- Each line is independent JSON object
- No interleaved non-JSON output

### AC-E5-014: Required Fields
**Criteria:** GIVEN log entry WHEN examined THEN contains timestamp, stage, level, message
**Tests:** UT-E5-002, UT-E5-003, IT-E5-008, E2E-E5-006
**Assertions:**
- `jq '.timestamp'` returns ISO 8601 format
- `jq '.stage'` returns stage name
- `jq '.level'` returns INFO/WARN/ERROR
- `jq '.message'` returns non-empty string

### AC-E5-015: Post-Merge Trigger
**Criteria:** GIVEN PR merged WHEN `make update-baselines` runs THEN baselines refreshed
**Tests:** IT-E5-012
**Assertions:**
- Makefile target exists and runs
- Baseline files updated with latest values
- Process documented in README

### AC-E5-016: gitignore Entries
**Criteria:** GIVEN `.gitignore` WHEN checked THEN includes pipeline artifacts
**Tests:** IT-E5-009
**Assertions:**
- `.gitignore` contains `runs/`
- `.gitignore` contains `logs/`
- `git status` clean after pipeline run

---

## PART C: AC-to-Test Traceability Matrix

| AC ID | AC Title | Test IDs | Test Type | Status |
|-------|----------|----------|-----------|--------|
| AC-E5-001 | Full Sequencing | E2E-E5-001, E2E-E5-005 | E2E | Pending |
| AC-E5-002 | No-Findings Exit | UT-E5-008, IT-E5-001, E2E-E5-002 | All | Pending |
| AC-E5-003 | Failure Handling | IT-E5-002, E2E-E5-004 | Integration + E2E | Pending |
| AC-E5-004 | Batch Processing | IT-E5-003, E2E-E5-003 | Integration + E2E | Pending |
| AC-E5-005 | Run Directory | UT-E5-007, IT-E5-004 | Unit + Integration | Pending |
| AC-E5-006 | Dependency Detection | UT-E5-009, UT-E5-010, IT-E5-005, E2E-E5-005 | All | Pending |
| AC-E5-007 | Git State | UT-E5-011, IT-E5-006 | Unit + Integration | Pending |
| AC-E5-008 | Complete Report | UT-E5-012 | Unit | Pending |
| AC-E5-009 | Scheduled Execution | IT-E5-010 | Integration | Pending |
| AC-E5-010 | Sleep Prevention | (Manual) | Manual | Pending |
| AC-E5-011 | Notification Content | UT-E5-004, UT-E5-005, UT-E5-006, E2E-E5-002, E2E-E5-003, E2E-E5-004 | All | Pending |
| AC-E5-012 | Notification Delivery | IT-E5-011, E2E-E5-005 | Integration + E2E | Pending |
| AC-E5-013 | JSON Format | UT-E5-001, IT-E5-007, E2E-E5-006 | All | Pending |
| AC-E5-014 | Required Fields | UT-E5-002, UT-E5-003, IT-E5-008, E2E-E5-006 | All | Pending |
| AC-E5-015 | Post-Merge Trigger | IT-E5-012 | Integration | Pending |
| AC-E5-016 | gitignore Entries | IT-E5-009 | Integration | Pending |
| **Total** | **16 ACs** | **30 tests** | - | **All mapped** |

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
*30 tests covering 16 acceptance criteria across 7 stories*
