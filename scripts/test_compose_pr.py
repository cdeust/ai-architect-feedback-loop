#!/usr/bin/env python3
"""
test_compose_pr.py — Unit tests for PR description composer

Test cases:
  UT-E4-004: All 6 audit trail sections present
  UT-E4-005: Uses <details> tags for PRD and integration plan
  UT-E4-006: Includes pipeline metadata (run ID, finding ID, attempt count)
  UT-E4-007: Handles missing optional files gracefully
  UT-E4-008: Retry attempt count from retry_summary.json
  UT-E4-009: Failure details captured per attempt
  UT-E4-010: Failure issue body includes finding details + attempt log
"""

import json
import os
import sys
import tempfile
import unittest

# Add scripts dir to path
sys.path.insert(0, os.path.dirname(__file__))

from compose_pr import (
    compose_enforcement,
    compose_impact,
    compose_integration_plan,
    compose_prd_section,
    compose_retry_history,
    compose_summary,
    compose_verification,
    load_json,
    main,
)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

IMPACT_REPORT = {
    "finding_id": "tv-001",
    "finding_title": "Contextual BM25 Scoring",
    "finding_category": "retrieval",
    "relevance_score": 0.87,
    "affected_engines": ["RAGEngine", "OrchestrationEngine"],
    "compound_score": 0.65,
    "propagation_paths": [
        {"from": "RAGEngine", "to": "OrchestrationEngine", "relationship": "feeds"}
    ],
    "recommendation": "PROCEED",
}

INTEGRATION_PLAN = {
    "finding_id": "tv-001",
    "affected_engines": ["RAGEngine", "OrchestrationEngine"],
    "modifications": [
        {
            "engine": "RAGEngine",
            "files": [
                {
                    "path": "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift",
                    "action": "modify",
                }
            ],
            "contract_changes": [
                {
                    "protocol": "RetrievalPort",
                    "change": "add contextWeight parameter",
                }
            ],
        }
    ],
    "cross_engine_touchpoints": [
        {
            "from": "RAGEngine",
            "to": "OrchestrationEngine",
            "via": "RetrievalPort",
            "description": "updated scoring results",
        }
    ],
    "new_files": [],
    "test_files": [],
    "constraints": {},
}

ENFORCEMENT_REPORT = {
    "stage": "enforcement",
    "overall_result": "PASS",
    "gates": [
        {"gate": 1, "name": "prohibited_patterns", "result": "PASS", "duration_seconds": 2},
        {"gate": 3, "name": "orphan_detection", "result": "PASS", "duration_seconds": 1},
        {"gate": 4, "name": "build_verification", "result": "PASS", "duration_seconds": 45},
        {"gate": 5, "name": "test_suite", "result": "PASS", "duration_seconds": 30},
        {"gate": 6, "name": "encryption_integrity", "result": "PASS", "duration_seconds": 60},
    ],
}

VERIFICATION_RESULT = {
    "stage": "semantic_verification",
    "finding_id": "tv-001",
    "overall_result": "PASS",
    "confidence": 0.87,
    "prd_alignment_score": 0.92,
    "findings": [],
    "cross_engine_verification": {
        "touchpoints_verified": 3,
        "touchpoints_total": 3,
        "result": "PASS",
    },
    "anti_patterns_detected": [],
    "requirements_traced": {"total": 5, "matched": 5, "missing": []},
}

RETRY_SUMMARY = {
    "stage": "retry_orchestrator",
    "finding_id": "tv-001",
    "result": "ACCEPTED",
    "total_attempts": 2,
    "max_attempts": 3,
    "branch": "pipeline/improvement-tv-001",
    "attempts": [
        {
            "attempt": 1,
            "failed_stage": "stage_6",
            "failed_gate": "gate_1",
            "failure_reason": "Prohibited pattern 'TODO' found in packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift:42",
            "files_affected": [
                "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift"
            ],
        }
    ],
    "issue_url": None,
    "timestamp": "2026-02-15T12:00:00Z",
}

PRD_CONTENT = """# Feature PRD: Contextual BM25 Scoring
## 1. Overview
Upgrade RAGEngine scoring to use contextual BM25.

## 2. Requirements
- FR-TV001-1: Add contextWeight parameter to RetrievalPort
- FR-TV001-2: Implement ContextualBM25 algorithm
- FR-TV001-3: Add scoring weights

## 5. Technical Specification
Uses port/adapter pattern.

**Overall Score:** 90%
"""

PRD_VERIFICATION = """# Verification Report
**Overall Score:** 90%
- Completeness: 92%
- Accuracy: 88%
"""


