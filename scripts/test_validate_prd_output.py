#!/usr/bin/env python3
"""
Unit tests for validate_prd_output.py (PIPE-E3-004)

Covers:
  UT-VPO-001: ACCEPTED — all checks pass
  UT-VPO-002: REJECTED — missing verification file
  UT-VPO-003: REJECTED — score below threshold (82% < 85%)
  UT-VPO-004: REJECTED — no story points (SP = 0)
  UT-VPO-005: REJECTED — no FR IDs
  UT-VPO-006: REJECTED — no AC IDs
  UT-VPO-007: REJECTED — engines not referenced in PRD
  UT-VPO-008: REJECTED — no test IDs (SKILL.md Rule 7)
  UT-VPO-009: REJECTED — no port/adapter in tech spec
  UT-VPO-010: Boundary — score exactly 85% passes (>=)
  UT-VPO-011: Engine name matching — uses exact names from engine_graph keys
  UT-VPO-012: Multiple failures — returns all failing checks
  UT-VPO-013: Missing metrics file → FAIL
  UT-VPO-014: Malformed metrics → FAIL

Uses synthetic data — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import validate_prd_output as vpo


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

ENGINE_GRAPH = {
    "engines": {
        "RAGEngine": {"package_path": "packages/AIPRDRAGEngine"},
        "OrchestrationEngine": {"package_path": "packages/AIPRDOrchestrationEngine"},
        "SharedUtilities": {"package_path": "packages/AIPRDSharedUtilities"},
    }
}

INTEGRATION_PLAN = {
    "finding_id": "tv-001",
    "affected_engines": ["RAGEngine", "OrchestrationEngine"],
}

CONFIG = {
    "stage_4": {"prd_quality_minimum": 0.85}
}

VALID_PRD = """# Feature PRD: Upgrade tv-001

## 1. Overview
Overview text with RAGEngine and OrchestrationEngine references.

## 2. Goals & Success Metrics
Goals here.

## 3. Requirements
### Functional Requirements
- FR-TV001-1: Implement contextual scoring
- FR-TV001-2: Update retrieval pipeline
- FR-TV001-3: Add scoring weights
- FR-TV001-4: Expose via port
- FR-TV001-5: Wire in composition

### Acceptance Criteria
- AC-TV001-1: Scoring produces weighted results
- AC-TV001-2: Port method available
- AC-TV001-3: Tests pass
- AC-TV001-4: Performance within bounds
- AC-TV001-5: No regression

## 4. User Stories
### PIPE-TV001-1: Contextual Scoring [5 SP]
Story details.
### PIPE-TV001-2: Port Update [3 SP]
Story details.
### PIPE-TV001-3: Wiring [5 SP]
Story details.

## 5. Technical Specification
Architecture follows port/adapter pattern. RAGEngine implements the
RetrievalPort protocol defined in SharedUtilities. Changes propagate
through the adapter layer.

## 6. Implementation Roadmap
Sprint 1.

## 7. Risk Assessment
Risks listed.

## 8. Appendix
More info.
"""

VALID_VERIFICATION = """# Verification Report

**Overall Score:** 90%

### 1. Overview
- **Score:** 92%

### 2. Goals
- **Score:** 88%
"""

VALID_JIRA = """# JIRA Tickets

## PIPE-TV001-1
- AC-TV001-1: Scoring produces weighted results
"""

VALID_TESTS = """# Test Cases

## Unit Tests
- UT-001: Test contextual scoring
- UT-002: Test weight calculation
- UT-003: Test port method

## Integration Tests
- IT-001: Test end-to-end retrieval

