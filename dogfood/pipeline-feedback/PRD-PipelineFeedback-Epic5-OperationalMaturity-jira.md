# JIRA Tickets: Pipeline Feedback — Epic 5: Operational Maturity

**Generated:** 2026-02-11
**Total Story Points:** 34 SP
**Estimated Duration:** 4 weeks (1 developer, 2 sprints)

---

## Epic: Operational Maturity [34 SP]

**Description:** Pipeline orchestration, nightly scheduling, health checks, macOS notifications, structured logging, and operational hardening. Makes the feedback loop fully autonomous.

**Dependencies:** Epics 1-4 must be operational before integration testing.

---

### PIPE-E5-001: Build Pipeline Orchestrator [13 SP]
**Type:** Story | **Priority:** P0 | **Sprint:** 1
**ACs:** AC-E5-001 (full sequencing), AC-E5-002 (no-findings exit), AC-E5-003 (failure handling), AC-E5-004 (batch processing), AC-E5-005 (run directory)
**Labels:** pipeline, orchestrator, p0

**Description:**
As a pipeline operator,
I want a main orchestrator that sequences all 10 stages,
So that the entire pipeline runs end-to-end with proper error handling.

**Acceptance Criteria:**

**AC-E5-001:** Full Sequencing
- [ ] GIVEN all stages available WHEN `pipeline.sh` runs THEN executes Stages 1→2→3→4→5→6→7→8→9→10 in order
| Baseline | No orchestration | Target | All 10 stages sequenced | Measurement | Stage execution log | Impact | EG-501 |

**AC-E5-002:** No-Findings Clean Exit
- [ ] GIVEN Stage 1 returns 0 findings WHEN pipeline runs THEN exits cleanly with "No actionable findings" message
| Baseline | N/A | Target | Clean exit, no error | Measurement | Exit code 0 + message | Impact | TG-001 |

**AC-E5-003:** Stage Failure Handling
- [ ] GIVEN Stage 2 fails WHEN pipeline detects failure THEN logs error, runs failure handler, exits
| Baseline | N/A | Target | Graceful failure | Measurement | Error log + handler execution | Impact | TG-001 |

**AC-E5-004:** Batch Processing
- [ ] GIVEN 3 findings from Stage 1 WHEN pipeline processes them THEN each finding goes through Stages 2-10 sequentially
| Baseline | N/A | Target | All findings processed | Measurement | Run dir contains 3 finding subdirectories | Impact | FR-019 |

**AC-E5-005:** Run Directory Management
- [ ] GIVEN pipeline start WHEN run begins THEN creates `runs/<YYYYMMDD_HHMMSS>/` and passes path to all stages
| Baseline | N/A | Target | Consistent run directory | Measurement | All stage outputs in same run dir | Impact | EG-504 |

**Tasks:**
- [ ] Task 1: Implement `pipeline.sh` as main entry point with `set -euo pipefail`
- [ ] Task 2: Sequence all stages with error checking between each
- [ ] Task 3: Handle Stage 1 no-findings exit path
- [ ] Task 4: Implement batch processing loop (findings → sequential processing)
- [ ] Task 5: Create timestamped run directory and pass to all stages
- [ ] Task 6: Add `caffeinate -i` wrapper for preventing sleep
- [ ] Task 7: Add structured logging (start, end, duration per stage)
- [ ] Task 8: Add summary output at end (findings processed, PRs created, failures)

**Dependencies:** All stage scripts from Epics 1-4
**Labels:** pipeline, orchestrator, bash, p0

---

### PIPE-E5-002: Build Health Check Script [5 SP]
**Type:** Story | **Priority:** P0 | **Sprint:** 1
**ACs:** AC-E5-006 (dependency detection), AC-E5-007 (git state), AC-E5-008 (complete report)
**Labels:** pipeline, health-check, p0

**Description:**
As a pipeline operator,
I want pre-flight validation of all dependencies,
So that the pipeline fails fast with a clear message instead of mid-stage.

**Acceptance Criteria:**

**AC-E5-006:** Dependency Detection
- [ ] GIVEN `claude` CLI not installed WHEN health check runs THEN reports "claude CLI not found" and fails
| Baseline | No pre-flight | Target | All missing deps detected | Measurement | Test with removed deps | Impact | EG-502 |

