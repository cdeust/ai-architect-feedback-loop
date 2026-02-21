#!/usr/bin/env python3
"""
compose_pr.py — PR Description Composer

Assembles all stage outputs into a structured PR description with collapsible
sections. Reads the pipeline's actual output files and formats them for human
review on GitHub.

Usage:
    python3 scripts/compose_pr.py \
        --run-dir runs/TIMESTAMP \
        --finding-id tv-001 \
        --engine-graph config/engine_graph.json \
        --output pr_description.md
"""

import argparse
import json
import os
import sys


def load_json(path):
    """Load a JSON file, returning None if not found or invalid."""
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return None


def find_file(run_dir, *candidates):
    """Return the first candidate path that exists under run_dir, or None."""
    for candidate in candidates:
        path = os.path.join(run_dir, candidate)
        if os.path.isfile(path):
            return path
    # Also check in attempt subdirectories
    for entry in sorted(os.listdir(run_dir)):
        attempt_dir = os.path.join(run_dir, entry)
        if os.path.isdir(attempt_dir) and entry.startswith("attempt_"):
            for candidate in candidates:
                path = os.path.join(attempt_dir, candidate)
                if os.path.isfile(path):
                    return path
    return None


def read_text(path, max_lines=None):
    """Read a text file, optionally truncating to max_lines."""
    if not path or not os.path.isfile(path):
        return None
    with open(path) as f:
        if max_lines:
            lines = []
            for i, line in enumerate(f):
                if i >= max_lines:
                    lines.append(f"\n... (truncated after {max_lines} lines)")
                    break
                lines.append(line)
            return "".join(lines)
        return f.read()


def compose_summary(finding_id, impact, retry_summary, verification, prd_verification, run_dir):
    """Compose the summary section."""
    lines = ["## Summary"]

    title = "Unknown"
    category = "unknown"
    engines = []
    ports = []
    compound_score = 0
    recommendation = "UNKNOWN"

    if impact:
        title = impact.get("finding_title", finding_id)
        category = impact.get("finding_category", "unknown")
        engines = impact.get("affected_engines", [])
        compound_score = impact.get("compound_score", 0)
        recommendation = impact.get("recommendation", "UNKNOWN")

    # Attempt count
    attempts = 1
    max_attempts = 3
    if retry_summary:
        attempts = retry_summary.get("total_attempts", 1)
        max_attempts = retry_summary.get("max_attempts", 3)

    # PRD quality score
    prd_score = "N/A"
    if prd_verification:
        text = prd_verification if isinstance(prd_verification, str) else ""
        import re
        match = re.search(r"\*\*Overall Score:\*\*\s*(\d+)%", text)
        if match:
            prd_score = f"{match.group(1)}%"

    # Verification confidence
    confidence = "N/A"
    prd_alignment = "N/A"
    if verification:
        conf = verification.get("confidence", 0)
        confidence = f"{int(conf * 100)}%" if isinstance(conf, float) and conf <= 1 else f"{conf}%"
        align = verification.get("prd_alignment_score", 0)
        prd_alignment = f"{int(align * 100)}%" if isinstance(align, float) and align <= 1 else f"{align}%"

    # Run ID from directory name
    run_id = os.path.basename(run_dir) if run_dir else "unknown"

    lines.append(f"- **Finding:** {finding_id} — {title}")
    lines.append(f"- **Category:** {category} — Primary engines: {', '.join(engines) if engines else 'N/A'}")
    lines.append(f"- **Engines Affected:** {', '.join(engines) if engines else 'N/A'}")
    lines.append(f"- **Compound Score:** {compound_score}")
    lines.append(f"- **Pipeline Run:** {run_id}")
    lines.append(f"- **Attempts:** {attempts} of {max_attempts}")
    lines.append(f"- **PRD Quality Score:** {prd_score}")
    lines.append(f"- **Verification Confidence:** {confidence}")

    return "\n".join(lines)