## E2E Tests
- E2E-001: Full pipeline test
"""


def make_metrics(overall_score=0.90):
    return {
        "verification": {
            "overall_score": overall_score,
            "section_scores": {"overview": 0.92},
        },
        "structure": {
            "section_count": 8,
            "fr_count": 5,
            "ac_count": 5,
            "total_sp": 13,
        },
    }


def create_prd_dir(tmpdir, prd=VALID_PRD, verification=VALID_VERIFICATION,
                   jira=VALID_JIRA, tests=VALID_TESTS):
    """Create a PRD output directory with given file contents."""
    prd_dir = os.path.join(tmpdir, "prd_output")
    os.makedirs(prd_dir, exist_ok=True)

    if prd is not None:
        with open(os.path.join(prd_dir, "prd.md"), "w") as f:
            f.write(prd)
    if verification is not None:
        with open(os.path.join(prd_dir, "prd-verification.md"), "w") as f:
            f.write(verification)
    if jira is not None:
        with open(os.path.join(prd_dir, "prd-jira.md"), "w") as f:
            f.write(jira)
    if tests is not None:
        with open(os.path.join(prd_dir, "prd-tests.md"), "w") as f:
            f.write(tests)

    return prd_dir


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestValidatePrdOutput(unittest.TestCase):

    def test_accepted_all_pass(self):
        """UT-VPO-001: All checks pass → ACCEPTED."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir)
            metrics = make_metrics(0.90)

            result, checks, fid = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "ACCEPTED")
            self.assertEqual(fid, "tv-001")
            failures = [c for c in checks if c["result"] == "FAIL"]
            self.assertEqual(len(failures), 0)

    def test_missing_verification_file(self):
        """UT-VPO-002: missing verification file → REJECTED."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, verification=None)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            file_check = next(c for c in checks if c["check"] == "four_files_exist")
            self.assertEqual(file_check["result"], "FAIL")

    def test_score_below_threshold(self):
        """UT-VPO-003: 82% < 85% → REJECTED."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir)
            metrics = make_metrics(0.82)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            threshold_check = next(c for c in checks if c["check"] == "quality_threshold")
            self.assertEqual(threshold_check["result"], "FAIL")

    def test_no_story_points(self):
        """UT-VPO-004: SP = 0 → REJECTED."""
        prd_no_sp = VALID_PRD.replace("[5 SP]", "").replace("[3 SP]", "")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_sp)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            sp_check = next(c for c in checks if c["check"] == "story_points")
            self.assertEqual(sp_check["result"], "FAIL")

    def test_no_fr_ids(self):
        """UT-VPO-005: no FR-XXX patterns → REJECTED."""
        prd_no_fr = VALID_PRD.replace("FR-TV001-", "REQ-TV001-")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_fr)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            fr_check = next(c for c in checks if c["check"] == "fr_count")
            self.assertEqual(fr_check["result"], "FAIL")

    def test_no_ac_ids(self):
        """UT-VPO-006: no AC-XXX patterns → REJECTED."""
        prd_no_ac = VALID_PRD.replace("AC-TV001-", "CRIT-TV001-")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_ac)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            ac_check = next(c for c in checks if c["check"] == "ac_count")
            self.assertEqual(ac_check["result"], "FAIL")

    def test_engines_not_referenced(self):
        """UT-VPO-007: PRD doesn't mention any affected engine → REJECTED."""
        prd_no_engines = VALID_PRD.replace("RAGEngine", "SearchModule").replace("OrchestrationEngine", "PipelineModule")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_engines)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            eng_check = next(c for c in checks if c["check"] == "engine_references")
            self.assertEqual(eng_check["result"], "FAIL")

    def test_no_test_ids(self):
        """UT-VPO-008: no UT-/IT-/E2E- test IDs → REJECTED."""
        tests_no_ids = "# Test Cases\n\nSome tests described in prose."
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, tests=tests_no_ids)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            test_check = next(c for c in checks if c["check"] == "test_ids")
            self.assertEqual(test_check["result"], "FAIL")

    def test_no_architecture_in_tech_spec(self):
        """UT-VPO-009: tech spec missing all architecture terms → REJECTED."""
        import re
        # Replace ALL architecture terms to trigger failure
        prd_no_arch = VALID_PRD
        for term in ["module", "interface", "service", "component", "layer",
                      "port", "adapter", "protocol", "api", "contract",
                      "Module", "Interface", "Service", "Component", "Layer",
                      "Port", "Adapter", "Protocol", "API", "Contract"]:
            prd_no_arch = prd_no_arch.replace(term, "thing")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_arch)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            arch_check = next(c for c in checks if c["check"] == "architecture_in_tech_spec")
            self.assertEqual(arch_check["result"], "FAIL")

    def test_score_exactly_threshold(self):
        """UT-VPO-010: score exactly 85% passes (>=, not >)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir)
            metrics = make_metrics(0.85)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            threshold_check = next(c for c in checks if c["check"] == "quality_threshold")
            self.assertEqual(threshold_check["result"], "PASS")

    def test_engine_name_exact_match(self):
        """UT-VPO-011: uses exact names from engine_graph keys."""
        # PRD contains "AIPRDRAGEngine" but not bare "RAGEngine"
        prd_aiprd = VALID_PRD.replace("RAGEngine", "AIPRDRAGEngine").replace("OrchestrationEngine", "AIPRDOrchestrationEngine")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_aiprd)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            eng_check = next(c for c in checks if c["check"] == "engine_references")
            # "RAGEngine" substring within "AIPRDRAGEngine" → should still match
            self.assertEqual(eng_check["result"], "PASS")

    def test_multiple_failures(self):
        """UT-VPO-012: returns all failing checks, not just first."""
        prd_no_fr_ac = VALID_PRD.replace("FR-TV001-", "X-").replace("AC-TV001-", "Y-")
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir, prd=prd_no_fr_ac)
            metrics = make_metrics(0.90)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            failures = [c for c in checks if c["result"] == "FAIL"]
            self.assertGreaterEqual(len(failures), 2)

    def test_missing_metrics_file(self):
        """UT-VPO-013: None metrics → FAIL score checks."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir)

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, None, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            score_check = next(c for c in checks if c["check"] == "verification_score_exists")
            self.assertEqual(score_check["result"], "FAIL")

    def test_malformed_metrics(self):
        """UT-VPO-014: metrics without verification → FAIL."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prd_dir = create_prd_dir(tmpdir)
            metrics = {"structure": {"section_count": 8}}  # no verification key

            result, checks, _ = vpo.validate(
                prd_dir, INTEGRATION_PLAN, ENGINE_GRAPH, metrics, CONFIG
            )
            self.assertEqual(result, "REJECTED")
            score_check = next(c for c in checks if c["check"] == "verification_score_exists")
            self.assertEqual(score_check["result"], "FAIL")


if __name__ == "__main__":
    unittest.main()
