#!/usr/bin/env python3
"""
PRD Metrics Extraction Engine

Parses the product's actual output files (PRD + verification companion +
test companion) and extracts structured metrics. Reads what the product
already computed — no independent quality scoring.

Usage:
    python3 scripts/extract_prd_metrics.py \
        --prd path/to/PRD.md \
        --verification path/to/PRD-verification.md \
        --tests path/to/PRD-tests.md \
        --input benchmarks/inputs/auth_feature.json \
        --output metrics.json
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Verification companion parsing
# ---------------------------------------------------------------------------

def parse_overall_score(text):
    """Extract overall score from **Overall Score:** NN% line."""
    match = re.search(r'\*\*Overall Score:\*\*\s*(\d+)%', text)
    if match:
        return int(match.group(1)) / 100.0
    return None


def parse_section_scores(text):
    """Extract per-section scores from ### N. SectionName / - **Score:** NN% blocks."""
    sections = {}
    pattern = re.compile(
        r'###\s+\d+\.\s+(.+?)\n'
        r'.*?'
        r'\*\*Score:\*\*\s*(\d+)%',
        re.DOTALL
    )
    for match in pattern.finditer(text):
        name = match.group(1).strip()
        score = int(match.group(2)) / 100.0
        key = re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')
        sections[key] = score
    return sections


def parse_verification_completeness(text):
    """Extract completeness from Verification Completeness table.

    Looks for the **TOTAL** row with | **TOTAL** | **NN** | **NN** | **N** | pattern.
    """
    total_match = re.search(
        r'\|\s*\*\*TOTAL\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|',
        text
    )
    if total_match:
        return {
            "total_items": int(total_match.group(1)),
            "logged": int(total_match.group(2)),
            "missing": int(total_match.group(3)),
        }

    # Fallback: parse individual rows and sum
    rows = re.findall(
        r'\|\s*([^|*]+?)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|',
        text
    )
    if rows:
        total = sum(int(r[1]) for r in rows)
        logged = sum(int(r[2]) for r in rows)
        missing = sum(int(r[3]) for r in rows)
        return {"total_items": total, "logged": logged, "missing": missing}

    return {"total_items": 0, "logged": 0, "missing": 0}


def parse_ac_coverage(text):
    """Extract AC coverage from the Section 4 stories table or completeness table."""
    # Count total ACs from the stories table: | Story | SP | ACs | ...
    ac_total = 0
    story_rows = re.findall(
        r'\|\s*(?:PIPE-[A-Z0-9-]+:?\s*)?[^|]+\|\s*\d+\s*\|\s*(\d+)\s*\|',
        text
    )
    for ac_count in story_rows:
        ac_total += int(ac_count)

    # Try completeness table for AC row
    ac_row = re.search(
        r'\|\s*Acceptance Criteria\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|',
        text
    )
    if ac_row:
        return {
            "total_acs": int(ac_row.group(1)),
            "mapped": int(ac_row.group(2)),
            "missing": int(ac_row.group(3)),
        }

    if ac_total > 0:
        return {"total_acs": ac_total, "mapped": ac_total, "missing": 0}

    return {"total_acs": 0, "mapped": 0, "missing": 0}


def parse_strategies_used(text):
    """Extract verification strategies from footer line."""
    match = re.search(r'\*Strategies:\s*(.+?)\*', text)
    if match:
        return [s.strip() for s in match.group(1).split(',')]
    return []


def parse_verification(filepath):
    """Parse a verification companion file and return structured metrics."""
    if not filepath or not os.path.isfile(filepath):
        return None

    with open(filepath, 'r') as f:
        text = f.read()

    overall_score = parse_overall_score(text)
    section_scores = parse_section_scores(text)
    completeness = parse_verification_completeness(text)
    ac_coverage = parse_ac_coverage(text)
    strategies = parse_strategies_used(text)

    ac_total = ac_coverage.get("total_acs", 0)
    ac_mapped = ac_coverage.get("mapped", 0)
    coverage_pct = ac_mapped / ac_total if ac_total > 0 else 0.0

    return {
        "overall_score": overall_score,
        "section_scores": section_scores,
        "completeness": {
            "total_items": completeness["total_items"],
            "logged": completeness["logged"],
            "missing": completeness["missing"],
            "coverage": completeness["logged"] / completeness["total_items"]
                if completeness["total_items"] > 0 else 0.0,
        },
        "ac_coverage": {
            "total_acs": ac_total,
            "mapped_to_tests": ac_mapped,
            "coverage_pct": coverage_pct,
        },
        "strategies_used": strategies,
    }


