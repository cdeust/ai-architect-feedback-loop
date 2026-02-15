#!/usr/bin/env python3
"""
Unit tests for parse_findings.py (PIPE-E1-001)

Covers:
  UT-001 (AC-E1-001): Parse valid TV JSON, extract matching relevance categories
  UT-002 (AC-E1-002): Filter by relevance score threshold — keeps 3 of 4
  UT-003 (AC-E1-003): Empty TV output — clean exit code 0
  UT-004 (AC-E1-004): Malformed JSON — exit code 1, error to stderr
  UT-005 (AC-E1-001): Output valid findings.json schema
  UT-006 (AC-E1-001): Accepts all 14 relevance categories
  UT-007 (AC-E1-001): Rejects findings with unknown relevance category
  UT-008 (AC-E1-002): Custom threshold via --threshold overrides default
  UT-009 (AC-E1-001): Stats block shows total, filtered, categories_matched

Uses temp files with synthetic TV output — no external dependencies.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import parse_findings as pf


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ALL_CATEGORIES = [
    "api_change", "behavior_change", "dependency_change", "config_change",
    "schema_change", "performance_change", "security_change",
    "prompting", "retrieval", "verification", "embeddings",
    "inference", "cost_optimization", "benchmarks",
]


def make_finding(id_, category, score, title="Finding"):
    return {
        "id": id_,
        "title": title,
        "description": f"Description for {id_}",
        "source_url": f"https://example.com/{id_}",
        "relevance_category": category,
        "relevance_score": score,
        "raw_data": {},
    }


def make_tv_output(findings):
    return {"findings": findings}


def write_json(tmpdir, filename, data):
    path = os.path.join(tmpdir, filename)
    with open(path, "w") as f:
        json.dump(data, f)
    return path


def write_text(tmpdir, filename, text):
    path = os.path.join(tmpdir, filename)
    with open(path, "w") as f:
        f.write(text)
    return path


def run_main(tmpdir, tv_data, threshold=None, config_path=None):
    """Run parse_findings.main() and return (output_data, exit_code)."""
    input_path = write_json(tmpdir, "tv_input.json", tv_data)
    output_path = os.path.join(tmpdir, "findings.json")

    argv = ["--input", input_path, "--output", output_path]
    if threshold is not None:
        argv += ["--threshold", str(threshold)]
    if config_path:
        argv += ["--config", config_path]

    pf.main(argv)

    with open(output_path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# UT-001: Valid TV Output Parsing (AC-E1-001)
# ---------------------------------------------------------------------------

class TestValidParsing(unittest.TestCase):
    """UT-001: Parse valid TV JSON with 10 findings, extract matching categories."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_extracts_matching_findings(self):
        findings = [
            make_finding("f01", "retrieval", 0.9),
            make_finding("f02", "verification", 0.8),
            make_finding("f03", "prompting", 0.7),
            make_finding("f04", "api_change", 0.85),
            make_finding("f05", "behavior_change", 0.6),
            make_finding("f06", "unknown_category", 0.95),  # rejected
            make_finding("f07", "embeddings", 0.5),
            make_finding("f08", "inference", 0.6),
            make_finding("f09", "cost_optimization", 0.75),
            make_finding("f10", "benchmarks", 0.55),
        ]
        tv = make_tv_output(findings)
        result = run_main(self.tmpdir, tv, threshold=0.5)

        # 9 of 10 pass (all except unknown_category)
        self.assertEqual(result["stats"]["total_findings"], 10)
        self.assertEqual(result["stats"]["filtered_findings"], 9)

    def test_preserves_finding_fields(self):
        findings = [make_finding("f01", "retrieval", 0.9, title="RAG improvement")]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)

        f = result["findings"][0]
        self.assertEqual(f["id"], "f01")
        self.assertEqual(f["title"], "RAG improvement")
        self.assertEqual(f["relevance_category"], "retrieval")
        self.assertEqual(f["relevance_score"], 0.9)
        self.assertIn("source_url", f)
        self.assertIn("raw_data", f)


# ---------------------------------------------------------------------------
# UT-002: Relevance Score Filtering (AC-E1-002)
# ---------------------------------------------------------------------------