**AC-E5-007:** Git State Validation
- [ ] GIVEN uncommitted changes in repo WHEN health check runs THEN reports "uncommitted changes detected" and fails
| Baseline | N/A | Target | Dirty repo detected | Measurement | Test with staged changes | Impact | FR-E5-006 |

**AC-E5-008:** Complete Report
- [ ] GIVEN 2 missing dependencies WHEN health check runs THEN reports BOTH (not fail-fast on first)
| Baseline | N/A | Target | All issues in one report | Measurement | Report contains all failures | Impact | FR-E5-008 |

**Tasks:**
- [ ] Task 1: Implement `health_check.sh` with accumulating error reporting
- [ ] Task 2: Check CLIs: `claude`, `gh`, `swift`, `swiftc`, `make`, `python3`
- [ ] Task 3: Check git state: `git status --porcelain` is empty
- [ ] Task 4: Check current branch is `main`
- [ ] Task 5: Accumulate all failures, report at end
- [ ] Task 6: Exit code 0 if all pass, 1 if any fail

**Dependencies:** None (can start immediately)
**Labels:** pipeline, health-check, bash, p0

---

### PIPE-E5-003: Create launchd Scheduler [3 SP]
**Type:** Story | **Priority:** P1 | **Sprint:** 2
**ACs:** AC-E5-009 (scheduled execution), AC-E5-010 (sleep prevention)
**Labels:** pipeline, scheduler, launchd, p1

**Description:**
As a pipeline operator,
I want nightly pipeline execution via macOS scheduler,
So that the pipeline runs automatically without manual intervention.

**Acceptance Criteria:**

**AC-E5-009:** Scheduled Execution
- [ ] GIVEN plist installed WHEN 2 AM arrives THEN `pipeline.sh` triggered
| Baseline | No scheduling | Target | Nightly at 2 AM | Measurement | launchd job log | Impact | EG-501 |

**AC-E5-010:** Sleep Prevention
- [ ] GIVEN pipeline running WHEN Mac attempts sleep THEN `caffeinate` prevents sleep
| Baseline | Mac may sleep during long runs | Target | Awake during pipeline | Measurement | caffeinate process check | Impact | FR-E5-010 |

**Tasks:**
- [ ] Task 1: Create `com.ai-architect.pipeline-feedback.plist`
- [ ] Task 2: Configure `StartCalendarInterval` for 2 AM daily
- [ ] Task 3: Set `StandardOutPath` and `StandardErrorPath` to log files
- [ ] Task 4: Include `caffeinate -i` in pipeline invocation
- [ ] Task 5: Add `make install-scheduler` / `make uninstall-scheduler` targets

**Dependencies:** PIPE-E5-001 (Pipeline Orchestrator)
**Labels:** pipeline, scheduler, launchd, macos, p1

---

### PIPE-E5-004: Build macOS Notification Script [3 SP]
**Type:** Story | **Priority:** P1 | **Sprint:** 2
**ACs:** AC-E5-011 (notification content), AC-E5-012 (notification delivery)
**Labels:** pipeline, notification, macos, p1

**Description:**
As a developer waking up in the morning,
I want a notification summarizing overnight pipeline results,
So that I know what happened without opening the terminal.

**Acceptance Criteria:**

**AC-E5-011:** Notification Content
- [ ] GIVEN pipeline completed with 2 findings processed, 1 PR, 1 failure WHEN notification triggers THEN displays "Pipeline: 2 findings, 1 PR, 1 failure"
| Baseline | No notification | Target | Informative summary | Measurement | Notification content | Impact | EG-503 |

**AC-E5-012:** Notification Delivery
- [ ] GIVEN macOS notification center available WHEN `notify.sh` runs THEN notification appears
| Baseline | N/A | Target | Notification displayed | Measurement | osascript exit code | Impact | FR-E5-012 |

**Tasks:**
- [ ] Task 1: Implement `notify.sh` using `osascript -e 'display notification ...'`
- [ ] Task 2: Parse pipeline summary from run directory
- [ ] Task 3: Compose notification message (findings, PRs, failures)
- [ ] Task 4: Integrate into `pipeline.sh` as final step

**Dependencies:** PIPE-E5-001 (Pipeline Orchestrator)
**Labels:** pipeline, notification, macos, osascript, p1

---