def compose_impact(impact):
    """Compose the impact analysis section."""
    if not impact:
        return ""

    lines = ["## Impact Analysis"]

    propagation = impact.get("propagation_paths", [])
    if propagation:
        for path in propagation:
            fr = path.get("from", "?")
            to = path.get("to", "?")
            rel = path.get("relationship", "?")
            lines.append(f"- **Propagation:** {fr} -> {to} ({rel})")

    recommendation = impact.get("recommendation", "UNKNOWN")
    lines.append(f"- **Recommendation:** {recommendation}")

    return "\n".join(lines)


def compose_integration_plan(integration_plan):
    """Compose collapsible integration plan section."""
    if not integration_plan:
        return ""

    lines = []
    lines.append("<details><summary>Integration Plan (JSON)</summary>")
    lines.append("")
    lines.append("```json")
    lines.append(json.dumps(integration_plan, indent=2))
    lines.append("```")
    lines.append("")
    lines.append("</details>")

    return "\n".join(lines)


def _load_prd_max_lines():
    """Load prd_max_lines from pipeline_preferences.json, default 100."""
    prefs_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "config", "pipeline_preferences.json"
    )
    if os.path.isfile(prefs_path):
        try:
            with open(prefs_path) as f:
                prefs = json.load(f)
            return prefs.get("pr", {}).get("prd_max_lines", 100)
        except (json.JSONDecodeError, IOError):
            pass
    return 100


def compose_prd_section(prd_content):
    """Compose collapsible PRD section (first N lines from preferences)."""
    if not prd_content:
        return ""

    max_lines = _load_prd_max_lines()
    prd_lines = prd_content.split("\n")[:max_lines]
    truncated = "\n".join(prd_lines)

    lines = []
    lines.append(f"<details><summary>PRD Specification (first {max_lines} lines)</summary>")
    lines.append("")
    lines.append(truncated)
    lines.append("")
    if len(prd_content.split("\n")) > max_lines:
        lines.append(f"... (truncated, {len(prd_content.split(chr(10)))} total lines)")
        lines.append("")
    lines.append("</details>")

    return "\n".join(lines)


def compose_enforcement(enforcement):
    """Compose enforcement results table."""
    lines = ["## Enforcement Results"]
    lines.append("| Gate | Name | Result |")
    lines.append("|------|------|--------|")

    if enforcement:
        gates = enforcement.get("gates", [])
        for gate in gates:
            num = gate.get("gate", "?")
            name = gate.get("name", "?")
            result = gate.get("result", "?")
            # Add descriptive names for known gates
            display_name = {
                "prohibited_patterns": "Prohibited Patterns",
                "manifest_compliance": "Manifest Compliance",
                "orphan_detection": "Orphan Detection",
                "build_verification": "Build Verification (make build-library)",
                "test_suite": "Test Suite (make test-all)",
                "encryption_integrity": "Encryption Integrity (make distribute)",
            }.get(name, name)
            lines.append(f"| {num} | {display_name} | {result} |")
    else:
        lines.append("| — | No enforcement data | — |")

    return "\n".join(lines)


def compose_verification(verification):
    """Compose verification results section."""
    lines = ["## Verification Results"]

    if not verification:
        lines.append("- **Overall:** No verification data available")
        return "\n".join(lines)

    overall = verification.get("overall_result", "UNKNOWN")
    confidence = verification.get("confidence", 0)
    conf_pct = f"{int(confidence * 100)}%" if isinstance(confidence, float) and confidence <= 1 else f"{confidence}%"

    prd_align = verification.get("prd_alignment_score", 0)
    align_pct = f"{int(prd_align * 100)}%" if isinstance(prd_align, float) and prd_align <= 1 else f"{prd_align}%"

    req_traced = verification.get("requirements_traced", {})
    total_req = req_traced.get("total", 0)
    matched_req = req_traced.get("matched", 0)

    cross = verification.get("cross_engine_verification", {})
    tp_verified = cross.get("touchpoints_verified", 0)
    tp_total = cross.get("touchpoints_total", 0)

    anti = verification.get("anti_patterns_detected", [])

    lines.append(f"- **Overall:** {overall} (confidence: {conf_pct})")
    lines.append(f"- **PRD Alignment:** {align_pct} — {matched_req}/{total_req} FR requirements traced to code")
    lines.append(f"- **Cross-Engine:** {tp_verified}/{tp_total} touchpoints verified")
    lines.append(f"- **Anti-Patterns:** {', '.join(anti) if anti else 'None detected'}")

    return "\n".join(lines)