class TestComposePR(unittest.TestCase):
    """Unit tests for compose_pr.py"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.tmpdir, "run")
        os.makedirs(self.run_dir)
        self._write_fixtures()

    def _write_fixtures(self):
        """Write all fixture files to the run directory."""
        # Impact report
        with open(os.path.join(self.run_dir, "impact_report_tv-001.json"), "w") as f:
            json.dump(IMPACT_REPORT, f)

        # Integration plan
        with open(os.path.join(self.run_dir, "integration_plan_tv-001.json"), "w") as f:
            json.dump(INTEGRATION_PLAN, f)

        # PRD
        prd_dir = os.path.join(self.run_dir, "prd_output_tv-001")
        os.makedirs(prd_dir)
        with open(os.path.join(prd_dir, "prd.md"), "w") as f:
            f.write(PRD_CONTENT)
        with open(os.path.join(prd_dir, "prd-verification.md"), "w") as f:
            f.write(PRD_VERIFICATION)

        # Enforcement report
        with open(os.path.join(self.run_dir, "enforcement_report.json"), "w") as f:
            json.dump(ENFORCEMENT_REPORT, f)

        # Verification result
        with open(os.path.join(self.run_dir, "verification_stage11_tv-001.json"), "w") as f:
            json.dump(VERIFICATION_RESULT, f)

        # Retry summary
        with open(os.path.join(self.run_dir, "retry_summary_tv-001.json"), "w") as f:
            json.dump(RETRY_SUMMARY, f)

    def _compose_full(self):
        """Run the full composition and return the output text."""
        output_path = os.path.join(self.tmpdir, "pr_body.md")
        sys.argv = [
            "compose_pr.py",
            "--run-dir", self.run_dir,
            "--finding-id", "tv-001",
            "--output", output_path,
        ]
        main()
        with open(output_path) as f:
            return f.read()

    # UT-E4-004: All 6 audit trail sections present
    def test_all_sections_present(self):
        """UT-E4-004: All 6 audit trail sections present in PR description."""
        output = self._compose_full()

        self.assertIn("## Summary", output)
        self.assertIn("## Impact Analysis", output)
        self.assertIn("## Enforcement Results", output)
        self.assertIn("## Verification Results", output)
        self.assertIn("## Retry History", output)
        # PRD and integration plan are in details tags
        self.assertIn("Integration Plan", output)
        self.assertIn("PRD Specification", output)

    # UT-E4-005: Uses <details> tags
    def test_details_tags(self):
        """UT-E4-005: Uses <details> tags for PRD and integration plan."""
        output = self._compose_full()

        self.assertIn("<details><summary>Integration Plan (JSON)</summary>", output)
        self.assertIn("<details><summary>PRD Specification (first 100 lines)</summary>", output)
        self.assertIn("</details>", output)

    # UT-E4-006: Pipeline metadata
    def test_pipeline_metadata(self):
        """UT-E4-006: Includes pipeline metadata (run ID, finding ID, attempt count)."""
        output = self._compose_full()

        self.assertIn("tv-001", output)
        self.assertIn("Attempts:", output)
        self.assertIn("2 of 3", output)
        self.assertIn("Pipeline Run:", output)

    # UT-E4-007: Missing optional files
    def test_missing_optional_files(self):
        """UT-E4-007: Handles missing optional files gracefully."""
        # Remove retry summary — should show "Attempt 1 of 1"
        retry_path = os.path.join(self.run_dir, "retry_summary_tv-001.json")
        os.remove(retry_path)

        output = self._compose_full()

        self.assertIn("## Summary", output)
        self.assertIn("## Retry History", output)
        # Should show first attempt success
        self.assertIn("Succeeded on first attempt", output)

    # UT-E4-008: Retry attempt count
    def test_retry_attempt_count(self):
        """UT-E4-008: Retry attempt count from retry_summary.json."""
        output = self._compose_full()

        self.assertIn("2 of 3", output)
        # Retry history should show the failure and success
        self.assertIn("stage_6", output)
        self.assertIn("FAIL", output)

    # UT-E4-009: Failure details per attempt
    def test_failure_details_per_attempt(self):
        """UT-E4-009: Failure details captured per attempt."""
        history = compose_retry_history(RETRY_SUMMARY)

        self.assertIn("stage_6", history)
        self.assertIn("Prohibited pattern", history)
        self.assertIn("Succeeded", history)  # Final success row

    # UT-E4-010: Enforcement gate names
    def test_enforcement_gate_names(self):
        """UT-E4-010: Enforcement results use descriptive gate names."""
        enforcement_text = compose_enforcement(ENFORCEMENT_REPORT)

        self.assertIn("Prohibited Patterns", enforcement_text)
        self.assertIn("Orphan Detection", enforcement_text)
        self.assertIn("Build Verification (make build-library)", enforcement_text)
        self.assertIn("Test Suite (make test-all)", enforcement_text)
        self.assertIn("Encryption Integrity (make distribute)", enforcement_text)


class TestComposePRHelpers(unittest.TestCase):
    """Unit tests for individual compose functions."""

    def test_compose_summary_no_impact(self):
        """Summary renders without impact data."""
        result = compose_summary("tv-999", None, None, None, None, "/tmp/runs/20260215")
        self.assertIn("tv-999", result)
        self.assertIn("N/A", result)

    def test_compose_verification_no_data(self):
        """Verification renders gracefully with no data."""
        result = compose_verification(None)
        self.assertIn("No verification data available", result)

    def test_compose_impact_propagation(self):
        """Impact section includes propagation paths."""
        result = compose_impact(IMPACT_REPORT)
        self.assertIn("RAGEngine", result)
        self.assertIn("OrchestrationEngine", result)
        self.assertIn("feeds", result)

    def test_compose_prd_truncation(self):
        """PRD section truncates to 100 lines."""
        long_prd = "\n".join([f"Line {i}" for i in range(200)])
        result = compose_prd_section(long_prd)
        self.assertIn("truncated", result)
        self.assertIn("200 total lines", result)

    def test_load_json_missing_file(self):
        """load_json returns None for missing file."""
        self.assertIsNone(load_json("/nonexistent/path.json"))

    def test_load_json_invalid(self):
        """load_json returns None for invalid JSON."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write("not json")
            f.flush()
            self.assertIsNone(load_json(f.name))
            os.unlink(f.name)

    def test_retry_history_no_failures(self):
        """Retry history shows first-attempt success when no failures."""
        result = compose_retry_history(None)
        self.assertIn("Succeeded on first attempt", result)


if __name__ == "__main__":
    unittest.main()