### PIPE-E5-005: Implement Structured Logging [3 SP]
**Type:** Story | **Priority:** P1 | **Sprint:** 1
**ACs:** AC-E5-013 (JSON format), AC-E5-014 (required fields)
**Labels:** pipeline, logging, p1

**Description:**
As a pipeline debugger,
I want structured JSON logging from all stages,
So that I can filter and search pipeline execution history.

**Acceptance Criteria:**

**AC-E5-013:** JSON Format
- [ ] GIVEN stage execution WHEN log entries written THEN each line is valid JSON parseable by `jq`
| Baseline | No structured logging | Target | 100% JSON-parseable | Measurement | `jq '.' logs/pipeline.log` | Impact | EG-505 |

**AC-E5-014:** Required Fields
- [ ] GIVEN log entry WHEN examined THEN contains: timestamp, stage, level, message
| Baseline | N/A | Target | All fields present | Measurement | jq field extraction | Impact | FR-E5-015 |

**Tasks:**
- [ ] Task 1: Create shared `log()` function for all pipeline scripts
- [ ] Task 2: Format: `{"timestamp":"...", "stage":"...", "level":"...", "message":"..."}`
- [ ] Task 3: Add optional `duration` field for stage timing
- [ ] Task 4: Ensure log file is append-only across pipeline run

**Dependencies:** None (can start immediately)
**Labels:** pipeline, logging, json, p1

---

### PIPE-E5-006: Integrate Baseline Update [2 SP]
**Type:** Story | **Priority:** P1 | **Sprint:** 2
**ACs:** AC-E5-015 (post-merge trigger)
**Labels:** pipeline, baselines, p1

**Description:**
As a post-merge process,
I want baselines updated after accepted improvements,
So that quality gate baselines stay current.

*Note: `update_baselines.sh` was implemented in Epic 1. This story integrates it into the operational workflow.*

**Acceptance Criteria:**

**AC-E5-015:** Post-Merge Trigger
- [ ] GIVEN PR merged to main WHEN developer runs `make update-baselines` THEN baselines refreshed from latest quality gate run
| Baseline | Manual baseline management | Target | Single-command update | Measurement | Makefile target execution | Impact | R-003 |

**Tasks:**
- [ ] Task 1: Document baseline update process in README
- [ ] Task 2: Add post-merge checklist to PR template
- [ ] Task 3: Verify `make update-baselines` works end-to-end

**Dependencies:** Epic 1 baseline infrastructure
**Labels:** pipeline, baselines, documentation, p1

---

### PIPE-E5-007: .gitignore & Cleanup [2 SP]
**Type:** Story | **Priority:** P2 | **Sprint:** 2
**ACs:** AC-E5-016 (gitignore entries)
**Labels:** pipeline, cleanup, p2

**Description:**
As a repository maintainer,
I want pipeline artifacts excluded from git,
So that runs/ and logs/ directories don't pollute the repository.

**Acceptance Criteria:**

**AC-E5-016:** gitignore Entries
- [ ] GIVEN `.gitignore` WHEN checked THEN includes `runs/`, `logs/`, and pipeline temp files
| Baseline | No pipeline entries | Target | All artifacts excluded | Measurement | `git status` clean after run | Impact | NFR-007 |

**Tasks:**
- [ ] Task 1: Add entries to `.gitignore`: `runs/`, `logs/`, `*.pyc`, `__pycache__/`
- [ ] Task 2: Verify with test pipeline run

**Dependencies:** None
**Labels:** pipeline, cleanup, gitignore, p2

---

## Summary

| Sprint | Stories | SP | Theme |
|--------|---------|-----|-------|
| Sprint 1 | E5-001, E5-002, E5-005 | 21 | Orchestrator + health + logging |
| Sprint 2 | E5-003 to E5-007 + testing | 13 | Scheduling + notifications + polish |
| **Total** | **7** | **34** | **4 weeks** |

---

## Sprint Dependencies

```
Sprint 1 (no external deps within sprint):
  E5-002 (Health Check) ──┐
  E5-005 (Logging)     ───┤→ E5-001 (Orchestrator) uses both
                           │
Sprint 2 (depends on orchestrator):
  E5-001 ──→ E5-003 (Scheduler)
  E5-001 ──→ E5-004 (Notifications)
  Epic 1  ──→ E5-006 (Baselines)
  (none)  ──→ E5-007 (.gitignore)
```

---

*Generated by AI PRD Generator v7.0 | Licensed Edition*