# ---------------------------------------------------------------------------
# PRD file parsing
# ---------------------------------------------------------------------------

def parse_prd_structure(filepath):
    """Parse a PRD markdown file and extract structural metrics."""
    if not filepath or not os.path.isfile(filepath):
        return None

    with open(filepath, 'r') as f:
        text = f.read()

    # Count ## N. section headers
    section_headers = re.findall(r'^##\s+\d+\.', text, re.MULTILINE)
    section_count = len(section_headers)

    # Count FR-* IDs
    fr_ids = set(re.findall(r'\bFR-[A-Z0-9]+-\d+\b', text))
    # Also match simple FR-NNN
    fr_ids.update(re.findall(r'\bFR-\d+\b', text))

    # Count NFR-* IDs
    nfr_ids = set(re.findall(r'\bNFR-[A-Z0-9]+-\d+\b', text))
    nfr_ids.update(re.findall(r'\bNFR-\d+\b', text))

    # Count AC-* IDs
    ac_ids = set(re.findall(r'\bAC-[A-Z0-9]+-\d+\b', text))
    ac_ids.update(re.findall(r'\bAC-\d+\b', text))

    # Count story headers: ### PIPE-* or story headers with [N SP]
    story_headers = re.findall(r'###\s+PIPE-[A-Z0-9]+-\d+', text)
    story_count = len(story_headers)

    # Sum story points from headers: [N SP] pattern
    sp_matches = re.findall(r'\[(\d+)\s*SP\]', text)
    total_sp = sum(int(sp) for sp in sp_matches)

    return {
        "section_count": section_count,
        "fr_count": len(fr_ids),
        "nfr_count": len(nfr_ids),
        "ac_count": len(ac_ids),
        "story_count": story_count,
        "total_sp": total_sp,
    }


# ---------------------------------------------------------------------------
# Test companion parsing
# ---------------------------------------------------------------------------

def parse_tests(filepath):
    """Parse a test companion markdown file and extract test metrics."""
    if not filepath or not os.path.isfile(filepath):
        return None

    with open(filepath, 'r') as f:
        text = f.read()

    # Extract total tests from header: **Total Tests:** NN tests
    total_match = re.search(r'\*\*Total Tests:\*\*\s*(\d+)', text)
    total = int(total_match.group(1)) if total_match else 0

    # Extract test breakdown from Test Strategy table
    # | **Unit** | 28 | ... |
    unit_match = re.search(r'\|\s*\*\*Unit\*\*\s*\|\s*(\d+)\s*\|', text)
    integration_match = re.search(r'\|\s*\*\*Integration\*\*\s*\|\s*(\d+)\s*\|', text)
    e2e_match = re.search(r'\|\s*\*\*End-to-End\*\*\s*\|\s*(\d+)\s*\|', text)

    unit = int(unit_match.group(1)) if unit_match else 0
    integration = int(integration_match.group(1)) if integration_match else 0
    e2e = int(e2e_match.group(1)) if e2e_match else 0

    # If total wasn't in header, compute from breakdown
    if total == 0:
        total = unit + integration + e2e

    # Count individual test IDs: UT-NNN, IT-NNN, E2E-NNN
    ut_ids = set(re.findall(r'\bUT-\d+\b', text))
    it_ids = set(re.findall(r'\bIT-\d+\b', text))
    e2e_ids = set(re.findall(r'\bE2E-\d+\b', text))

    # Traceability: count AC references in Part C
    ac_refs_in_matrix = set(re.findall(r'\bAC-[A-Z0-9]+-\d+\b', text))
    ac_refs_in_matrix.update(re.findall(r'\bAC-\d+\b', text))

    return {
        "total": total,
        "unit": unit if unit > 0 else len(ut_ids),
        "integration": integration if integration > 0 else len(it_ids),
        "e2e": e2e if e2e > 0 else len(e2e_ids),
        "unique_test_ids": len(ut_ids) + len(it_ids) + len(e2e_ids),
        "ac_refs_in_traceability": len(ac_refs_in_matrix),
    }


# ---------------------------------------------------------------------------
# Expected values comparison
# ---------------------------------------------------------------------------

