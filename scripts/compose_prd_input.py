#!/usr/bin/env python3
"""
PRD Input Composer (PIPE-E3-001)

Transforms pipeline artifacts into a structured markdown document that
the SKILL.md PRD generation flow can consume. Maps the TV finding through
the product's engine architecture to produce context-rich input.

Usage:
    python3 scripts/compose_prd_input.py \
        --impact-report runs/TS/impact_report_tv-001.json \
        --integration-plan runs/TS/integration_plan_tv-001.json \
        --manifest runs/TS/manifest_tv-001.json \
        --contracts-md /tmp/contracts_tv-001.md \
        --engine-graph config/engine_graph.json \
        --category-map config/category_engine_map.json \
        --output runs/TS/prd_input_tv-001.md

    # Batch mode:
    python3 scripts/compose_prd_input.py \
        --batch-dir runs/TIMESTAMP \
        --engine-graph config/engine_graph.json \
        --category-map config/category_engine_map.json
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


def load_text(path):
    """Load text file. Return empty string on failure."""
    try:
        with open(path, "r") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# Engine subgraph extraction
# ---------------------------------------------------------------------------

def build_engine_subgraph(affected_engines, engine_graph):
    """Build a human-readable engine dependency subgraph for affected engines."""
    engines_data = engine_graph.get("engines", {})
    lines = []

    for engine in affected_engines:
        info = engines_data.get(engine, {})
        if not info:
            continue

        pkg_path = info.get("package_path", "unknown")
        depends_on = info.get("depends_on", [])
        feeds = info.get("feeds", [])

        dep_str = f"depends_on: [{', '.join(depends_on)}]" if depends_on else "depends_on: []"
        line = f"{engine} ({pkg_path}) {dep_str}"
        lines.append(line)

        for target in feeds:
            lines.append(f"  -> feeds: {target}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Category resolution
# ---------------------------------------------------------------------------

def resolve_category(finding_category, category_map):
    """Resolve finding category to ports, services, and primary engines."""
    mappings = category_map.get("mappings", {})
    mapping = mappings.get(finding_category, {})
    return {
        "primary_engines": mapping.get("primary_engines", []),
        "related_ports": mapping.get("related_ports", []),
        "key_services": mapping.get("key_services", []),
    }


# ---------------------------------------------------------------------------
# Markdown composition
# ---------------------------------------------------------------------------

def compose(impact_report, integration_plan, manifest, contracts_md,
            engine_graph, category_map, architecture_description=""):
    """Compose the full PRD input markdown from pipeline artifacts."""
    finding_id = impact_report.get("finding_id", "unknown")
    finding_title = impact_report.get("finding_title",
                    impact_report.get("title", f"Upgrade {finding_id}"))
    finding_description = impact_report.get("finding_description",
                          impact_report.get("description", ""))
    finding_source = impact_report.get("source_url",
                     impact_report.get("source", ""))
    finding_category = impact_report.get("finding_category",
                       impact_report.get("category", ""))
    relevance_score = impact_report.get("relevance_score", "N/A")

    # Resolve category to product concepts
    category_info = resolve_category(finding_category, category_map)
    related_ports = category_info["related_ports"]
    key_services = category_info["key_services"]

    # Impact analysis data
    affected_engines = impact_report.get("affected_engines", [])
    compound_score = impact_report.get("compound_score", "N/A")
    recommendation = impact_report.get("recommendation", "N/A")

    # Propagation paths
    propagation_paths = impact_report.get("propagation_paths", [])
    propagation_str = ""
    for path in propagation_paths:
        from_eng = path.get("from", "")
        to_eng = path.get("to", "")
        rel = path.get("relationship", path.get("type", "depends_on"))
        propagation_str += f"{from_eng} -> {to_eng} ({rel})\n"
    if not propagation_str:
        propagation_str = "No propagation paths recorded"

    # Engine subgraph
    subgraph = build_engine_subgraph(affected_engines, engine_graph)

    # Manifest constraints
    must_change = []
    must_not_change = []
    if manifest:
        must_change = manifest.get("must_change", [])
        must_not_change = manifest.get("must_not_change", [])

    # Cross-engine touchpoints from integration plan
    touchpoints = []
    if integration_plan:
        for tp in integration_plan.get("cross_engine_touchpoints", []):
            from_eng = tp.get("from", "")
            to_eng = tp.get("to", "")
            via = tp.get("via", "")
            desc = tp.get("description", "")
            touchpoints.append(f"- {from_eng} -> {to_eng} via {via}: {desc}")

    # Contract changes from integration plan
    contract_changes = []
    if integration_plan:
        for mod in integration_plan.get("modifications", []):
            for change in mod.get("contract_changes", []):
                protocol = change.get("protocol", "")
                change_desc = change.get("description", change.get("change", ""))
                contract_changes.append(f"- {protocol} -- {change_desc}")

    # Build markdown
    sections = []

    sections.append(f"# Upgrade Specification: {finding_title}")
    sections.append("")

    # Finding Context
    sections.append("## Finding Context")
    sections.append(f"- **ID:** {finding_id}")
    sections.append(f"- **Source:** {finding_source}")
    sections.append(f"- **Category:** {finding_category} -> Primary engines: {', '.join(category_info['primary_engines'])}")
    sections.append(f"- **Relevance Score:** {relevance_score}")
    sections.append(f"- **Related Ports:** {', '.join(related_ports) if related_ports else 'None identified'}")
    sections.append(f"- **Key Services:** {', '.join(key_services) if key_services else 'None identified'}")
    sections.append(f"- **Description:** {finding_description}")
    sections.append("")

    # Impact Analysis Summary
    sections.append("## Impact Analysis Summary")
    sections.append(f"- **Engines Affected:** {', '.join(affected_engines)}")
    sections.append(f"- **Compound Score:** {compound_score}")
    sections.append(f"- **Propagation Path:**")
    for line in propagation_str.strip().split("\n"):
        sections.append(f"  {line}")
    sections.append(f"- **Recommendation:** {recommendation}")
    sections.append("")

    # Engine Dependency Subgraph
    sections.append("## Engine Dependency Subgraph")
    sections.append(subgraph)
    sections.append("")

    # Integration Constraints
    sections.append("## Integration Constraints")
    sections.append("### Files to Modify (must_change from manifest)")
    if must_change:
        for f in must_change:
            sections.append(f"- {f}")
    else:
        sections.append("- No manifest constraints available")
    sections.append("### Files NOT to Modify (must_not_change from manifest)")
    if must_not_change:
        for f in must_not_change:
            sections.append(f"- {f}")
    else:
        sections.append("- No manifest constraints available")
    sections.append("### Cross-Engine Touchpoints")
    if touchpoints:
        for tp in touchpoints:
            sections.append(tp)
    else:
        sections.append("- No cross-engine touchpoints recorded")
    sections.append("### Contract Changes")
    if contract_changes:
        for cc in contract_changes:
            sections.append(cc)
    else:
        sections.append("- No contract changes recorded")
    sections.append("")

    # Module Contracts
    sections.append("## Module Interfaces / Contracts")
    if contracts_md:
        sections.append(contracts_md)
    else:
        sections.append("No contracts extracted")
    sections.append("")

    # Product Architecture Rules (from architecture.md if available)
    sections.append("## Product Architecture Rules")
    if architecture_description:
        sections.append(architecture_description)
    else:
        sections.append("- Follow the project's CLAUDE.md and architecture documentation")
        sections.append("- Respect module boundaries and dependency graph")
        sections.append("- New capabilities extend existing interfaces")
        sections.append("- Implementations go in the relevant module")

    return "\n".join(sections)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Compose PRD input markdown from pipeline artifacts"
    )

    # Single-finding mode
    parser.add_argument(
        "--impact-report", default=None,
        help="Path to impact report JSON"
    )
    parser.add_argument(
        "--integration-plan", default=None,
        help="Path to integration plan JSON"
    )
    parser.add_argument(
        "--manifest", default=None,
        help="Path to manifest JSON"
    )
    parser.add_argument(
        "--contracts-md", default=None,
        help="Path to contracts markdown file"
    )
    parser.add_argument(
        "--output", default=None,
        help="Path to write PRD input markdown"
    )

    # Batch mode
    parser.add_argument(
        "--batch-dir", default=None,
        help="Process all accepted findings in this run directory"
    )

    # Required for both modes
    parser.add_argument(
        "--engine-graph", required=True,
        help="Path to engine_graph.json"
    )
    parser.add_argument(
        "--category-map", required=True,
        help="Path to category_engine_map.json"
    )
    parser.add_argument(
        "--architecture", default=None,
        help="Path to architecture.md (optional)"
    )

    args = parser.parse_args(argv)

    engine_graph = load_json(args.engine_graph)
    category_map = load_json(args.category_map)
    architecture_description = ""
    if args.architecture and os.path.isfile(args.architecture):
        architecture_description = load_text(args.architecture)

    if args.batch_dir:
        # Batch mode: process all accepted findings
        batch_dir = args.batch_dir
        count = 0

        for fname in sorted(os.listdir(batch_dir)):
            if not fname.startswith("validation_stage3_") or not fname.endswith(".json"):
                continue
            validation = load_json(os.path.join(batch_dir, fname))
            if validation.get("result") != "ACCEPTED":
                continue

            finding_id = validation.get("finding_id", "unknown")

            impact_path = os.path.join(batch_dir, f"impact_report_{finding_id}.json")
            plan_path = os.path.join(batch_dir, f"integration_plan_{finding_id}.json")
            manifest_path = os.path.join(batch_dir, f"manifest_{finding_id}.json")
            contracts_path = os.path.join(batch_dir, f"contracts_{finding_id}.md")

            if not os.path.isfile(impact_path):
                print(f"WARN: Impact report not found for {finding_id}, skipping",
                      file=sys.stderr)
                continue

            impact_report = load_json(impact_path)
            integration_plan = load_json(plan_path) if os.path.isfile(plan_path) else None
            manifest = load_json(manifest_path) if os.path.isfile(manifest_path) else None
            contracts_md = load_text(contracts_path)

            md = compose(impact_report, integration_plan, manifest,
                        contracts_md, engine_graph, category_map,
                        architecture_description)

            output_path = os.path.join(batch_dir, f"prd_input_{finding_id}.md")
            with open(output_path, "w") as f:
                f.write(md)
                f.write("\n")
            count += 1

        print(json.dumps({
            "stage": "compose_prd_input",
            "mode": "batch",
            "findings_composed": count,
            "status": "complete",
        }))
        return

    # Single-finding mode
    if not args.impact_report:
        print("ERROR: --impact-report required in single-finding mode",
              file=sys.stderr)
        sys.exit(1)

    if not args.output:
        print("ERROR: --output required in single-finding mode",
              file=sys.stderr)
        sys.exit(1)

    impact_report = load_json(args.impact_report)

    if not impact_report.get("affected_engines"):
        print("ERROR: Impact report has no affected_engines", file=sys.stderr)
        sys.exit(1)

    integration_plan = None
    if args.integration_plan and os.path.isfile(args.integration_plan):
        integration_plan = load_json(args.integration_plan)

    manifest = None
    if args.manifest and os.path.isfile(args.manifest):
        manifest = load_json(args.manifest)

    contracts_md = ""
    if args.contracts_md and os.path.isfile(args.contracts_md):
        contracts_md = load_text(args.contracts_md)

    md = compose(impact_report, integration_plan, manifest,
                contracts_md, engine_graph, category_map,
                architecture_description)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        f.write(md)
        f.write("\n")

    finding_id = impact_report.get("finding_id", "unknown")
    print(json.dumps({
        "stage": "compose_prd_input",
        "finding_id": finding_id,
        "affected_engines": impact_report.get("affected_engines", []),
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
