#!/usr/bin/env python3
"""
Unit tests for extract_prd_metrics.py

Tests parsing of verification companion, PRD structure, and test companion
files using the product's actual dogfood output as fixtures.
"""

import json
import os
import sys
import tempfile
import unittest

# Add scripts directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract_prd_metrics import (
    parse_overall_score,
    parse_section_scores,
    parse_verification_completeness,
    parse_ac_coverage,
    parse_strategies_used,
    parse_verification,
    parse_prd_structure,
    parse_tests,
    compute_traceability,
    main,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

DOGFOOD_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "ai-architect-prd-builder", "dogfood", "pipeline-feedback"
)

VERIFICATION_FILE = os.path.join(
    DOGFOOD_DIR,
    "PRD-PipelineFeedback-Epic1-DeterministicFoundation-verification.md"
)

PRD_FILE = os.path.join(
    DOGFOOD_DIR,
    "PRD-PipelineFeedback-Epic1-DeterministicFoundation.md"
)

TESTS_FILE = os.path.join(
    DOGFOOD_DIR,
    "PRD-PipelineFeedback-Epic1-DeterministicFoundation-tests.md"
)


def has_dogfood():
    """Check if dogfood fixtures are available."""
    return os.path.isfile(VERIFICATION_FILE)


# ---------------------------------------------------------------------------
# Verification parsing tests
# ---------------------------------------------------------------------------

class TestParseOverallScore(unittest.TestCase):
    def test_parses_percentage(self):
        text = "**Overall Score:** 93%"
        self.assertEqual(parse_overall_score(text), 0.93)

    def test_parses_100_percent(self):
        text = "**Overall Score:** 100%"
        self.assertEqual(parse_overall_score(text), 1.0)

    def test_returns_none_on_missing(self):
        text = "No score here"
        self.assertIsNone(parse_overall_score(text))


class TestParseSectionScores(unittest.TestCase):
    def test_parses_sections(self):
        text = """### 1. Overview
- **Score:** 95%
- **Verified Claims:** 6

### 2. Goals & Success Metrics
- **Score:** 92%
"""
        scores = parse_section_scores(text)
        self.assertEqual(scores["overview"], 0.95)
        self.assertEqual(scores["goals_success_metrics"], 0.92)

    def test_empty_text(self):
        scores = parse_section_scores("")
        self.assertEqual(scores, {})


class TestParseVerificationCompleteness(unittest.TestCase):
    def test_parses_total_row(self):
        text = """| **TOTAL** | **88** | **88** | **0** | **ALL LOGGED** |"""
        result = parse_verification_completeness(text)
        self.assertEqual(result["total_items"], 88)
        self.assertEqual(result["logged"], 88)
        self.assertEqual(result["missing"], 0)

    def test_fallback_to_individual_rows(self):
        text = """| Functional Requirements | 26 | 26 | 0 | COMPLETE |
| Non-Functional Requirements | 8 | 8 | 0 | COMPLETE |"""
        result = parse_verification_completeness(text)
        self.assertEqual(result["total_items"], 34)
        self.assertEqual(result["logged"], 34)
        self.assertEqual(result["missing"], 0)

    def test_empty_returns_zeros(self):
        result = parse_verification_completeness("")
        self.assertEqual(result["total_items"], 0)


class TestParseACCoverage(unittest.TestCase):
    def test_parses_completeness_table(self):
        text = """| Acceptance Criteria | 35 | 35 | 0 | COMPLETE |"""
        result = parse_ac_coverage(text)
        self.assertEqual(result["total_acs"], 35)
        self.assertEqual(result["mapped"], 35)


class TestParseStrategies(unittest.TestCase):
    def test_parses_strategies_line(self):
        text = "*Strategies: Plan-and-Solve, Self-Consistency, ReAct*"
        result = parse_strategies_used(text)
        self.assertEqual(len(result), 3)
        self.assertIn("Plan-and-Solve", result)
        self.assertIn("ReAct", result)


# ---------------------------------------------------------------------------
# Full file parsing tests (require dogfood fixtures)
# ---------------------------------------------------------------------------

@unittest.skipUnless(has_dogfood(), "Dogfood fixtures not available")
class TestParseVerificationFile(unittest.TestCase):
    def test_overall_score_is_93(self):
        result = parse_verification(VERIFICATION_FILE)
        self.assertIsNotNone(result)
        self.assertEqual(result["overall_score"], 0.93)

    def test_has_6_section_scores(self):
        result = parse_verification(VERIFICATION_FILE)
        self.assertEqual(len(result["section_scores"]), 6)

    def test_completeness_88_items(self):
        result = parse_verification(VERIFICATION_FILE)
        self.assertEqual(result["completeness"]["total_items"], 88)
        self.assertEqual(result["completeness"]["logged"], 88)
        self.assertEqual(result["completeness"]["missing"], 0)
        self.assertEqual(result["completeness"]["coverage"], 1.0)

    def test_ac_coverage_35(self):
        result = parse_verification(VERIFICATION_FILE)
        self.assertEqual(result["ac_coverage"]["total_acs"], 35)
        self.assertEqual(result["ac_coverage"]["coverage_pct"], 1.0)

    def test_strategies_count(self):
        result = parse_verification(VERIFICATION_FILE)
        self.assertGreaterEqual(len(result["strategies_used"]), 5)


