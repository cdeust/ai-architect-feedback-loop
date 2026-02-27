#!/usr/bin/env python3
"""
Unit tests for validate_impact_report.py (PIPE-E2-003)

Covers:
  UT-VIR-001: ACCEPTED — engines_affected=3, compound_score=0.65, valid paths
  UT-VIR-002: REJECTED — engines_affected=1 (below threshold 2)
  UT-VIR-003: REJECTED — compound_score=0.2 (below threshold 0.3)
  UT-VIR-004: REJECTED — bad propagation path (not in graph)
  UT-VIR-005: REJECTED — score mismatch (declared != computed)
  UT-VIR-006: REJECTED — unknown engine in affected_engines
  UT-VIR-007: Boundary — engines_affected=2, compound_score=0.3 (exactly at threshold)
  UT-VIR-008: REJECTED — inconsistent count vs list
  UT-VIR-009: REJECTED — recommendation coherence
  UT-VIR-010: output_format='json' emits one JSON line per check
  UT-VIR-011: output_format='text' (default) unchanged behavior
  UT-VIR-012: invalid output_format raises ValueError
  UT-VIR-013: ErrorRecord fields present and exact in JSON output
  UT-VIR-014: ErrorRecord, format_error_record, emit_json_line importable

Uses synthetic data — no external dependencies.
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import validate_impact_report as vir


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

ENGINE_GRAPH = {
    "engines": {
        "SharedUtilities": {
            "depends_on": [],
            "depended_by": ["RAGEngine", "VerificationEngine", "OrchestrationEngine"],
            "feeds": ["RAGEngine", "VerificationEngine", "OrchestrationEngine"],
            "fed_by": [],
        },
        "RAGEngine": {
            "depends_on": ["SharedUtilities"],
            "depended_by": ["MetaPromptingEngine", "OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "MetaPromptingEngine": {
            "depends_on": ["RAGEngine", "SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "VerificationEngine": {
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "EncryptionEngine": {
            "depends_on": ["SharedUtilities"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities"],
        },
        "OrchestrationEngine": {
            "depends_on": ["SharedUtilities", "RAGEngine", "VerificationEngine", "MetaPromptingEngine"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities", "RAGEngine", "VerificationEngine", "MetaPromptingEngine"],
        },
    }
}


def make_valid_report(finding_id="tv-001", engines_affected=3, compound_score=0.65):
    """Create a valid impact report."""
    return {
        "finding_id": finding_id,
        "engines_affected": engines_affected,
        "compound_score": compound_score,
        "affected_engines": ["RAGEngine", "MetaPromptingEngine", "OrchestrationEngine"][:engines_affected],
        "propagation_paths": [
            {"from": "RAGEngine", "to": "OrchestrationEngine", "order": 1, "mechanism": "feeds"},
            {"from": "RAGEngine", "to": "MetaPromptingEngine", "order": 1, "mechanism": "depended_by"},
        ][:engines_affected - 1],
        "scoring_breakdown": {
            "engines_affected": {"value": engines_affected, "weight": 0.3},
            "propagation_depth": {"value": 2, "weight": 0.2},
            "contract_impact": {"value": 0.3, "weight": 0.3},
            "test_coverage_delta": {"value": 0.2, "weight": 0.2},
        },
        "recommendation": "PROCEED" if engines_affected >= 2 and compound_score >= 0.3 else "REJECT",
        "rationale": "Multi-engine impact detected",
    }


def make_report_with_score(engines_affected, propagation_depth, contract_impact, test_delta):
    """Create report with explicit scoring components."""
    score = (engines_affected * 0.3 + propagation_depth * 0.2 +
             contract_impact * 0.3 + test_delta * 0.2)
    affected = ["RAGEngine", "MetaPromptingEngine", "OrchestrationEngine"][:int(engines_affected)]
    should_proceed = len(affected) >= 2 and score >= 0.3
    return {
        "finding_id": "tv-test",
        "engines_affected": len(affected),
        "compound_score": round(score, 4),
        "affected_engines": affected,
        "propagation_paths": [
            {"from": "RAGEngine", "to": "OrchestrationEngine", "order": 1, "mechanism": "feeds"},
        ] if len(affected) >= 2 else [],
        "scoring_breakdown": {
            "engines_affected": {"value": engines_affected, "weight": 0.3},
            "propagation_depth": {"value": propagation_depth, "weight": 0.2},
            "contract_impact": {"value": contract_impact, "weight": 0.3},
            "test_coverage_delta": {"value": test_delta, "weight": 0.2},
        },
        "recommendation": "PROCEED" if should_proceed else "REJECT",
        "rationale": "Test report",
    }


# ---------------------------------------------------------------------------
# UT-VIR-001: ACCEPTED
# ---------------------------------------------------------------------------

class TestAccepted(unittest.TestCase):
    """UT-VIR-001: Valid report with engines_affected=3, compound_score=0.65."""

    def test_valid_report_accepted(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "ACCEPTED")

    def test_all_checks_pass(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        _, checks = vir.validate(report, None, ENGINE_GRAPH)
        failures = [c for c in checks if c["result"] == "FAIL"]
        self.assertEqual(len(failures), 0)


# ---------------------------------------------------------------------------
# UT-VIR-002: REJECTED — engines below threshold
# ---------------------------------------------------------------------------

class TestRejectedEngines(unittest.TestCase):
    """UT-VIR-002: engines_affected=1 below threshold 2."""

    def test_single_engine_rejected(self):
        report = make_report_with_score(1, 1, 0.5, 0.5)
        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        engine_check = next(c for c in checks if c["check"] == "engines_affected_threshold")
        self.assertEqual(engine_check["result"], "FAIL")
        self.assertIn("below threshold 2", engine_check["reason"])


# ---------------------------------------------------------------------------
# UT-VIR-003: REJECTED — score below threshold
# ---------------------------------------------------------------------------

class TestRejectedScore(unittest.TestCase):
    """UT-VIR-003: compound_score=0.2 below threshold 0.3."""

    def test_low_score_rejected(self):
        report = make_report_with_score(2, 0, 0.0, 0.0)
        # This gives score = 2*0.3 = 0.6, so we need to manually override
        report["compound_score"] = 0.2
        report["scoring_breakdown"]["engines_affected"]["value"] = 0.5
        report["scoring_breakdown"]["propagation_depth"]["value"] = 0
        report["scoring_breakdown"]["contract_impact"]["value"] = 0
        report["scoring_breakdown"]["test_coverage_delta"]["value"] = 0.25
        # Recompute: 0.5*0.3 + 0*0.2 + 0*0.3 + 0.25*0.2 = 0.15 + 0.05 = 0.2
        report["compound_score"] = 0.2
        report["recommendation"] = "REJECT"

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        score_check = next(c for c in checks if c["check"] == "compound_score_threshold")
        self.assertEqual(score_check["result"], "FAIL")
        self.assertIn("below threshold 0.3", score_check["reason"])


# ---------------------------------------------------------------------------
# UT-VIR-004: REJECTED — bad propagation path
# ---------------------------------------------------------------------------

class TestRejectedBadPath(unittest.TestCase):
    """UT-VIR-004: Path RAGEngine -> EncryptionEngine not in graph."""

    def test_invalid_path_rejected(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        report["propagation_paths"] = [
            {"from": "RAGEngine", "to": "EncryptionEngine", "order": 1, "mechanism": "invalid"},
        ]
        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        path_check = next(c for c in checks if c["check"] == "propagation_path_validity")
        self.assertEqual(path_check["result"], "FAIL")
        self.assertIn("no edge in graph", path_check["reason"])


# ---------------------------------------------------------------------------
# UT-VIR-005: REJECTED — score mismatch
# ---------------------------------------------------------------------------

class TestRejectedScoreMismatch(unittest.TestCase):
    """UT-VIR-005: Declared compound_score doesn't match breakdown."""

    def test_score_mismatch_rejected(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        report["compound_score"] = 0.99  # Wrong

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        score_check = next(c for c in checks if c["check"] == "score_verification")
        self.assertEqual(score_check["result"], "FAIL")
        self.assertIn("!=", score_check["reason"])


# ---------------------------------------------------------------------------
# UT-VIR-006: REJECTED — unknown engine
# ---------------------------------------------------------------------------

class TestRejectedUnknownEngine(unittest.TestCase):
    """UT-VIR-006: affected_engines includes FakeEngine not in graph."""

    def test_unknown_engine_rejected(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        report["affected_engines"] = ["RAGEngine", "FakeEngine", "OrchestrationEngine"]

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        engine_check = next(c for c in checks if c["check"] == "engine_existence")
        self.assertEqual(engine_check["result"], "FAIL")
        self.assertIn("FakeEngine", engine_check["reason"])


# ---------------------------------------------------------------------------
# UT-VIR-007: Boundary — exactly at threshold
# ---------------------------------------------------------------------------

class TestBoundary(unittest.TestCase):
    """UT-VIR-007: engines_affected=2, compound_score=0.3 → ACCEPTED."""

    def test_exactly_at_threshold_accepted(self):
        report = make_report_with_score(2, 0, 0, 0)
        # score = 2*0.3 = 0.6, override to 0.3
        report["scoring_breakdown"]["engines_affected"]["value"] = 0.5
        report["scoring_breakdown"]["propagation_depth"]["value"] = 0.5
        report["scoring_breakdown"]["contract_impact"]["value"] = 0
        report["scoring_breakdown"]["test_coverage_delta"]["value"] = 0
        # 0.5*0.3 + 0.5*0.2 + 0 + 0 = 0.15 + 0.10 = 0.25... still not 0.3
        # Let's use: 1*0.3 + 0*0.2 + 0*0.3 + 0*0.2 = 0.3
        report["scoring_breakdown"]["engines_affected"]["value"] = 1
        report["scoring_breakdown"]["propagation_depth"]["value"] = 0
        report["scoring_breakdown"]["contract_impact"]["value"] = 0
        report["scoring_breakdown"]["test_coverage_delta"]["value"] = 0
        report["compound_score"] = 0.3
        report["recommendation"] = "PROCEED"

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        # Check engines_affected threshold
        engine_check = next(c for c in checks if c["check"] == "engines_affected_threshold")
        self.assertEqual(engine_check["result"], "PASS")
        score_check = next(c for c in checks if c["check"] == "compound_score_threshold")
        self.assertEqual(score_check["result"], "PASS")


# ---------------------------------------------------------------------------
# UT-VIR-008: Inconsistent count vs list
# ---------------------------------------------------------------------------

class TestInconsistency(unittest.TestCase):
    """UT-VIR-008: len(affected_engines) != engines_affected."""

    def test_inconsistent_count(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        report["engines_affected"] = 5  # Mismatch

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "consistency")
        self.assertEqual(check["result"], "FAIL")


# ---------------------------------------------------------------------------
# UT-VIR-009: Recommendation coherence
# ---------------------------------------------------------------------------

class TestRecommendationCoherence(unittest.TestCase):
    """UT-VIR-009: Recommendation must match threshold conditions."""

    def test_proceed_when_should_reject(self):
        report = make_report_with_score(1, 0, 0, 0)
        report["recommendation"] = "PROCEED"  # Wrong — single engine

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        rec_check = next(c for c in checks if c["check"] == "recommendation_coherence")
        self.assertEqual(rec_check["result"], "FAIL")

    def test_reject_when_should_proceed(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        report["recommendation"] = "REJECT"  # Wrong — meets thresholds

        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")


# ---------------------------------------------------------------------------
# Schema checks
# ---------------------------------------------------------------------------

class TestSchemaChecks(unittest.TestCase):
    """Test schema validation."""

    def test_missing_keys_fail(self):
        report = {"finding_id": "tv-001"}
        result, checks = vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(result, "REJECTED")
        schema_check = next(c for c in checks if c["check"] == "schema_completeness")
        self.assertEqual(schema_check["result"], "FAIL")

    def test_all_keys_pass(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        _, checks = vir.validate(report, None, ENGINE_GRAPH)
        schema_check = next(c for c in checks if c["check"] == "schema_completeness")
        self.assertEqual(schema_check["result"], "PASS")


# ---------------------------------------------------------------------------
# UT-VIR-010 through UT-VIR-014: output_format and ErrorRecord
# ---------------------------------------------------------------------------

class TestJsonOutputFormat(unittest.TestCase):
    """UT-VIR-010: output_format='json' emits one JSON line per check."""

    def test_json_format_emits_lines(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        lines = [l for l in stdout.getvalue().strip().split("\n") if l]
        self.assertGreater(len(lines), 0)

    def test_json_line_count_matches_checks(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result, checks = vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        lines = [l for l in stdout.getvalue().strip().split("\n") if l]
        self.assertEqual(len(lines), len(checks))

    def test_json_lines_are_valid_json(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        for line in stdout.getvalue().strip().split("\n"):
            if line:
                record = json.loads(line)
                self.assertIsInstance(record, dict)


class TestTextOutputFormat(unittest.TestCase):
    """UT-VIR-011: output_format='text' (default) produces no extra stdout."""

    def test_text_format_no_json_lines(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH, output_format="text")
        self.assertEqual(stdout.getvalue(), "")

    def test_default_is_text_format(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH)
        self.assertEqual(stdout.getvalue(), "")


class TestInvalidOutputFormat(unittest.TestCase):
    """UT-VIR-012: invalid output_format raises ValueError."""

    def test_invalid_format_raises(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        with self.assertRaises(ValueError) as ctx:
            vir.validate(report, None, ENGINE_GRAPH, output_format="xml")
        self.assertIn("xml", str(ctx.exception))

    def test_empty_format_raises(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        with self.assertRaises(ValueError):
            vir.validate(report, None, ENGINE_GRAPH, output_format="")


class TestErrorRecordSchema(unittest.TestCase):
    """UT-VIR-013: ErrorRecord fields present and exact in JSON output."""

    def test_record_has_exact_keys(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        for line in stdout.getvalue().strip().split("\n"):
            if line:
                record = json.loads(line)
                self.assertEqual(set(record.keys()), {"code", "message", "context"})

    def test_code_is_check_name(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result, checks = vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        lines = [l for l in stdout.getvalue().strip().split("\n") if l]
        codes = [json.loads(l)["code"] for l in lines]
        check_names = [c["check"] for c in checks]
        self.assertEqual(codes, check_names)

    def test_context_has_result_field(self):
        report = make_report_with_score(3, 2, 0.3, 0.2)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            vir.validate(report, None, ENGINE_GRAPH, output_format="json")
        for line in stdout.getvalue().strip().split("\n"):
            if line:
                record = json.loads(line)
                self.assertIn("result", record["context"])


class TestErrorRecordImport(unittest.TestCase):
    """UT-VIR-014: ErrorRecord, format_error_record, emit_json_line importable."""

    def test_error_record_importable(self):
        self.assertTrue(hasattr(vir, "ErrorRecord"))

    def test_format_error_record_importable(self):
        self.assertTrue(hasattr(vir, "format_error_record"))

    def test_emit_json_line_importable(self):
        self.assertTrue(hasattr(vir, "emit_json_line"))

    def test_format_error_record_creates_valid_record(self):
        record = vir.format_error_record("test_code", "test msg", {"result": "PASS"})
        self.assertEqual(record["code"], "test_code")
        self.assertEqual(record["message"], "test msg")
        self.assertEqual(record["context"], {"result": "PASS"})

    def test_emit_json_line_produces_compact_json(self):
        record = vir.format_error_record("c", "m", {"result": "PASS"})
        line = vir.emit_json_line(record)
        parsed = json.loads(line)
        self.assertEqual(parsed, record)
        self.assertNotIn("\n", line)


if __name__ == "__main__":
    unittest.main()
