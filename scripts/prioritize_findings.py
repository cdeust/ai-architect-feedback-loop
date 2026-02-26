#!/usr/bin/env python3
"""
Finding Prioritization Script (PIPE-E2-001)

Ranks findings by likelihood of multi-engine impact and outputs the top-N
highest-value findings for Stage 2 processing.

Scoring formula:
    priority_score = (
        relevance_score * 0.2
      + category_engine_weight * 0.3
      + source_signal * 0.2
      + actor_relevance * 0.3
    )

Usage:
    python3 scripts/prioritize_findings.py \
        --findings runs/TIMESTAMP/findings.json \
        --category-map config/category_engine_map.json \
        --engine-graph config/engine_graph.json \
        --output runs/TIMESTAMP/prioritized_findings.json \
        [--top-n 20]
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

PIPELINE_VERSION = "1.0"

MAJOR_AI_LABS = {
    "anthropic", "openai", "google_deepmind", "google", "meta",
    "deepmind", "google_ai", "microsoft",
}


# ---------------------------------------------------------------------------
# Configuration loading
# ---------------------------------------------------------------------------

def load_json(path):
    """Load and return a JSON file. Exit 1 on failure."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"ERROR: Cannot load {path}: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Engine weight computation
# ---------------------------------------------------------------------------

def compute_category_engine_weights(category_map, engine_graph):
    """Compute per-category engine weight based on primary + downstream count.

    Returns dict mapping category -> float (0.0-1.0 normalized).
    """
    mappings = category_map.get("mappings", {})
    engines = engine_graph.get("engines", {})

    weights = {}
    max_count = 1  # avoid division by zero

    for category, mapping in mappings.items():
        primary = set(mapping.get("primary_engines", []))
        downstream = set()
        for engine_name in primary:
            engine_data = engines.get(engine_name, {})
            downstream.update(engine_data.get("feeds", []))
            downstream.update(engine_data.get("depended_by", []))
        total = len(primary) + len(downstream - primary)
        weights[category] = total
        if total > max_count:
            max_count = total

    # Normalize to 0-1
    for category in weights:
        weights[category] = weights[category] / max_count

    return weights


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

def _get_field(finding, key, default=""):
    """Get a field from finding, checking raw_data as fallback."""
    value = finding.get(key, "")
    if not value:
        raw = finding.get("raw_data", {})
        if isinstance(raw, dict):
            value = raw.get(key, default)
    return value if value else default


def compute_source_signal(finding):
    """Compute source signal score from finding metadata.

    post_worthy=true -> 1.0; arxiv/github -> 0.7; rss -> 0.3
    """
    post_worthy = _get_field(finding, "post_worthy", False)
    if post_worthy:
        return 1.0

    source_type = _get_field(finding, "source_type").lower()
    source_url = finding.get("source_url", "").lower()

    if source_type in ("arxiv", "github"):
        return 0.7
    if "arxiv.org" in source_url:
        return 0.7
    if "github.com" in source_url:
        return 0.7

    if source_type == "rss":
        return 0.3

    return 0.3


def compute_actor_relevance(finding):
    """Compute actor relevance score.

    Major AI labs -> 1.0; academic -> 0.5; other -> 0.3
    """
    actor = _get_field(finding, "actor").lower().replace(" ", "_").replace("-", "_")
    actor_type = _get_field(finding, "actor_type").lower()

    if actor in MAJOR_AI_LABS:
        return 1.0

    if actor_type in ("academic", "academic_research", "research"):
        return 0.5
    if actor in ("academic_research", "academic"):
        return 0.5

    # Check if source suggests academic
    source_url = finding.get("source_url", "").lower()
    if "arxiv.org" in source_url:
        return 0.5

    return 0.3


def compute_expected_engines(category, category_map, engine_graph):
    """Determine which engines a finding in this category would affect."""
    mappings = category_map.get("mappings", {})
    engines_data = engine_graph.get("engines", {})

    mapping = mappings.get(category, {})
    primary = set(mapping.get("primary_engines", []))
    all_engines = set(primary)

    for engine_name in primary:
        engine_data = engines_data.get(engine_name, {})
        all_engines.update(engine_data.get("feeds", []))
        all_engines.update(engine_data.get("depended_by", []))

    return sorted(all_engines)


