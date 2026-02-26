#!/usr/bin/env python3
"""
Manifest Generator (PIPE-E2-005)

Converts validated integration plans into the exact format consumed by
Stage 10 Gate 2 (manifest compliance check in stage10-gates.sh).

Produces:
  - must_change: files from plan's modify-action entries
  - must_not_change: critical files in unaffected engines
  - allowed_new_files: plan's test files

Usage:
    python3 scripts/generate_manifest.py \
        --plan integration_plan_tv-001.json \
        --engine-graph config/engine_graph.json \
        --output manifest_tv-001.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_json(path):
    """Load JSON file. Exit 1 on failure."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"ERROR: Cannot load {path}: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Manifest generation
# ---------------------------------------------------------------------------

def generate(plan, engine_graph):
    """Generate Gate 2-compatible manifest from integration plan.

    Returns manifest dict.
    """
    # must_change: all modify-action file paths
    must_change = []
    for mod in plan.get("modifications", []):
        for file_entry in mod.get("files", []):
            if file_entry.get("action") == "modify":
                path = file_entry.get("path", "")
                if path and path not in must_change:
                    must_change.append(path)

    # must_not_change: critical config files in unaffected engines
    affected = set(plan.get("affected_engines", []))
    all_engines = set(engine_graph.get("engines", {}).keys())
    unaffected = all_engines - affected

    must_not_change = []
    engines_data = engine_graph.get("engines", {})
    for engine in sorted(unaffected):
        pkg_path = engines_data.get(engine, {}).get("package_path", "")
        if pkg_path:
            must_not_change.append(pkg_path)

    # Always protect these
    must_not_change.append("Makefile")

    # allowed_new_files: plan's test files
    allowed_new_files = list(plan.get("test_files", []))

    return {
        "generated_from": plan.get("finding_id", "unknown"),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "must_change": sorted(must_change),
        "must_not_change": sorted(must_not_change),
        "allowed_new_files": sorted(allowed_new_files),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate Gate 2-compatible manifest from integration plan"
    )
    parser.add_argument(
        "--plan", required=True,
        help="Path to integration plan JSON"
    )
    parser.add_argument(
        "--engine-graph", required=True,
        help="Path to engine_graph.json"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write manifest JSON"
    )
    args = parser.parse_args(argv)

    plan = load_json(args.plan)
    engine_graph = load_json(args.engine_graph)

    manifest = generate(plan, engine_graph)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(json.dumps({
        "stage": "generate_manifest",
        "finding_id": plan.get("finding_id", "unknown"),
        "must_change": len(manifest["must_change"]),
        "must_not_change": len(manifest["must_not_change"]),
        "allowed_new_files": len(manifest["allowed_new_files"]),
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
