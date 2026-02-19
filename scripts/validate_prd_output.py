#!/usr/bin/env python3
"""
Stage 4 PRD Output Validator (PIPE-E3-004)

Deterministic structural validation of PRD output files. Validates against
the product's actual PRD format (feature context = 11 sections) and engine
architecture.

Validation rules:
  1. Four files exist (prd.md, prd-verification.md, prd-jira.md, prd-tests.md)
  2. PRD section count (>= 7 ## N. headers)
  3. FR count (>= 3 FR-XXX IDs)
  4. AC count (>= 3 AC-XXX IDs)
  5. Story points (total SP > 0)
  6. Verification score exists and is numeric
  7. Quality threshold (>= config threshold)
  8. Engine references (PRD mentions affected engines)
  9. Test file non-empty (>= 1 test ID)
  10. Architecture references in tech spec

Usage:
    python3 scripts/validate_prd_output.py \
        --prd-dir prd_output_tv-001/ \
        --integration-plan integration_plan_tv-001.json \
        --engine-graph config/engine_graph.json \
        --metrics metrics_tv-001.json \
        --config config/thresholds.json \
        --output validation_stage4_tv-001.json
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_json(path):
    """Load JSON file. Return None on failure."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def load_text(path):
    """Load text file. Return empty string on failure."""
    try:
        with open(path, "r") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------------

EXPECTED_FILES = ["prd.md", "prd-verification.md", "prd-jira.md", "prd-tests.md"]


def check_four_files_exist(prd_dir):
    """Rule 1: All four PRD output files must exist."""
    missing = []
    for fname in EXPECTED_FILES:
        path = os.path.join(prd_dir, fname)
        if not os.path.isfile(path):
            missing.append(fname)
    if missing:
        return {"check": "four_files_exist", "result": "FAIL",
                "reason": f"Missing files: {', '.join(missing)}"}
    return {"check": "four_files_exist", "result": "PASS"}


def check_section_count(prd_dir):
    """Rule 2: PRD must have >= 7 ## N. section headers."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    if not prd_text:
        return {"check": "section_count", "result": "FAIL",
                "reason": "prd.md is empty or missing"}
    headers = re.findall(r'^##\s+\d+\.', prd_text, re.MULTILINE)
    count = len(headers)
    if count < 7:
        return {"check": "section_count", "result": "FAIL",
                "reason": f"Only {count} section headers (need >= 7)"}
    return {"check": "section_count", "result": "PASS",
            "reason": f"{count} sections found"}


def check_fr_count(prd_dir):
    """Rule 3: PRD must have >= 3 FR IDs."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    fr_ids = set(re.findall(r'\bFR-[A-Z0-9]+-\d+\b', prd_text))
    fr_ids.update(re.findall(r'\bFR-\d+\b', prd_text))
    count = len(fr_ids)
    if count < 3:
        return {"check": "fr_count", "result": "FAIL",
                "reason": f"Only {count} FR IDs (need >= 3)"}
    return {"check": "fr_count", "result": "PASS",
            "reason": f"{count} FR IDs found"}


def check_ac_count(prd_dir):
    """Rule 4: PRD must have >= 3 AC IDs."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    ac_ids = set(re.findall(r'\bAC-[A-Z0-9]+-\d+\b', prd_text))
    ac_ids.update(re.findall(r'\bAC-\d+\b', prd_text))
    count = len(ac_ids)
    if count < 3:
        return {"check": "ac_count", "result": "FAIL",
                "reason": f"Only {count} AC IDs (need >= 3)"}
    return {"check": "ac_count", "result": "PASS",
            "reason": f"{count} AC IDs found"}


def check_story_points(prd_dir):
    """Rule 5: Total story points must be > 0."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    sp_matches = re.findall(r'\[(\d+)\s*SP\]', prd_text)
    total_sp = sum(int(sp) for sp in sp_matches)
    if total_sp <= 0:
        return {"check": "story_points", "result": "FAIL",
                "reason": "Total SP = 0 (SKILL.md Rule 1 violation)"}
    return {"check": "story_points", "result": "PASS",
            "reason": f"Total SP = {total_sp}"}


def check_verification_score_exists(metrics):
    """Rule 6: Verification overall_score must exist and be numeric."""
    if metrics is None:
        return {"check": "verification_score_exists", "result": "FAIL",
                "reason": "Metrics file not found or invalid"}
    verification = metrics.get("verification")
    if verification is None:
        return {"check": "verification_score_exists", "result": "FAIL",
                "reason": "No verification section in metrics"}
    score = verification.get("overall_score")
    if score is None or not isinstance(score, (int, float)):
        return {"check": "verification_score_exists", "result": "FAIL",
                "reason": "overall_score missing or non-numeric"}
    return {"check": "verification_score_exists", "result": "PASS",
            "reason": f"overall_score = {score}"}


def check_quality_threshold(metrics, threshold):
    """Rule 7: overall_score >= threshold."""
    if metrics is None:
        return {"check": "quality_threshold", "result": "FAIL",
                "reason": "Metrics not available"}
    verification = metrics.get("verification", {})
    score = verification.get("overall_score")
    if score is None:
        return {"check": "quality_threshold", "result": "FAIL",
                "reason": "No overall_score"}
    if score < threshold:
        return {"check": "quality_threshold", "result": "FAIL",
                "reason": f"Score {score:.2f} < threshold {threshold:.2f}"}
    return {"check": "quality_threshold", "result": "PASS",
            "reason": f"Score {score:.2f} >= threshold {threshold:.2f}"}