def score_finding(finding, category_weights, category_map, engine_graph):
    """Compute priority score for a single finding.

    Returns (score, breakdown, expected_engines).
    """
    category = finding.get("relevance_category", "")
    relevance = finding.get("relevance_score", 0.0)
    category_weight = category_weights.get(category, 0.0)
    source_signal = compute_source_signal(finding)
    actor_relevance = compute_actor_relevance(finding)

    breakdown = {
        "relevance": round(relevance * 0.2, 4),
        "category_weight": round(category_weight * 0.3, 4),
        "source_signal": round(source_signal * 0.2, 4),
        "actor_relevance": round(actor_relevance * 0.3, 4),
    }

    score = sum(breakdown.values())
    expected_engines = compute_expected_engines(category, category_map, engine_graph)

    return round(score, 4), breakdown, expected_engines


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

def deduplicate(findings):
    """Remove duplicate findings by title, keeping highest-scored instance."""
    seen = {}
    for finding in findings:
        title = finding.get("title", "")
        if title not in seen:
            seen[title] = finding
        else:
            existing_score = seen[title].get("priority_score", 0)
            new_score = finding.get("priority_score", 0)
            if new_score > existing_score:
                seen[title] = finding
    return list(seen.values())


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def prioritize(findings, category_map, engine_graph, top_n,
               exclude_categories=None):
    """Score, deduplicate, sort, and truncate findings.

    Args:
        exclude_categories: Set of category names to skip (e.g. {"benchmarks"}).
            Benchmark findings are for Stage 12 quality tracking, not for the
            implementation loop (Stages 2-11).

    Returns list of prioritized findings.
    """
    if exclude_categories is None:
        exclude_categories = set()

    category_weights = compute_category_engine_weights(category_map, engine_graph)
    mappings = category_map.get("mappings", {})

    scored = []
    for finding in findings:
        category = finding.get("relevance_category", "")

        # Exclude findings with no engine mapping
        if category not in mappings:
            continue

        # Exclude non-actionable categories (e.g. benchmarks → Stage 8 only)
        if category in exclude_categories:
            continue

        score, breakdown, expected_engines = score_finding(
            finding, category_weights, category_map, engine_graph
        )
        enriched = dict(finding)
        enriched["priority_score"] = score
        enriched["priority_breakdown"] = breakdown
        enriched["expected_engines"] = expected_engines
        scored.append(enriched)

    # Deduplicate by title
    deduped = deduplicate(scored)

    # Sort by priority_score descending
    deduped.sort(key=lambda f: f["priority_score"], reverse=True)

    # Truncate to top-N
    return deduped[:top_n]


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Prioritize findings by multi-engine impact likelihood"
    )
    parser.add_argument(
        "--findings", required=True,
        help="Path to findings.json (Stage 1 output)"
    )
    parser.add_argument(
        "--category-map", required=True,
        help="Path to category_engine_map.json"
    )
    parser.add_argument(
        "--engine-graph", required=True,
        help="Path to engine_graph.json"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write prioritized_findings.json"
    )
    parser.add_argument(
        "--top-n", type=int, default=20,
        help="Number of top findings to emit (default: 20)"
    )
    parser.add_argument(
        "--exclude-categories", nargs="*", default=["benchmarks"],
        help="Categories to exclude from prioritization (default: benchmarks). "
             "Benchmark findings are for Stage 12 quality tracking, not for "
             "the implementation loop."
    )
    args = parser.parse_args(argv)

    # Load inputs
    findings_data = load_json(args.findings)
    category_map = load_json(args.category_map)
    engine_graph = load_json(args.engine_graph)

    findings = findings_data.get("findings", [])
    total_input = len(findings)
    exclude_set = set(args.exclude_categories) if args.exclude_categories else set()

    # Prioritize
    prioritized = prioritize(
        findings, category_map, engine_graph, args.top_n,
        exclude_categories=exclude_set,
    )

    # Build output
    output = {
        "pipeline_version": PIPELINE_VERSION,
        "prioritized_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "total_input": total_input,
        "total_output": len(prioritized),
        "findings": prioritized,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(json.dumps({
        "stage": "prioritize_findings",
        "timestamp": output["prioritized_at"],
        "total_input": total_input,
        "total_output": len(prioritized),
        "top_n": args.top_n,
        "excluded_categories": sorted(exclude_set) if exclude_set else [],
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
