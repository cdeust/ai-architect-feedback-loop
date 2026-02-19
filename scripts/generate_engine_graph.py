#!/usr/bin/env python3
"""
Engine Dependency Graph Generator (PIPE-E1-003)

Parses all Package.swift files in the builder project, merges manual
overrides, detects cycles, and writes engine_graph.json.

Usage:
    python3 scripts/generate_engine_graph.py \
        --packages-dir /path/to/target-product/packages \
        --overrides config/engine_graph_overrides.json \
        --output config/engine_graph.json
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

GENERATOR_VERSION = "1.0"
AIPRD_PREFIX = "AIPRD"


# ---------------------------------------------------------------------------
# Package.swift parsing
# ---------------------------------------------------------------------------

def discover_packages(packages_dir):
    """Find all AIPRD*/Package.swift under packages_dir."""
    pattern = os.path.join(packages_dir, "AIPRD*", "Package.swift")
    return sorted(glob.glob(pattern))


def parse_package_swift(filepath):
    """Extract package name and local dependencies from a Package.swift file.

    Returns (package_name, [local_dep_names]) where names are full AIPRD-prefixed.
    Only `.package(path: ...)` entries are considered (URL deps are ignored).
    """
    with open(filepath, "r") as f:
        content = f.read()

    # Extract package name: name: "AIPRDFoo"
    name_match = re.search(r'name:\s*"(AIPRD[^"]+)"', content)
    if not name_match:
        return None, []
    package_name = name_match.group(1)

    # Extract local path dependencies: .package(path: "../AIPRDFoo")
    local_deps = re.findall(r'\.package\(\s*path:\s*"[^"]*(AIPRD[^"]+)"\s*\)', content)

    return package_name, local_deps


def strip_prefix(full_name):
    """AIPRDSharedUtilities -> SharedUtilities"""
    if full_name.startswith(AIPRD_PREFIX):
        return full_name[len(AIPRD_PREFIX):]
    return full_name


# ---------------------------------------------------------------------------
# Graph construction
# ---------------------------------------------------------------------------

def build_graph(packages_dir):
    """Parse all Package.swift files and return adjacency data.

    Returns dict: {
        short_name: {
            "package_path": relative path,
            "depends_on": [short names],
            "depended_by": [],   # populated after
        }
    }
    """
    package_files = discover_packages(packages_dir)
    if not package_files:
        print(f"ERROR: No Package.swift files found in {packages_dir}/AIPRD*/",
              file=sys.stderr)
        sys.exit(1)

    engines = {}
    for filepath in package_files:
        full_name, full_deps = parse_package_swift(filepath)
        if full_name is None:
            continue

        short = strip_prefix(full_name)
        package_dir = os.path.dirname(filepath)
        rel_path = os.path.relpath(package_dir, os.path.dirname(packages_dir))

        engines[short] = {
            "package_path": rel_path,
            "depends_on": sorted(strip_prefix(d) for d in full_deps),
            "depended_by": [],
        }

    # Populate depended_by (reverse edges)
    for name, data in engines.items():
        for dep in data["depends_on"]:
            if dep in engines:
                engines[dep]["depended_by"].append(name)

    # Sort depended_by for deterministic output
    for data in engines.values():
        data["depended_by"].sort()

    return engines


# ---------------------------------------------------------------------------
# Override merging
# ---------------------------------------------------------------------------

def load_overrides(overrides_path):
    """Load engine_graph_overrides.json and return the engines dict."""
    if not overrides_path or not os.path.exists(overrides_path):
        return {}
    with open(overrides_path, "r") as f:
        data = json.load(f)
    return data.get("engines", {})


def merge_overrides(engines, overrides):
    """Deep-merge override fields (feeds, fed_by, role) into engines.

    Override keys that don't match a parsed engine are added as new entries
    (for aliases like PromptEngine → MetaPromptingEngine scenario).
    """
    for name, override_data in overrides.items():
        if name not in engines:
            # Override references an engine not found in Package.swift —
            # add a placeholder entry so override data isn't lost
            engines[name] = {
                "package_path": "",
                "depends_on": [],
                "depended_by": [],
            }
        entry = engines[name]
        if "feeds" in override_data:
            entry["feeds"] = override_data["feeds"]
        if "fed_by" in override_data:
            entry["fed_by"] = override_data["fed_by"]
        if "role" in override_data:
            entry["role"] = override_data["role"]

    # Ensure every engine has feeds/fed_by/role even without overrides
    for data in engines.values():
        data.setdefault("feeds", [])
        data.setdefault("fed_by", [])
        data.setdefault("role", "")

    return engines


# ---------------------------------------------------------------------------
# Cycle detection
# ---------------------------------------------------------------------------

def detect_cycles(engines):
    """DFS-based cycle detection on depends_on edges.

    Returns list of cycle paths found (each is a list of engine names).
    """
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {name: WHITE for name in engines}
    path = []
    cycles = []

    def dfs(node):
        color[node] = GRAY
        path.append(node)
        for neighbor in engines[node].get("depends_on", []):
            if neighbor not in color:
                continue
            if color[neighbor] == GRAY:
                # Back edge found — extract cycle
                cycle_start = path.index(neighbor)
                cycle = path[cycle_start:] + [neighbor]
                cycles.append(cycle)
            elif color[neighbor] == WHITE:
                dfs(neighbor)
        path.pop()
        color[node] = BLACK

    for node in sorted(engines.keys()):
        if color[node] == WHITE:
            dfs(node)

    return cycles


# ---------------------------------------------------------------------------
# Stats computation
# ---------------------------------------------------------------------------

def compute_max_depth(engines):
    """Compute max depth of the dependency DAG (longest path from a root)."""
    memo = {}

    def depth(name):
        if name in memo:
            return memo[name]
        deps = [d for d in engines[name].get("depends_on", []) if d in engines]
        if not deps:
            memo[name] = 0
            return 0
        memo[name] = 1 + max(depth(d) for d in deps)
        return memo[name]

    if not engines:
        return 0
    return max(depth(n) for n in engines)


def compute_stats(engines):
    """Compute summary statistics for the graph."""
    edge_count = sum(len(d.get("depends_on", [])) for d in engines.values())
    return {
        "engine_count": len(engines),
        "edge_count": edge_count,
        "max_depth": compute_max_depth(engines),
        "cycles_detected": 0,
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def build_output(engines, stats):
    """Assemble the final JSON structure."""
    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator_version": GENERATOR_VERSION,
        "source": "Package.swift + overrides",
        "engines": engines,
        "stats": stats,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate engine dependency graph from Package.swift files"
    )
    parser.add_argument(
        "--packages-dir", required=True,
        help="Path to the packages directory containing AIPRD* subdirectories"
    )
    parser.add_argument(
        "--overrides", default=None,
        help="Path to engine_graph_overrides.json"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write engine_graph.json"
    )
    args = parser.parse_args(argv)

    # 1. Parse Package.swift files
    engines = build_graph(args.packages_dir)
    print(f"Parsed {len(engines)} engines from Package.swift files")

    # 2. Load & merge overrides
    overrides = load_overrides(args.overrides)
    engines = merge_overrides(engines, overrides)
    if overrides:
        print(f"Merged overrides for {len(overrides)} engines")

    # 3. Detect cycles
    cycles = detect_cycles(engines)
    if cycles:
        print("ERROR: Dependency cycles detected:", file=sys.stderr)
        for cycle in cycles:
            print(f"  Cycle: {' -> '.join(cycle)}", file=sys.stderr)
        sys.exit(1)

    # 4. Compute stats
    stats = compute_stats(engines)

    # 5. Write output
    output = build_output(engines, stats)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(f"Wrote {args.output}: "
          f"{stats['engine_count']} engines, "
          f"{stats['edge_count']} edges, "
          f"depth {stats['max_depth']}")


if __name__ == "__main__":
    main()