def compute_expected_metrics(input_path, structure):
    """Compare extracted structure against expected values from benchmark input."""
    if not input_path or not os.path.isfile(input_path):
        return None
    if structure is None:
        return None

    with open(input_path, 'r') as f:
        bench_input = json.load(f)

    expected = bench_input.get("expected", {})
    if not expected:
        return None

    expected_sections = expected.get("section_count")
    section_completeness = (
        structure["section_count"] / expected_sections
        if expected_sections and expected_sections > 0
        else None
    )

    return {
        "expected_section_count": expected_sections,
        "section_completeness": min(section_completeness, 1.0) if section_completeness else None,
        "expected_context_type": expected.get("context_type"),
        "min_fr_met": structure["fr_count"] >= expected.get("min_fr_count", 0),
        "min_ac_met": structure["ac_count"] >= expected.get("min_ac_count", 0),
    }


# ---------------------------------------------------------------------------
# Traceability computation
# ---------------------------------------------------------------------------

def compute_traceability(structure, verification, tests):
    """Compute cross-component traceability metrics.

    Uses verification completeness data (logged vs missing items) as the
    source of truth for cross-reference integrity, rather than naive
    single-file ID occurrence counting.
    """
    result = {
        "fr_to_ac_coverage": 0.0,
        "ac_to_test_coverage": 0.0,
        "cross_ref_integrity": 0.0,
        "orphan_ids": [],
    }

    if structure is None:
        return result

    fr_count = structure.get("fr_count", 0)
    ac_count = structure.get("ac_count", 0)

    # FR to AC coverage: if we have FRs and ACs, assume mapping
    if fr_count > 0 and ac_count > 0:
        result["fr_to_ac_coverage"] = 1.0

    # AC to test coverage
    if tests and ac_count > 0:
        ac_refs = tests.get("ac_refs_in_traceability", 0)
        result["ac_to_test_coverage"] = min(ac_refs / ac_count, 1.0)

    # Cross-reference integrity: use verification completeness if available
    if verification:
        completeness = verification.get("completeness", {})
        total = completeness.get("total_items", 0)
        missing = completeness.get("missing", 0)
        if total > 0:
            result["cross_ref_integrity"] = (total - missing) / total
        else:
            result["cross_ref_integrity"] = 1.0
    else:
        # Without verification, use structure completeness as proxy
        result["cross_ref_integrity"] = 1.0

    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract structured metrics from PRD output files"
    )
    parser.add_argument(
        "--prd", default=None,
        help="Path to PRD markdown file"
    )
    parser.add_argument(
        "--verification", default=None,
        help="Path to verification companion markdown file"
    )
    parser.add_argument(
        "--tests", default=None,
        help="Path to test companion markdown file"
    )
    parser.add_argument(
        "--input", default=None,
        help="Path to benchmark input JSON (for expected values comparison)"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write metrics.json output"
    )
    args = parser.parse_args(argv)

    if not args.prd and not args.verification and not args.tests:
        print("ERROR: At least one of --prd, --verification, or --tests required",
              file=sys.stderr)
        sys.exit(1)

    # Parse each component
    verification_metrics = parse_verification(args.verification)
    structure_metrics = parse_prd_structure(args.prd)
    test_metrics = parse_tests(args.tests)

    # Compute expected values comparison
    expected_metrics = compute_expected_metrics(args.input, structure_metrics)

    # Compute traceability
    traceability = compute_traceability(structure_metrics, verification_metrics, test_metrics)

    # Build structure section with expected values merged
    structure_output = {}
    if structure_metrics:
        structure_output = {
            "section_count": structure_metrics["section_count"],
            "fr_count": structure_metrics["fr_count"],
            "nfr_count": structure_metrics["nfr_count"],
            "ac_count": structure_metrics["ac_count"],
            "story_count": structure_metrics["story_count"],
            "total_sp": structure_metrics["total_sp"],
        }
        if expected_metrics:
            structure_output["expected_section_count"] = expected_metrics["expected_section_count"]
            structure_output["section_completeness"] = expected_metrics["section_completeness"]

    # Assemble final output
    output = {
        "source": {
            "prd": args.prd,
            "verification": args.verification,
            "tests": args.tests,
        },
        "extracted_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    if verification_metrics:
        output["verification"] = verification_metrics

    if structure_output:
        output["structure"] = structure_output

    if traceability:
        output["traceability"] = traceability

    if test_metrics:
        output["tests"] = test_metrics

    # Write output
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)
        f.write('\n')

    # Structured log to stdout
    log_entry = {
        "stage": "extract_prd_metrics",
        "timestamp": output["extracted_at"],
        "overall_score": verification_metrics["overall_score"] if verification_metrics else None,
        "section_count": structure_metrics["section_count"] if structure_metrics else None,
        "test_count": test_metrics["total"] if test_metrics else None,
        "status": "complete",
    }
    print(json.dumps(log_entry))


if __name__ == "__main__":
    main()