@unittest.skipUnless(has_dogfood(), "Dogfood fixtures not available")
class TestParsePRDFile(unittest.TestCase):
    def test_section_count_is_8(self):
        result = parse_prd_structure(PRD_FILE)
        self.assertIsNotNone(result)
        self.assertEqual(result["section_count"], 8)

    def test_has_frs(self):
        result = parse_prd_structure(PRD_FILE)
        self.assertGreaterEqual(result["fr_count"], 20)

    def test_has_nfrs(self):
        result = parse_prd_structure(PRD_FILE)
        self.assertEqual(result["nfr_count"], 8)

    def test_has_stories(self):
        result = parse_prd_structure(PRD_FILE)
        self.assertEqual(result["story_count"], 10)

    def test_has_acs(self):
        result = parse_prd_structure(PRD_FILE)
        self.assertEqual(result["ac_count"], 35)


@unittest.skipUnless(has_dogfood(), "Dogfood fixtures not available")
class TestParseTestFile(unittest.TestCase):
    def test_total_tests_52(self):
        result = parse_tests(TESTS_FILE)
        self.assertIsNotNone(result)
        self.assertEqual(result["total"], 52)

    def test_unit_tests_28(self):
        result = parse_tests(TESTS_FILE)
        self.assertEqual(result["unit"], 28)

    def test_integration_tests_18(self):
        result = parse_tests(TESTS_FILE)
        self.assertEqual(result["integration"], 18)

    def test_e2e_tests_6(self):
        result = parse_tests(TESTS_FILE)
        self.assertEqual(result["e2e"], 6)

    def test_ac_traceability(self):
        result = parse_tests(TESTS_FILE)
        self.assertEqual(result["ac_refs_in_traceability"], 35)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases(unittest.TestCase):
    def test_missing_verification_file(self):
        result = parse_verification("/nonexistent/path.md")
        self.assertIsNone(result)

    def test_missing_prd_file(self):
        result = parse_prd_structure("/nonexistent/path.md")
        self.assertIsNone(result)

    def test_missing_tests_file(self):
        result = parse_tests("/nonexistent/path.md")
        self.assertIsNone(result)

    def test_empty_prd(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
            f.write("")
            f.flush()
            result = parse_prd_structure(f.name)
            self.assertEqual(result["section_count"], 0)
            self.assertEqual(result["fr_count"], 0)
            os.unlink(f.name)

    def test_empty_verification(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
            f.write("")
            f.flush()
            result = parse_verification(f.name)
            self.assertIsNone(result["overall_score"])
            os.unlink(f.name)


# ---------------------------------------------------------------------------
# Traceability tests
# ---------------------------------------------------------------------------

class TestComputeTraceability(unittest.TestCase):
    def test_full_traceability(self):
        structure = {"fr_count": 10, "nfr_count": 5, "ac_count": 20}
        verification = {
            "completeness": {"total_items": 50, "logged": 50, "missing": 0}
        }
        tests = {"ac_refs_in_traceability": 20}
        result = compute_traceability(structure, verification, tests)
        self.assertEqual(result["fr_to_ac_coverage"], 1.0)
        self.assertEqual(result["ac_to_test_coverage"], 1.0)
        self.assertEqual(result["cross_ref_integrity"], 1.0)

    def test_partial_test_coverage(self):
        structure = {"fr_count": 10, "nfr_count": 5, "ac_count": 20}
        verification = {
            "completeness": {"total_items": 50, "logged": 45, "missing": 5}
        }
        tests = {"ac_refs_in_traceability": 10}
        result = compute_traceability(structure, verification, tests)
        self.assertEqual(result["ac_to_test_coverage"], 0.5)
        self.assertEqual(result["cross_ref_integrity"], 0.9)

    def test_no_structure(self):
        result = compute_traceability(None, None, None)
        self.assertEqual(result["fr_to_ac_coverage"], 0.0)


# ---------------------------------------------------------------------------
# CLI integration test
# ---------------------------------------------------------------------------

@unittest.skipUnless(has_dogfood(), "Dogfood fixtures not available")
class TestCLI(unittest.TestCase):
    def test_full_extraction(self):
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            output_path = f.name

        try:
            main([
                "--prd", PRD_FILE,
                "--verification", VERIFICATION_FILE,
                "--tests", TESTS_FILE,
                "--output", output_path,
            ])

            with open(output_path) as f:
                result = json.load(f)

            self.assertEqual(result["verification"]["overall_score"], 0.93)
            self.assertEqual(result["structure"]["section_count"], 8)
            self.assertEqual(result["tests"]["total"], 52)
            self.assertEqual(result["traceability"]["cross_ref_integrity"], 1.0)
        finally:
            os.unlink(output_path)


if __name__ == "__main__":
    unittest.main()