def compose_retry_history(retry_summary):
    """Compose retry history table."""
    lines = ["## Retry History"]
    lines.append("| Attempt | Result | Stage | Details |")
    lines.append("|---------|--------|-------|---------|")

    if retry_summary:
        attempts = retry_summary.get("attempts", [])
        total = retry_summary.get("total_attempts", 1)
        result = retry_summary.get("result", "ACCEPTED")

        if not attempts:
            # Success on first attempt
            lines.append("| 1 | PASS | — | Succeeded on first attempt |")
        else:
            for a in attempts:
                num = a.get("attempt", "?")
                stage = a.get("failed_stage", "?")
                reason = a.get("failure_reason", "?")
                # Truncate long reasons
                if len(reason) > 60:
                    reason = reason[:57] + "..."
                lines.append(f"| {num} | FAIL | {stage} | {reason} |")

            # If result is ACCEPTED, the last attempt succeeded
            if result == "ACCEPTED":
                lines.append(f"| {total} | PASS | — | Succeeded |")
    else:
        lines.append("| 1 | PASS | — | Succeeded on first attempt |")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compose PR description from pipeline outputs")
    parser.add_argument("--run-dir", required=True, help="Pipeline run directory")
    parser.add_argument("--finding-id", required=True, help="Finding identifier")
    parser.add_argument("--engine-graph", required=False, help="Path to engine_graph.json")
    parser.add_argument("--output", required=True, help="Output file path for PR description")
    args = parser.parse_args()

    fid = args.finding_id
    run_dir = args.run_dir

    # Load pipeline outputs
    impact_path = find_file(run_dir, f"impact_report_{fid}.json")
    impact = load_json(impact_path)

    integration_path = find_file(run_dir, f"integration_plan_{fid}.json")
    integration_plan = load_json(integration_path)

    prd_path = find_file(run_dir, f"prd_output_{fid}/prd.md")
    prd_content = read_text(prd_path)

    prd_verif_path = find_file(run_dir, f"prd_output_{fid}/prd-verification.md")
    prd_verification = read_text(prd_verif_path)

    enforcement_path = find_file(run_dir, "enforcement_report.json")
    enforcement = load_json(enforcement_path)

    verification_path = find_file(run_dir, f"verification_stage7_{fid}.json")
    verification = load_json(verification_path)

    retry_path = find_file(run_dir, f"retry_summary_{fid}.json")
    retry_summary = load_json(retry_path)

    # Compose sections
    sections = []

    sections.append(compose_summary(fid, impact, retry_summary, verification, prd_verification, run_dir))
    sections.append("")

    impact_section = compose_impact(impact)
    if impact_section:
        sections.append(impact_section)
        sections.append("")

    plan_section = compose_integration_plan(integration_plan)
    if plan_section:
        sections.append(plan_section)
        sections.append("")

    prd_section = compose_prd_section(prd_content)
    if prd_section:
        sections.append(prd_section)
        sections.append("")

    sections.append(compose_enforcement(enforcement))
    sections.append("")

    sections.append(compose_verification(verification))
    sections.append("")

    sections.append(compose_retry_history(retry_summary))
    sections.append("")

    sections.append("---")
    sections.append(f"Generated by AI Architect Pipeline | Finding: {fid}")

    output = "\n".join(sections)

    with open(args.output, "w") as f:
        f.write(output)
        f.write("\n")

    print(f"PR description written to {args.output} ({len(output)} chars)")


if __name__ == "__main__":
    main()
