#!/usr/bin/env python3
"""
progress.py — Pipeline Progress Reporter

Reads the artifact layout under $RUN_DIR/findings/ and progress.jsonl
to display a live-updating progress table.

Usage:
    python3 scripts/progress.py --run-dir runs/LATEST
    python3 scripts/progress.py --run-dir runs/20260226_020000 --watch
    python3 scripts/progress.py --run-dir runs/LATEST --json
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Stage detection
# ---------------------------------------------------------------------------

# Ordered list of stage artifact files to detect highest stage reached
STAGE_FILES = [
    (2, "stage2-impact.json"),
    (3, "stage3-integration.json"),
    (5, "stage5-prd/prd.md"),
    (6, "stage6-review.json"),
    (7, "attempts/1/stage7-summary.json"),
    (10, "attempts/1/stage10-enforcement.json"),
    (11, "attempts/1/stage11-verification.json"),
]

STATUS_LABELS = {
    0: "QUEUED",
    2: "IMPACT",
    3: "DESIGN",
    5: "PRD",
    6: "REVIEW",
    7: "IMPL",
    10: "GATES",
    11: "VERIFY",
    12: "BENCH",
    13: "DEPLOY",
    14: "PR",
    99: "ACCEPTED",
    -1: "FAILED",
}


def detect_finding_stage(run_dir, fid):
    """Detect the highest stage reached for a finding."""
    fid_dir = os.path.join(run_dir, "findings", fid)
    if not os.path.isdir(fid_dir):
        return 0, "QUEUED", 0

    highest_stage = 0
    current_attempt = 1

    # Check for retry state to get current attempt
    for name in ("retry-state.json", f"retry_state_{fid}.json"):
        rpath = os.path.join(fid_dir, name)
        if not os.path.isfile(rpath):
            rpath = os.path.join(run_dir, name)
        if os.path.isfile(rpath):
            try:
                with open(rpath) as f:
                    state = json.load(f)
                current_attempt = state.get("current_attempt", 1) or 1
            except (json.JSONDecodeError, OSError):
                pass
            break

    # Check stage artifacts (try current attempt first, then attempt 1)
    for stage_num, rel_path in STAGE_FILES:
        # Check in finding dir directly
        if os.path.isfile(os.path.join(fid_dir, rel_path)):
            highest_stage = stage_num
            continue
        # Check with attempt number substituted
        for attempt in (current_attempt, 1):
            attempt_path = rel_path.replace("attempts/1/", f"attempts/{attempt}/")
            if os.path.isfile(os.path.join(fid_dir, attempt_path)):
                highest_stage = stage_num
                break

    # Check for retry summary (final result)
    for name in ("retry-summary.json", f"retry_summary_{fid}.json"):
        rpath = os.path.join(fid_dir, name)
        if not os.path.isfile(rpath):
            rpath = os.path.join(run_dir, name)
        if os.path.isfile(rpath):
            try:
                with open(rpath) as f:
                    summary = json.load(f)
                result = summary.get("result", "")
                if result == "ACCEPTED":
                    return 99, "ACCEPTED", summary.get("total_attempts", current_attempt)
                elif result == "EXHAUSTED":
                    return -1, "FAILED", summary.get("total_attempts", current_attempt)
            except (json.JSONDecodeError, OSError):
                pass
            break

    # Check for stage5 validation (between PRD and impl)
    for name in ("stage5-validation.json", "stage4-validation.json", f"validation_stage4_{fid}.json"):
        vpath = os.path.join(fid_dir, name)
        if not os.path.isfile(vpath):
            vpath = os.path.join(run_dir, name)
        if os.path.isfile(vpath):
            try:
                with open(vpath) as f:
                    val = json.load(f)
                if val.get("result") == "ACCEPTED" and highest_stage < 6:
                    highest_stage = 5
            except (json.JSONDecodeError, OSError):
                pass
            break

    status = STATUS_LABELS.get(highest_stage, f"STAGE-{highest_stage}")
    max_attempts = 3
    attempt_str = f"{current_attempt}/{max_attempts}"

    return highest_stage, status, attempt_str


def list_findings(run_dir):
    """List all finding IDs in the run directory."""
    findings_dir = os.path.join(run_dir, "findings")
    if os.path.isdir(findings_dir):
        return sorted(
            d for d in os.listdir(findings_dir)
            if os.path.isdir(os.path.join(findings_dir, d))
        )
    return []


def read_progress_events(run_dir):
    """Read progress.jsonl for timing and event data."""
    events = []
    progress_file = os.path.join(run_dir, "progress.jsonl")
    if os.path.isfile(progress_file):
        with open(progress_file) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    return events


def read_pipeline_summary(run_dir):
    """Read pipeline_summary.json if available."""
    path = os.path.join(run_dir, "pipeline_summary.json")
    if os.path.isfile(path):
        try:
            with open(path) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return None


def get_finding_duration(events, fid):
    """Get duration from progress events for a finding."""
    start_ts = None
    end_ts = None
    for ev in events:
        if ev.get("fid") != fid:
            continue
        ts_str = ev.get("ts", "")
        try:
            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            continue
        if start_ts is None or ts < start_ts:
            start_ts = ts
        if end_ts is None or ts > end_ts:
            end_ts = ts

    if start_ts and end_ts and start_ts != end_ts:
        delta = (end_ts - start_ts).total_seconds()
        return format_duration(int(delta))
    return "--:--"


def format_duration(seconds):
    """Format seconds as human-readable duration."""
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        m, s = divmod(seconds, 60)
        return f"{m}m {s}s"
    else:
        h, remainder = divmod(seconds, 3600)
        m, _ = divmod(remainder, 60)
        return f"{h}h {m:02d}m"


def resolve_latest_run(runs_base):
    """Find the most recent run directory."""
    if not os.path.isdir(runs_base):
        return None
    dirs = sorted(
        (d for d in os.listdir(runs_base)
         if os.path.isdir(os.path.join(runs_base, d)) and not d.startswith(".")),
        reverse=True,
    )
    return os.path.join(runs_base, dirs[0]) if dirs else None


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def render_table(run_dir):
    """Render the progress table."""
    findings = list_findings(run_dir)
    events = read_progress_events(run_dir)
    summary = read_pipeline_summary(run_dir)

    run_name = os.path.basename(run_dir)

    # Elapsed time
    elapsed = ""
    if summary:
        elapsed = format_duration(summary.get("duration_seconds", 0))
    else:
        # Estimate from directory mtime
        try:
            mtime = os.path.getmtime(run_dir)
            elapsed = format_duration(int(time.time() - mtime))
        except OSError:
            elapsed = "?"

    total = len(findings)
    accepted = 0
    failed = 0
    in_progress = 0

    rows = []
    for fid in findings:
        stage, status, attempt = detect_finding_stage(run_dir, fid)
        duration = get_finding_duration(events, fid)

        if stage == 99:
            accepted += 1
        elif stage == -1:
            failed += 1
        elif stage > 0:
            in_progress += 1

        rows.append((fid, stage, status, duration, attempt))

    # Header
    lines = []
    lines.append(f"AI Architect Pipeline -- Run {run_name}")
    lines.append("=" * 56)

    done = accepted + failed
    lines.append(f"Elapsed: {elapsed} | Findings: {done}/{total} | "
                 f"Accepted: {accepted} | Failed: {failed}")
    lines.append("")

    # Table
    header = f"{'Finding':<14} {'Stage':<8} {'Status':<10} {'Duration':<10} {'Attempt'}"
    lines.append(header)
    lines.append("-" * len(header))

    for fid, stage, status, duration, attempt in rows:
        fid_short = fid[:13]
        stage_str = str(stage) if stage > 0 else "--"
        if stage == 99:
            stage_str = "DONE"
        elif stage == -1:
            stage_str = "FAIL"
        lines.append(
            f"{fid_short:<14} {stage_str:<8} {status:<10} {duration:<10} {attempt}"
        )

    if not rows:
        lines.append("  (no findings detected)")

    return "\n".join(lines)


def render_json(run_dir):
    """Render progress as JSON."""
    findings = list_findings(run_dir)
    events = read_progress_events(run_dir)
    summary = read_pipeline_summary(run_dir)

    result = {
        "run_dir": run_dir,
        "run_id": os.path.basename(run_dir),
        "total_findings": len(findings),
        "findings": [],
    }

    if summary:
        result["duration_seconds"] = summary.get("duration_seconds", 0)
        result["prs_created"] = summary.get("prs_created", 0)

    for fid in findings:
        stage, status, attempt = detect_finding_stage(run_dir, fid)
        result["findings"].append({
            "finding_id": fid,
            "stage": stage,
            "status": status,
            "attempt": attempt,
        })

    return json.dumps(result, indent=2)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Pipeline progress reporter")
    parser.add_argument(
        "--run-dir", required=True,
        help="Path to run directory (or 'LATEST' to auto-detect)"
    )
    parser.add_argument(
        "--watch", action="store_true",
        help="Refresh every 5 seconds"
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output as JSON instead of table"
    )
    parser.add_argument(
        "--interval", type=int, default=5,
        help="Refresh interval in seconds (with --watch)"
    )
    args = parser.parse_args()

    run_dir = args.run_dir

    # Resolve LATEST
    if run_dir.endswith("LATEST") or run_dir == "LATEST":
        base = os.path.dirname(run_dir) if "/" in run_dir else "runs"
        resolved = resolve_latest_run(base)
        if not resolved:
            print("ERROR: No runs found", file=sys.stderr)
            sys.exit(1)
        run_dir = resolved

    if not os.path.isdir(run_dir):
        print(f"ERROR: Run directory not found: {run_dir}", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(render_json(run_dir))
        return

    if args.watch:
        try:
            while True:
                # Clear screen
                print("\033[2J\033[H", end="")
                print(render_table(run_dir))
                print(f"\nRefreshing every {args.interval}s... (Ctrl+C to stop)")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nStopped.")
    else:
        print(render_table(run_dir))


if __name__ == "__main__":
    main()
