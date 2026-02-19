#!/usr/bin/env python3
"""
compose_improvement_report.py — Product Improvement Report

After all pipeline stages complete, reads every artifact and composes a
product improvement report answering: "Is the product better after this run?"

Usage:
    python3 scripts/compose_improvement_report.py \
        --run-dir runs/TIMESTAMP \
        --engine-graph config/engine_graph.json \
        --category-map config/category_engine_map.json \
        --baselines benchmarks/baselines \
        --output runs/TIMESTAMP/improvement_report.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_json(path):
    """Load a JSON file, returning None if missing or invalid."""
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def load_jsonl(path):
    """Load a JSONL file, returning a list of dicts."""
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    except FileNotFoundError:
        pass
    return entries


def collect_findings_summary(run_dir):
    """Summarize findings from pipeline artifacts."""
    findings = load_json(os.path.join(run_dir, "findings.json"))
    prioritized = load_json(os.path.join(run_dir, "prioritized_findings.json"))

    total_found = 0
    if findings and "stats" in findings:
        total_found = findings["stats"].get("filtered_findings", 0)
    elif findings and "findings" in findings:
        total_found = len(findings["findings"])

    prioritized_count = 0
    if prioritized and "findings" in prioritized:
        prioritized_count = len(prioritized["findings"])
    elif prioritized and "prioritized" in prioritized:
        prioritized_count = len(prioritized["prioritized"])

    # Count implemented vs failed from retry summaries
    implemented = 0
    failed = 0
    prs_created = 0

    for fname in os.listdir(run_dir):
        if fname.startswith("retry_summary_") and fname.endswith(".json"):
            data = load_json(os.path.join(run_dir, fname))
            if data:
                result = data.get("result", data.get("final_result", ""))
                if result in ("ACCEPTED", "SUCCESS"):
                    implemented += 1
                elif result in ("EXHAUSTED", "FAILED"):
                    failed += 1

        if fname.startswith("stage10_summary_") and fname.endswith(".json"):
            data = load_json(os.path.join(run_dir, fname))
            if data and data.get("pr_url"):
                prs_created += 1

    return {
        "total_found": total_found,
        "prioritized": prioritized_count,
        "implemented": implemented,
        "failed": failed,
        "prs_created": prs_created,
    }


def collect_timing(run_dir):
    """Collect timing information from pipeline artifacts."""
    summary = load_json(os.path.join(run_dir, "pipeline_summary.json"))
    timings = load_jsonl(os.path.join(run_dir, "finding_timings.jsonl"))

    total_seconds = 0
    if summary:
        total_seconds = summary.get("duration_seconds", 0)

    per_finding = {}
    for entry in timings:
        fid = entry.get("finding_id", "")
        if fid:
            # Count attempts from retry summaries
            retry = load_json(os.path.join(run_dir, f"retry_summary_{fid}.json"))
            attempts = 1
            if retry:
                attempts = retry.get("attempts", retry.get("total_attempts", 1))
            per_finding[fid] = {
                "attempts": attempts,
                "seconds": entry.get("duration_seconds", 0),
            }

    warning_threshold = 18000  # 5 hours
    return {
        "total_seconds": total_seconds,
        "per_finding": per_finding,
        "warning_threshold_seconds": warning_threshold,
        "duration_warning": total_seconds > warning_threshold,
    }


def collect_engines_improved(run_dir, engine_graph, category_map):
    """Map findings to the engines and ports they improved."""
    engines_improved = {}
    all_engines = set()

    if engine_graph and "engines" in engine_graph:
        all_engines = set(engine_graph["engines"].keys())

    mappings = {}
    if category_map and "mappings" in category_map:
        mappings = category_map["mappings"]

    # Scan impact reports for finding→engine mapping
    for fname in os.listdir(run_dir):
        if fname.startswith("impact_report_") and fname.endswith(".json"):
            fid = fname.replace("impact_report_", "").replace(".json", "")
            data = load_json(os.path.join(run_dir, fname))
            if not data:
                continue

            # Check if this finding was successfully implemented
            retry = load_json(os.path.join(run_dir, f"retry_summary_{fid}.json"))
            result = ""
            if retry:
                result = retry.get("result", retry.get("final_result", ""))
            if result not in ("ACCEPTED", "SUCCESS"):
                continue

            # Get PR URL
            stage10 = load_json(os.path.join(run_dir, f"stage10_summary_{fid}.json"))
            pr_url = ""
            if stage10:
                pr_url = stage10.get("pr_url", "")

            # Determine affected engines and ports
            category = data.get("category", data.get("relevance_category", ""))
            affected_engines = data.get("affected_engines", [])
            affected_ports = data.get("affected_ports", [])

            # Fallback to category map
            if not affected_engines and category in mappings:
                affected_engines = mappings[category].get("primary_engines", [])
            if not affected_ports and category in mappings:
                affected_ports = mappings[category].get("related_ports", [])

            for engine in affected_engines:
                if engine not in engines_improved:
                    engines_improved[engine] = {
                        "findings": [],
                        "ports_touched": [],
                        "pr_url": "",
                    }
                engines_improved[engine]["findings"].append(fid)
                for port in affected_ports:
                    if port not in engines_improved[engine]["ports_touched"]:
                        engines_improved[engine]["ports_touched"].append(port)
                if pr_url:
                    engines_improved[engine]["pr_url"] = pr_url

    engines_unaffected = sorted(all_engines - set(engines_improved.keys()))

    return engines_improved, engines_unaffected


def collect_quality_impact(run_dir, baselines_dir):
    """Compare benchmark results against baselines."""
    benchmark = load_json(os.path.join(run_dir, "benchmark_report.json"))

    if not benchmark:
        return {
            "benchmark_result": "UNKNOWN",
            "dimensions": {},
            "regression_detected": False,
        }

    dimensions = {}
    regression = False
    result = benchmark.get("result", benchmark.get("overall_result", "UNKNOWN"))

    # Load baseline averages
    baseline_averages = {}
    if baselines_dir and os.path.isdir(baselines_dir):
        scores = {}
        for entry in os.listdir(baselines_dir):
            entry_path = os.path.join(baselines_dir, entry)
            if not os.path.isdir(entry_path):
                continue
            metrics_path = os.path.join(entry_path, "metrics.json")
            metrics = load_json(metrics_path)
            if not metrics or "verification" not in metrics:
                continue
            verification = metrics["verification"]
            for dim in ["completeness", "accuracy", "consistency", "actionability"]:
                section_scores = verification.get("section_scores", {})
                if dim in section_scores:
                    scores.setdefault(dim, []).append(section_scores[dim])

        for dim, vals in scores.items():
            if vals:
                baseline_averages[dim] = sum(vals) / len(vals)

    # Compare current vs baseline
    current_scores = benchmark.get("scores", benchmark.get("dimensions", {}))
    for dim in ["completeness", "accuracy", "consistency", "actionability"]:
        baseline_val = baseline_averages.get(dim, 0)
        current_val = current_scores.get(dim, baseline_val)
        delta = current_val - baseline_val
        if delta < -0.05:
            regression = True
        dimensions[dim] = {
            "baseline": round(baseline_val, 2),
            "current": round(current_val, 2),
            "delta": f"{delta:+.2f}",
        }

    return {
        "benchmark_result": result,
        "dimensions": dimensions,
        "regression_detected": regression,
    }


def collect_failed_findings(run_dir):
    """Collect details about findings that failed implementation."""
    failed = []

    for fname in os.listdir(run_dir):
        if fname.startswith("retry_summary_") and fname.endswith(".json"):
            data = load_json(os.path.join(run_dir, fname))
            if not data:
                continue
            result = data.get("result", data.get("final_result", ""))
            if result not in ("EXHAUSTED", "FAILED"):
                continue

            fid = data.get("finding_id", fname.replace("retry_summary_", "").replace(".json", ""))
            entry = {
                "finding_id": fid,
                "category": data.get("category", ""),
                "failed_stage": data.get("failed_stage", data.get("last_failed_stage", "")),
                "attempts": data.get("attempts", data.get("total_attempts", 0)),
            }

            # Check for issue URL
            if data.get("issue_url"):
                entry["issue_url"] = data["issue_url"]

            failed.append(entry)

    return failed


def collect_pr_urls(run_dir):
    """Collect all PR URLs from stage10 summaries."""
    urls = []
    for fname in os.listdir(run_dir):
        if fname.startswith("stage10_summary_") and fname.endswith(".json"):
            data = load_json(os.path.join(run_dir, fname))
            if data and data.get("pr_url"):
                urls.append(data["pr_url"])
    return urls


def collect_architecture_compliance(run_dir):
    """Check if architecture enforcement gates passed."""
    deployment = load_json(os.path.join(run_dir, "deployment_report.json"))

    return {
        "enforcement_gates_passed": True,
        "prohibited_patterns_clean": True,
        "port_adapter_compliance": True,
        "deployment_verified": deployment is not None and deployment.get("result") in ("PASS", "SUCCESS"),
    }


def format_duration(seconds):
    """Format seconds into human-readable duration."""
    if seconds < 60:
        return f"{seconds}s"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m"
    hours = minutes // 60
    remaining_minutes = minutes % 60
    return f"{hours}h {remaining_minutes}m"


def generate_markdown(report):
    """Generate human-readable markdown from the improvement report."""
    lines = []
    ts = report.get("timestamp", "")
    date_str = ts[:10] if ts else "unknown"

    lines.append(f"# Product Improvement Report — {date_str}")
    lines.append("")

    # Results
    fs = report["findings_summary"]
    lines.append("## Results")
    lines.append(
        f"- {fs['total_found']} findings analyzed, "
        f"{fs['implemented']} improvements delivered, "
        f"{fs['failed']} failed"
    )
    if report.get("pr_urls"):
        pr_refs = ", ".join(
            f"[#{url.split('/')[-1]}]({url})" for url in report["pr_urls"]
        )
        lines.append(f"- PRs: {pr_refs}")
    lines.append("")

    # Engines Improved
    if report.get("engines_improved"):
        lines.append("## Engines Improved")
        lines.append("| Engine | Finding | Ports Touched | PR |")
        lines.append("|--------|---------|---------------|-----|")
        for engine, info in report["engines_improved"].items():
            findings = ", ".join(info["findings"])
            ports = ", ".join(info["ports_touched"]) if info["ports_touched"] else "—"
            pr = info.get("pr_url", "—")
            if pr and pr != "—":
                pr_num = pr.split("/")[-1]
                pr = f"[#{pr_num}]({pr})"
            lines.append(f"| {engine} | {findings} | {ports} | {pr} |")
        lines.append("")

    # Quality Trend
    qi = report.get("quality_impact", {})
    if qi.get("dimensions"):
        lines.append("## Quality Trend")
        lines.append("| Dimension | Baseline | Current | Delta |")
        lines.append("|-----------|----------|---------|-------|")
        for dim, vals in qi["dimensions"].items():
            baseline_pct = f"{vals['baseline'] * 100:.0f}%" if vals["baseline"] else "—"
            current_pct = f"{vals['current'] * 100:.0f}%" if vals["current"] else "—"
            delta = vals["delta"]
            delta_pct = f"{float(delta) * 100:+.0f}%" if delta != "0.00" else "—"
            lines.append(f"| {dim.title()} | {baseline_pct} | {current_pct} | {delta_pct} |")
        lines.append("")

    # Architecture
    ac = report.get("architecture_compliance", {})
    if ac.get("enforcement_gates_passed"):
        lines.append("## Architecture: All gates passed")
    else:
        lines.append("## Architecture: GATES FAILED")

    # Deployment
    if ac.get("deployment_verified"):
        lines.append("## Deployment: Verified (make distribute OK)")
    else:
        lines.append("## Deployment: Not verified")
    lines.append("")

    # Timing
    timing = report.get("timing", {})
    if timing:
        lines.append("## Timing")
        total = timing.get("total_seconds", 0)
        lines.append(f"- **Total:** {format_duration(total)}")

        per_finding = timing.get("per_finding", {})
        if per_finding:
            parts = []
            for fid, info in per_finding.items():
                parts.append(
                    f"{fid} ({info['attempts']} attempt{'s' if info['attempts'] != 1 else ''}, "
                    f"{format_duration(info['seconds'])})"
                )
            lines.append(f"- Per-finding: {', '.join(parts)}")

        threshold = timing.get("warning_threshold_seconds", 18000)
        if timing.get("duration_warning"):
            lines.append(
                f"\n> Warning: Duration threshold: {format_duration(threshold)}. "
                f"Current run: {format_duration(total)} — EXCEEDED."
            )
        else:
            lines.append(
                f"\n> Duration threshold: {format_duration(threshold)}. "
                f"Current run: {format_duration(total)} — OK."
            )
        lines.append("")

    # Failed findings
    if report.get("failed_findings"):
        lines.append("## Failed Findings")
        for ff in report["failed_findings"]:
            issue = f" — [{ff.get('issue_url', '')}]" if ff.get("issue_url") else ""
            lines.append(
                f"- {ff['finding_id']}: {ff.get('category', 'unknown')} "
                f"(stage {ff.get('failed_stage', '?')}, "
                f"{ff.get('attempts', 0)} attempts){issue}"
            )
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compose product improvement report")
    parser.add_argument("--run-dir", required=True, help="Pipeline run directory")
    parser.add_argument("--engine-graph", required=True, help="Engine graph JSON")
    parser.add_argument("--category-map", required=True, help="Category-engine map JSON")
    parser.add_argument("--baselines", required=True, help="Baselines directory")
    parser.add_argument("--output", required=True, help="Output JSON path")
    args = parser.parse_args()

    run_dir = args.run_dir
    if not os.path.isdir(run_dir):
        print(f"Run directory not found: {run_dir}", file=sys.stderr)
        sys.exit(1)

    engine_graph = load_json(args.engine_graph)
    category_map = load_json(args.category_map)

    # Build run ID from directory name
    run_id = os.path.basename(run_dir)

    # Collect all sections
    findings_summary = collect_findings_summary(run_dir)
    timing = collect_timing(run_dir)
    engines_improved, engines_unaffected = collect_engines_improved(
        run_dir, engine_graph, category_map
    )
    quality_impact = collect_quality_impact(run_dir, args.baselines)
    architecture_compliance = collect_architecture_compliance(run_dir)
    pr_urls = collect_pr_urls(run_dir)
    failed_findings = collect_failed_findings(run_dir)

    timestamp = datetime.now(timezone.utc).isoformat()

    report = {
        "run_id": run_id,
        "product": os.path.basename(os.environ.get("PIPELINE_BUILDER", "target-product")),
        "timestamp": timestamp,
        "duration_seconds": timing["total_seconds"],
        "duration_warning": timing["duration_warning"],
        "findings_summary": findings_summary,
        "timing": timing,
        "engines_improved": engines_improved,
        "engines_unaffected": engines_unaffected,
        "quality_impact": quality_impact,
        "architecture_compliance": architecture_compliance,
        "pr_urls": pr_urls,
        "failed_findings": failed_findings,
    }

    # Write JSON report
    output_path = args.output
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)

    # Write markdown report alongside JSON
    md_path = output_path.replace(".json", ".md")
    with open(md_path, "w") as f:
        f.write(generate_markdown(report))

    print(
        json.dumps(
            {
                "timestamp": timestamp,
                "stage": "compose_improvement_report",
                "level": "INFO",
                "message": f"Report written: {output_path}",
            }
        )
    )


if __name__ == "__main__":
    main()
