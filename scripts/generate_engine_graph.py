#!/usr/bin/env python3
"""
Engine Dependency Graph Generator (PIPE-E1-003)

Language-aware dependency graph generator. Parses dependency manifests
(Package.swift, pyproject.toml, package.json, go.mod), merges manual
overrides, detects cycles, and writes engine_graph.json.

Usage:
    python3 scripts/generate_engine_graph.py \
        --packages-dir /path/to/target-product/packages \
        --overrides config/engine_graph_overrides.json \
        --output config/engine_graph.json \
        [--project-config config/project.json]
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

GENERATOR_VERSION = "2.0"


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_project_config(config_path):
    """Load project.json configuration."""
    defaults = {
        "language": "python",
        "module_prefix": "",
        "modules_dir": "packages",
    }
    if config_path and os.path.isfile(config_path):
        with open(config_path, "r") as f:
            user = json.load(f)
        defaults.update(user)
    return defaults


# ---------------------------------------------------------------------------
# Language-specific dependency detection
# ---------------------------------------------------------------------------

def discover_packages_generic(packages_dir, module_prefix=""):
    """Find all module directories under packages_dir."""
    if module_prefix:
        pattern = os.path.join(packages_dir, f"{module_prefix}*")
    else:
        pattern = os.path.join(packages_dir, "*")

    dirs = []
    for d in sorted(glob.glob(pattern)):
        if os.path.isdir(d):
            name = os.path.basename(d)
            if not name.startswith('.') and name not in ('node_modules', '__pycache__', '.build'):
                dirs.append(d)
    return dirs


def parse_swift_package(filepath, module_prefix):
    """Extract package name and local dependencies from Package.swift."""
    with open(filepath, "r") as f:
        content = f.read()

    name_pattern = r'name:\s*"([^"]+)"'
    name_match = re.search(name_pattern, content)
    if not name_match:
        return None, []
    package_name = name_match.group(1)

    local_deps = re.findall(r'\.package\(\s*path:\s*"[^"]*?([^"/]+)"\s*\)', content)
    return package_name, local_deps


def parse_python_deps(pkg_dir, module_prefix):
    """Extract dependencies from pyproject.toml or setup.py."""
    deps = []
    pyproject = os.path.join(pkg_dir, "pyproject.toml")
    if os.path.isfile(pyproject):
        with open(pyproject, "r") as f:
            content = f.read()
        # Simple TOML parsing for dependencies
        for match in re.finditer(r'"([^"]+)"', content):
            dep = match.group(1)
            if module_prefix and dep.startswith(module_prefix):
                deps.append(dep)
    return deps


def parse_node_deps(pkg_dir, module_prefix):
    """Extract dependencies from package.json."""
    deps = []
    pkg_json = os.path.join(pkg_dir, "package.json")
    if os.path.isfile(pkg_json):
        with open(pkg_json, "r") as f:
            data = json.load(f)
        all_deps = {}
        all_deps.update(data.get("dependencies", {}))
        all_deps.update(data.get("devDependencies", {}))
        for dep_name in all_deps:
            if module_prefix and dep_name.startswith(module_prefix):
                deps.append(dep_name)
    return deps


def parse_go_deps(pkg_dir, module_prefix):
    """Extract dependencies from go.mod."""
    deps = []
    go_mod = os.path.join(pkg_dir, "go.mod")
    if os.path.isfile(go_mod):
        with open(go_mod, "r") as f:
            content = f.read()
        for match in re.finditer(r'require\s+(\S+)', content):
            dep = match.group(1)
            if module_prefix and module_prefix in dep:
                deps.append(dep.split('/')[-1])
    return deps


LANG_PARSERS = {
    "swift": "package_swift",
    "python": "pyproject",
    "typescript": "package_json",
    "go": "go_mod",
}


def strip_prefix(full_name, prefix):
    """Remove module prefix from name."""
    if prefix and full_name.startswith(prefix):
        return full_name[len(prefix):]
    return full_name


# ---------------------------------------------------------------------------
# Graph construction
# ---------------------------------------------------------------------------

def build_graph(packages_dir, language="python", module_prefix=""):
    """Parse dependency manifests and return adjacency data."""
    pkg_dirs = discover_packages_generic(packages_dir, module_prefix)

    if not pkg_dirs:
        # No packages found — return empty graph (overrides will populate it)
        return {}

    engines = {}

    for pkg_dir in pkg_dirs:
        full_name = os.path.basename(pkg_dir)
        short = strip_prefix(full_name, module_prefix)
        rel_path = os.path.relpath(pkg_dir, os.path.dirname(packages_dir))

        deps = []

        if language == "swift":
            pkg_swift = os.path.join(pkg_dir, "Package.swift")
            if os.path.isfile(pkg_swift):
                parsed_name, raw_deps = parse_swift_package(pkg_swift, module_prefix)
                deps = sorted(strip_prefix(d, module_prefix) for d in raw_deps)
        elif language == "python":
            raw_deps = parse_python_deps(pkg_dir, module_prefix)
            deps = sorted(strip_prefix(d, module_prefix) for d in raw_deps)
        elif language == "typescript":
            raw_deps = parse_node_deps(pkg_dir, module_prefix)
            deps = sorted(strip_prefix(d, module_prefix) for d in raw_deps)
        elif language == "go":
            raw_deps = parse_go_deps(pkg_dir, module_prefix)
            deps = sorted(strip_prefix(d, module_prefix) for d in raw_deps)

        engines[short] = {
            "package_path": rel_path,
            "depends_on": deps,
            "depended_by": [],
        }

    # Populate depended_by (reverse edges)
    for name, data in engines.items():
        for dep in data["depends_on"]:
            if dep in engines:
                engines[dep]["depended_by"].append(name)

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
    """Deep-merge override fields into engines."""
    for name, override_data in overrides.items():
        if name not in engines:
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

    for data in engines.values():
        data.setdefault("feeds", [])
        data.setdefault("fed_by", [])
        data.setdefault("role", "")

    return engines


# ---------------------------------------------------------------------------
# Cycle detection
# ---------------------------------------------------------------------------

def detect_cycles(engines):
    """DFS-based cycle detection on depends_on edges."""
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
    """Compute max depth of the dependency DAG."""
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

def build_output(engines, stats, language):
    """Assemble the final JSON structure."""
    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator_version": GENERATOR_VERSION,
        "source": f"{language} manifests + overrides",
        "engines": engines,
        "stats": stats,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate engine dependency graph from project manifests"
    )
    parser.add_argument(
        "--packages-dir", required=True,
        help="Path to the modules directory"
    )
    parser.add_argument(
        "--overrides", default=None,
        help="Path to engine_graph_overrides.json"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write engine_graph.json"
    )
    parser.add_argument(
        "--project-config", default=None,
        help="Path to project.json (optional)"
    )
    args = parser.parse_args(argv)

    # Load project config
    config = load_project_config(args.project_config)
    language = config.get("language", "python")
    module_prefix = config.get("module_prefix", "")

    # 1. Parse dependency manifests
    engines = build_graph(args.packages_dir, language, module_prefix)
    print(f"Parsed {len(engines)} modules from {language} manifests")

    # 2. Load & merge overrides
    overrides = load_overrides(args.overrides)
    engines = merge_overrides(engines, overrides)
    if overrides:
        print(f"Merged overrides for {len(overrides)} modules")

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
    output = build_output(engines, stats, language)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(f"Wrote {args.output}: "
          f"{stats['engine_count']} modules, "
          f"{stats['edge_count']} edges, "
          f"depth {stats['max_depth']}")


if __name__ == "__main__":
    main()