def check_engine_references(prd_dir, affected_engines, engine_graph):
    """Rule 8: PRD body mentions >= 1 engine from affected list."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    if not prd_text:
        return {"check": "engine_references", "result": "FAIL",
                "reason": "prd.md is empty or missing"}

    # Use exact engine names from engine_graph keys
    valid_names = set(engine_graph.get("engines", {}).keys())
    found = []
    for engine in affected_engines:
        if engine in valid_names and engine in prd_text:
            found.append(engine)

    if not found:
        return {"check": "engine_references", "result": "FAIL",
                "reason": f"No engine references found (expected: {', '.join(affected_engines)})"}
    return {"check": "engine_references", "result": "PASS",
            "reason": f"Found: {', '.join(found)}"}


def check_test_ids(prd_dir):
    """Rule 9: Tests companion must have >= 1 test ID (UT-/IT-/E2E- prefix)."""
    test_text = load_text(os.path.join(prd_dir, "prd-tests.md"))
    if not test_text:
        return {"check": "test_ids", "result": "FAIL",
                "reason": "prd-tests.md is empty or missing"}
    ut_ids = set(re.findall(r'\bUT-\d+\b', test_text))
    it_ids = set(re.findall(r'\bIT-\d+\b', test_text))
    e2e_ids = set(re.findall(r'\bE2E-\d+\b', test_text))
    total = len(ut_ids) + len(it_ids) + len(e2e_ids)
    if total < 1:
        return {"check": "test_ids", "result": "FAIL",
                "reason": "No UT-/IT-/E2E- test IDs found (SKILL.md Rule 7)"}
    return {"check": "test_ids", "result": "PASS",
            "reason": f"{total} test IDs found"}


def check_architecture_in_tech_spec(prd_dir):
    """Rule 10: Technical Spec section mentions architecture terms."""
    prd_text = load_text(os.path.join(prd_dir, "prd.md"))
    if not prd_text:
        return {"check": "architecture_in_tech_spec", "result": "FAIL",
                "reason": "prd.md is empty or missing"}

    # Find the Technical Spec section (usually section 5 or 6)
    tech_spec_match = re.search(
        r'##\s+\d+\.\s+Technical\s+Spec.*?\n(.*?)(?=\n##\s+\d+\.|\Z)',
        prd_text,
        re.DOTALL | re.IGNORECASE
    )

    if not tech_spec_match:
        # Fallback: check entire document
        text_to_check = prd_text
    else:
        text_to_check = tech_spec_match.group(1)

    # Check for any common architecture terms (not just port/adapter)
    terms = ["module", "interface", "service", "component", "layer",
             "port", "adapter", "protocol", "api", "contract"]
    found = [t for t in terms if t.lower() in text_to_check.lower()]

    if not found:
        return {"check": "architecture_in_tech_spec", "result": "FAIL",
                "reason": "Technical Spec missing architecture references"}
    return {"check": "architecture_in_tech_spec", "result": "PASS",
            "reason": f"Found: {', '.join(found[:5])}"}


# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

def validate(prd_dir, integration_plan, engine_graph, metrics, config):
    """Run all validation checks. Returns (result, checks, finding_id)."""
    threshold = config.get("stage_4", {}).get("prd_quality_minimum", 0.85)
    affected_engines = integration_plan.get("affected_engines", []) if integration_plan else []
    finding_id = integration_plan.get("finding_id", "unknown") if integration_plan else "unknown"

    checks = [
        check_four_files_exist(prd_dir),
        check_section_count(prd_dir),
        check_fr_count(prd_dir),
        check_ac_count(prd_dir),
        check_story_points(prd_dir),
        check_verification_score_exists(metrics),
        check_quality_threshold(metrics, threshold),
        check_engine_references(prd_dir, affected_engines, engine_graph),
        check_test_ids(prd_dir),
        check_architecture_in_tech_spec(prd_dir),
    ]

    failures = [c for c in checks if c["result"] == "FAIL"]
    result = "REJECTED" if failures else "ACCEPTED"

    return result, checks, finding_id


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate Stage 4 PRD output against product constraints"
    )
    parser.add_argument(
        "--prd-dir", required=True,
        help="Directory containing the 4 PRD output files"
    )
    parser.add_argument(
        "--integration-plan", required=True,
        help="Path to integration plan JSON"
    )
    parser.add_argument(
        "--engine-graph", required=True,
        help="Path to engine_graph.json"
    )
    parser.add_argument(
        "--metrics", required=True,
        help="Path to metrics JSON from extract_prd_metrics.py"
    )
    parser.add_argument(
        "--config", required=True,
        help="Path to thresholds.json"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write validation result JSON"
    )
    args = parser.parse_args(argv)

    integration_plan = load_json(args.integration_plan)
    if integration_plan is None:
        print("ERROR: Cannot load integration plan", file=sys.stderr)
        sys.exit(1)

    engine_graph = load_json(args.engine_graph)
    if engine_graph is None:
        print("ERROR: Cannot load engine graph", file=sys.stderr)
        sys.exit(1)

    metrics = load_json(args.metrics)
    config = load_json(args.config)
    if config is None:
        config = {"stage_4": {"prd_quality_minimum": 0.85}}

    result, checks, finding_id = validate(
        args.prd_dir, integration_plan, engine_graph, metrics, config
    )

    output = {
        "stage": "validate_prd_output",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "finding_id": finding_id,
        "result": result,
        "checks": checks,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(json.dumps({
        "stage": "validate_prd_output",
        "finding_id": finding_id,
        "result": result,
        "checks_passed": sum(1 for c in checks if c["result"] == "PASS"),
        "checks_failed": sum(1 for c in checks if c["result"] == "FAIL"),
        "status": "complete",
    }))

    if result == "REJECTED":
        sys.exit(1)


if __name__ == "__main__":
    main()
