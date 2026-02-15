#!/usr/bin/env python3
"""
Technical Veil Output Adapter (PIPE-E1-001)

Transforms Technical Veil JSON output into pipeline-compatible findings.json.
Filters by relevance category and score threshold.

Usage:
    python3 scripts/parse_findings.py \
        --input tv_output.json \
        --output findings.json \
        --config config/thresholds.json \
        --threshold 0.5
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

PIPELINE_VERSION = "1.0"

DEFAULT_THRESHOLD = 0.5
DEFAULT_CATEGORIES = [
    "api_change",
    "behavior_change",
    "dependency_change",
    "config_change",
    "schema_change",
    "performance_change",
    "security_change",
    "prompting",
    "retrieval",
    "verification",
    "embeddings",
    "inference",
    "cost_optimization",
    "benchmarks",
]


# ---------------------------------------------------------------------------
# Configuration loading
# ---------------------------------------------------------------------------

def load_config(config_path):
    """Load stage_1 config from thresholds.json.

    Returns (threshold, categories) or defaults if file missing/invalid.
    """
    if not config_path:
        return DEFAULT_THRESHOLD, DEFAULT_CATEGORIES
    try:
        with open(config_path, "r") as f:
            data = json.load(f)
        stage_1 = data.get("stage_1", {})
        threshold = stage_1.get("relevance_score_minimum", DEFAULT_THRESHOLD)
        categories = stage_1.get("relevance_categories", DEFAULT_CATEGORIES)
        return threshold, categories
    except (json.JSONDecodeError, OSError):
        return DEFAULT_THRESHOLD, DEFAULT_CATEGORIES


# ---------------------------------------------------------------------------
# Input parsing
# ---------------------------------------------------------------------------

def parse_tv_input(input_path):
    """Parse Technical Veil JSON input file.

    Returns the parsed dict. Raises SystemExit on malformed JSON.
    """
    try:
        with open(input_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"ERROR: Cannot read input file: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(data, dict):
        print("ERROR: Input JSON must be an object", file=sys.stderr)
        sys.exit(1)

    return data


# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

def filter_findings(findings, threshold, valid_categories):
    """Filter findings by relevance category and score threshold.

    Returns (filtered_findings, categories_matched).
    Findings with unknown categories are rejected.
    """
    filtered = []
    categories_seen = set()

    for finding in findings:
        category = finding.get("relevance_category", "")
        score = finding.get("relevance_score", 0.0)

        if category not in valid_categories:
            continue

        if score < threshold:
            continue

        filtered.append(finding)
        categories_seen.add(category)

    return filtered, sorted(categories_seen)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def build_output(filtered_findings, total_count, threshold, categories_matched):
    """Build the findings.json output conforming to PRD section 5.2 schema."""
    return {
        "pipeline_version": PIPELINE_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "technical_veil",
        "threshold_used": threshold,
        "findings": filtered_findings,
        "stats": {
            "total_findings": total_count,
            "filtered_findings": len(filtered_findings),
            "categories_matched": categories_matched,
        },
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Transform Technical Veil output into pipeline findings.json"
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to Technical Veil JSON output file"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write findings.json"
    )
    parser.add_argument(
        "--config", default=None,
        help="Path to thresholds.json for category and threshold defaults"
    )
    parser.add_argument(
        "--threshold", type=float, default=None,
        help="Override relevance score threshold (default: from config or 0.5)"
    )
    args = parser.parse_args(argv)

    # Load config
    config_threshold, valid_categories = load_config(args.config)
    threshold = args.threshold if args.threshold is not None else config_threshold

    # Parse input
    tv_data = parse_tv_input(args.input)
    findings = tv_data.get("findings", [])
    total_count = len(findings)

    # Filter
    filtered, categories_matched = filter_findings(findings, threshold, valid_categories)

    # Build and write output
    output = build_output(filtered, total_count, threshold, categories_matched)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(json.dumps({
        "stage": "parse_findings",
        "timestamp": output["generated_at"],
        "total_findings": total_count,
        "filtered_findings": len(filtered),
        "threshold": threshold,
        "categories_matched": categories_matched,
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
