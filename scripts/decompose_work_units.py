#!/usr/bin/env python3
"""
decompose_work_units.py — Split implementation into work units by module

Reads the integration plan and PRD, then produces one work unit JSON file
per engine modification. Each work unit is a self-contained slice that a
parallel worker can implement independently.

Usage:
    python3 scripts/decompose_work_units.py \
        --integration-plan runs/TS/findings/FID/stage3-integration.json \
        --prd runs/TS/findings/FID/stage5-prd/prd.md \
        --manifest runs/TS/findings/FID/stage3-manifest.json \
        --output-dir /tmp/work_units
"""

import argparse
import json
import os
import re
import sys


def extract_prd_sections_for_engine(prd_text, engine_name):
    """Extract PRD sections that mention this engine."""
    lines = prd_text.split("\n")
    relevant = []
    in_section = False
    section_header = ""

    for line in lines:
        # Detect headers
        if line.startswith("#"):
            in_section = False
            section_header = line

        # Check if engine is mentioned
        if engine_name.lower() in line.lower():
            if not in_section:
                in_section = True
                relevant.append(section_header)
            relevant.append(line)
        elif in_section:
            # Continue capturing until next header of same or higher level
            if line.startswith("#") and not engine_name.lower() in line.lower():
                in_section = False
            else:
                relevant.append(line)

    if not relevant:
        # Fallback: return full PRD if engine not specifically mentioned
        return prd_text

    return "\n".join(relevant)


def extract_engine_contracts(plan_modification):
    """Extract contract changes from a single engine's modification."""
    contracts = []
    for change in plan_modification.get("contract_changes", []):
        contracts.append({
            "protocol": change.get("protocol", ""),
            "change": change.get("change", change.get("description", "")),
        })
    return contracts


def decompose(integration_plan, prd_text, manifest=None):
    """Split implementation into work units by engine module.

    Returns a list of work unit dicts.
    """
    modifications = integration_plan.get("modifications", [])
    cross_engine = integration_plan.get("cross_engine_touchpoints", [])
    finding_id = integration_plan.get("finding_id", "unknown")

    # Build advised_changes / not_advised_changes sets per engine
    advised_changes_set = set()
    not_advised_changes_set = set()
    if manifest:
        advised_changes_set = set(manifest.get("advised_changes", []))
        not_advised_changes_set = set(manifest.get("not_advised_changes", []))

    work_units = []
    for i, mod in enumerate(modifications):
        engine = mod.get("engine", f"engine_{i}")
        files = [f.get("path", "") for f in mod.get("files", []) if f.get("path")]
        file_actions = {
            f.get("path", ""): {
                "action": f.get("action", "modify"),
                "description": f.get("description", ""),
            }
            for f in mod.get("files", []) if f.get("path")
        }

        # Filter manifest constraints to this engine's files
        wu_advised_changes = [f for f in files if f in advised_changes_set]
        wu_not_advised_changes = sorted(not_advised_changes_set)

        # Find cross-engine touchpoints involving this engine
        wu_touchpoints = []
        for tp in cross_engine:
            if tp.get("from") == engine or tp.get("to") == engine:
                wu_touchpoints.append(tp)

        # Extract relevant PRD sections
        prd_slice = extract_prd_sections_for_engine(prd_text, engine)

        work_unit = {
            "id": f"wu-{i + 1:03d}",
            "finding_id": finding_id,
            "engine": engine,
            "files": files,
            "file_actions": file_actions,
            "contracts": extract_engine_contracts(mod),
            "touchpoints": wu_touchpoints,
            "advised_changes": wu_advised_changes,
            "not_advised_changes": wu_not_advised_changes,
            "prd_slice": prd_slice,
        }
        work_units.append(work_unit)

    return work_units


def main():
    parser = argparse.ArgumentParser(
        description="Decompose implementation into work units by engine"
    )
    parser.add_argument(
        "--integration-plan", required=True,
        help="Path to integration plan JSON"
    )
    parser.add_argument(
        "--prd", required=True,
        help="Path to PRD markdown file"
    )
    parser.add_argument(
        "--manifest", default=None,
        help="Path to manifest JSON (optional)"
    )
    parser.add_argument(
        "--output-dir", required=True,
        help="Directory to write work unit JSON files"
    )

    args = parser.parse_args()

    # Load inputs
    with open(args.integration_plan) as f:
        plan = json.load(f)

    with open(args.prd) as f:
        prd_text = f.read()

    manifest = None
    if args.manifest and os.path.isfile(args.manifest):
        with open(args.manifest) as f:
            manifest = json.load(f)

    # Decompose
    work_units = decompose(plan, prd_text, manifest)

    # Write output
    os.makedirs(args.output_dir, exist_ok=True)
    for wu in work_units:
        path = os.path.join(args.output_dir, f"{wu['id']}.json")
        with open(path, "w") as f:
            json.dump(wu, f, indent=2)
            f.write("\n")

    # Summary to stdout
    print(json.dumps({
        "total_work_units": len(work_units),
        "engines": [wu["engine"] for wu in work_units],
        "output_dir": args.output_dir,
    }))


if __name__ == "__main__":
    main()