class TestScoreFiltering(unittest.TestCase):
    """UT-002: Filter by threshold 0.5 — keeps scores >= 0.5 (3 of 4)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_filters_by_threshold(self):
        findings = [
            make_finding("f01", "retrieval", 0.2),
            make_finding("f02", "retrieval", 0.5),
            make_finding("f03", "retrieval", 0.8),
            make_finding("f04", "retrieval", 0.9),
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)

        self.assertEqual(result["stats"]["filtered_findings"], 3)
        ids = [f["id"] for f in result["findings"]]
        self.assertNotIn("f01", ids)
        self.assertIn("f02", ids)
        self.assertIn("f03", ids)
        self.assertIn("f04", ids)

    def test_threshold_boundary_inclusive(self):
        """Score exactly at threshold should pass."""
        findings = [make_finding("f01", "retrieval", 0.5)]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)
        self.assertEqual(result["stats"]["filtered_findings"], 1)

    def test_threshold_boundary_exclusive_below(self):
        """Score just below threshold should fail."""
        findings = [make_finding("f01", "retrieval", 0.49)]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)
        self.assertEqual(result["stats"]["filtered_findings"], 0)


# ---------------------------------------------------------------------------
# UT-003: Empty TV Output (AC-E1-003)
# ---------------------------------------------------------------------------

class TestEmptyOutput(unittest.TestCase):
    """UT-003: Empty TV output → exit code 0, empty findings array."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_empty_findings_array(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.5)
        self.assertEqual(result["findings"], [])
        self.assertEqual(result["stats"]["total_findings"], 0)
        self.assertEqual(result["stats"]["filtered_findings"], 0)

    def test_missing_findings_key(self):
        """TV output with no 'findings' key treated as empty."""
        result = run_main(self.tmpdir, {}, threshold=0.5)
        self.assertEqual(result["findings"], [])

    def test_empty_output_exit_code(self):
        """Script exits cleanly (code 0) on empty input."""
        input_path = write_json(self.tmpdir, "empty.json", {"findings": []})
        output_path = os.path.join(self.tmpdir, "out.json")
        script = os.path.join(os.path.dirname(__file__), "parse_findings.py")

        result = subprocess.run(
            [sys.executable, script,
             "--input", input_path,
             "--output", output_path,
             "--threshold", "0.5"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0)


# ---------------------------------------------------------------------------
# UT-004: Malformed JSON Rejection (AC-E1-004)
# ---------------------------------------------------------------------------

class TestMalformedJson(unittest.TestCase):
    """UT-004: Malformed JSON → exit code 1, error to stderr."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_truncated_json(self):
        input_path = write_text(self.tmpdir, "bad.json", '{"findings": [')
        output_path = os.path.join(self.tmpdir, "out.json")
        script = os.path.join(os.path.dirname(__file__), "parse_findings.py")

        result = subprocess.run(
            [sys.executable, script,
             "--input", input_path,
             "--output", output_path,
             "--threshold", "0.5"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("JSON", result.stderr)

    def test_invalid_syntax(self):
        input_path = write_text(self.tmpdir, "bad2.json", "not json at all")
        output_path = os.path.join(self.tmpdir, "out.json")
        script = os.path.join(os.path.dirname(__file__), "parse_findings.py")

        result = subprocess.run(
            [sys.executable, script,
             "--input", input_path,
             "--output", output_path,
             "--threshold", "0.5"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("ERROR", result.stderr)

    def test_non_object_json(self):
        """JSON array at root (not object) should be rejected."""
        input_path = write_json(self.tmpdir, "array.json", [1, 2, 3])
        output_path = os.path.join(self.tmpdir, "out.json")
        script = os.path.join(os.path.dirname(__file__), "parse_findings.py")

        result = subprocess.run(
            [sys.executable, script,
             "--input", input_path,
             "--output", output_path,
             "--threshold", "0.5"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)


# ---------------------------------------------------------------------------
# UT-005: Output Schema Validation (AC-E1-001)
# ---------------------------------------------------------------------------

class TestOutputSchema(unittest.TestCase):
    """UT-005: Output valid findings.json schema with all required fields."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_top_level_keys(self):
        findings = [make_finding("f01", "retrieval", 0.9)]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)

        for key in ["pipeline_version", "generated_at", "source",
                     "threshold_used", "findings", "stats"]:
            self.assertIn(key, result, f"Missing top-level key: {key}")

    def test_pipeline_version(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.5)
        self.assertEqual(result["pipeline_version"], "1.0")

    def test_source_value(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.5)
        self.assertEqual(result["source"], "technical_veil")

    def test_threshold_recorded(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.7)
        self.assertEqual(result["threshold_used"], 0.7)

    def test_generated_at_iso(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.5)
        ts = result["generated_at"]
        self.assertRegex(ts, r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")


# ---------------------------------------------------------------------------
# UT-006: All 14 Relevance Categories (AC-E1-001)
# ---------------------------------------------------------------------------

class TestAllCategories(unittest.TestCase):
    """UT-006: Accepts all 14 relevance categories (7 change + 7 AI domain)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_all_categories_accepted(self):
        findings = [
            make_finding(f"f{i:02d}", cat, 0.9)
            for i, cat in enumerate(ALL_CATEGORIES)
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)
        self.assertEqual(result["stats"]["filtered_findings"], 14)
        self.assertEqual(
            sorted(result["stats"]["categories_matched"]),
            sorted(ALL_CATEGORIES),
        )


# ---------------------------------------------------------------------------
# UT-007: Unknown Category Rejection (AC-E1-001)
# ---------------------------------------------------------------------------

class TestUnknownCategory(unittest.TestCase):
    """UT-007: Rejects findings with unknown relevance category."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_unknown_category_filtered_out(self):
        findings = [
            make_finding("f01", "retrieval", 0.9),
            make_finding("f02", "made_up_category", 0.95),
            make_finding("f03", "", 0.9),
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)
        self.assertEqual(result["stats"]["filtered_findings"], 1)
        self.assertEqual(result["findings"][0]["id"], "f01")


# ---------------------------------------------------------------------------
# UT-008: Custom Threshold Override (AC-E1-002)
# ---------------------------------------------------------------------------

class TestCustomThreshold(unittest.TestCase):
    """UT-008: --threshold overrides config default."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_custom_threshold_0_7(self):
        findings = [
            make_finding("f01", "retrieval", 0.2),
            make_finding("f02", "retrieval", 0.5),
            make_finding("f03", "retrieval", 0.8),
            make_finding("f04", "retrieval", 0.9),
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.7)
        self.assertEqual(result["stats"]["filtered_findings"], 2)
        self.assertEqual(result["threshold_used"], 0.7)

    def test_threshold_0_means_all_pass(self):
        findings = [
            make_finding("f01", "retrieval", 0.0),
            make_finding("f02", "retrieval", 0.1),
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.0)
        self.assertEqual(result["stats"]["filtered_findings"], 2)

    def test_config_threshold_used_when_no_override(self):
        config = {
            "stage_1": {
                "relevance_score_minimum": 0.8,
                "relevance_categories": ALL_CATEGORIES,
            }
        }
        config_path = write_json(self.tmpdir, "thresholds.json", config)

        findings = [
            make_finding("f01", "retrieval", 0.5),
            make_finding("f02", "retrieval", 0.9),
        ]
        input_path = write_json(self.tmpdir, "tv.json", make_tv_output(findings))
        output_path = os.path.join(self.tmpdir, "findings.json")

        pf.main(["--input", input_path, "--output", output_path,
                  "--config", config_path])

        with open(output_path) as f:
            result = json.load(f)
        self.assertEqual(result["stats"]["filtered_findings"], 1)
        self.assertEqual(result["threshold_used"], 0.8)


# ---------------------------------------------------------------------------
# UT-009: Stats Block (AC-E1-001)
# ---------------------------------------------------------------------------

class TestStatsBlock(unittest.TestCase):
    """UT-009: Stats shows total_findings, filtered_findings, categories_matched."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_stats_counts(self):
        findings = [
            make_finding("f01", "retrieval", 0.9),
            make_finding("f02", "prompting", 0.8),
            make_finding("f03", "retrieval", 0.3),  # below threshold
            make_finding("f04", "unknown", 0.9),    # bad category
            make_finding("f05", "api_change", 0.7),
        ]
        result = run_main(self.tmpdir, make_tv_output(findings), threshold=0.5)

        stats = result["stats"]
        self.assertEqual(stats["total_findings"], 5)
        self.assertEqual(stats["filtered_findings"], 3)
        self.assertEqual(sorted(stats["categories_matched"]),
                         ["api_change", "prompting", "retrieval"])

    def test_stats_keys_present(self):
        result = run_main(self.tmpdir, make_tv_output([]), threshold=0.5)
        stats = result["stats"]
        for key in ["total_findings", "filtered_findings", "categories_matched"]:
            self.assertIn(key, stats, f"Missing stats key: {key}")


# ---------------------------------------------------------------------------
# Utility function tests
# ---------------------------------------------------------------------------

class TestConfigLoading(unittest.TestCase):
    """Test config loading edge cases."""

    def test_no_config_returns_defaults(self):
        threshold, categories = pf.load_config(None)
        self.assertEqual(threshold, 0.5)
        self.assertEqual(len(categories), 14)

    def test_missing_config_file_returns_defaults(self):
        threshold, categories = pf.load_config("/nonexistent/path.json")
        self.assertEqual(threshold, 0.5)

    def test_valid_config_loads(self):
        tmpdir = tempfile.mkdtemp()
        config = {
            "stage_1": {
                "relevance_score_minimum": 0.3,
                "relevance_categories": ["retrieval"],
            }
        }
        path = write_json(tmpdir, "cfg.json", config)
        threshold, categories = pf.load_config(path)
        self.assertEqual(threshold, 0.3)
        self.assertEqual(categories, ["retrieval"])


class TestFilterFindings(unittest.TestCase):
    """Test filter_findings directly."""

    def test_empty_input(self):
        filtered, cats = pf.filter_findings([], 0.5, ALL_CATEGORIES)
        self.assertEqual(filtered, [])
        self.assertEqual(cats, [])

    def test_all_below_threshold(self):
        findings = [make_finding("f01", "retrieval", 0.1)]
        filtered, cats = pf.filter_findings(findings, 0.5, ALL_CATEGORIES)
        self.assertEqual(len(filtered), 0)

    def test_mixed_categories_and_scores(self):
        findings = [
            make_finding("f01", "retrieval", 0.9),
            make_finding("f02", "bad_cat", 0.9),
            make_finding("f03", "prompting", 0.1),
        ]
        filtered, cats = pf.filter_findings(findings, 0.5, ALL_CATEGORIES)
        self.assertEqual(len(filtered), 1)
        self.assertEqual(filtered[0]["id"], "f01")


if __name__ == "__main__":
    unittest.main()
