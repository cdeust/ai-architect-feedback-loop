#!/usr/bin/env python3
"""
Unit tests for generate_manifest.py (PIPE-E2-005)

Covers:
  UT-GM-001: Correct must_change — matches plan's modify-action files
  UT-GM-002: Correct must_not_change — Package.swift for unaffected engines + library + Makefile
  UT-GM-003: Correct allowed_new_files — matches plan's test_files
  UT-GM-004: Minimal plan — single engine, large must_not_change
  UT-GM-005: Output schema — generated_from, generated_at, all arrays present

Uses synthetic data — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_manifest as gm


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

ENGINE_GRAPH = {
    "engines": {
        "SharedUtilities": {
            "package_path": "packages/AIPRDSharedUtilities",
            "depends_on": [],
            "depended_by": ["RAGEngine", "VerificationEngine", "OrchestrationEngine",
                            "MetaPromptingEngine", "StrategyEngine", "EncryptionEngine"],
            "feeds": [],
            "fed_by": [],
        },
        "RAGEngine": {
            "package_path": "packages/AIPRDRAGEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "MetaPromptingEngine": {
            "package_path": "packages/AIPRDMetaPromptingEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "VerificationEngine": {
            "package_path": "packages/AIPRDVerificationEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "StrategyEngine": {
            "package_path": "packages/AIPRDStrategyEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
        },
        "EncryptionEngine": {
            "package_path": "packages/AIPRDEncryptionEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities"],
        },
        "OrchestrationEngine": {
            "package_path": "packages/AIPRDOrchestrationEngine",
            "depends_on": ["SharedUtilities", "RAGEngine"],
            "depended_by": [],
            "feeds": [],
            "fed_by": [],
        },
    },
}


def make_plan(affected_engines, modify_files, test_files=None):
    """Create a minimal integration plan."""
    modifications = []
    for engine in affected_engines:
        engine_files = [f for f in modify_files if engine in f]
        modifications.append({
            "engine": engine,
            "files": [{"path": f, "action": "modify", "description": "change"} for f in engine_files],
            "contract_changes": [],
        })
    return {
        "finding_id": "tv-test",
        "affected_engines": affected_engines,
        "modifications": modifications,
        "cross_engine_touchpoints": [],
        "new_files": [],
        "test_files": test_files or [],
        "constraints": {"no_new_packages": True, "no_standalone_modules": True,
                        "existing_dependency_graph_only": True},
    }


# ---------------------------------------------------------------------------
# UT-GM-001: Correct must_change
# ---------------------------------------------------------------------------

class TestMustChange(unittest.TestCase):
    """UT-GM-001: must_change matches plan's modify-action files exactly."""

    def test_must_change_from_modifications(self):
        plan = make_plan(
            ["RAGEngine", "OrchestrationEngine"],
            ["packages/AIPRDRAGEngine/Sources/BM25.swift",
             "packages/AIPRDOrchestrationEngine/Sources/Pipeline.swift"],
        )
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertEqual(sorted(manifest["must_change"]), [
            "packages/AIPRDOrchestrationEngine/Sources/Pipeline.swift",
            "packages/AIPRDRAGEngine/Sources/BM25.swift",
        ])

    def test_no_duplicates(self):
        plan = make_plan(["RAGEngine"], [
            "packages/AIPRDRAGEngine/Sources/BM25.swift",
            "packages/AIPRDRAGEngine/Sources/BM25.swift",
        ])
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertEqual(len(manifest["must_change"]), 1)


# ---------------------------------------------------------------------------
# UT-GM-002: Correct must_not_change
# ---------------------------------------------------------------------------

class TestMustNotChange(unittest.TestCase):
    """UT-GM-002: Includes unaffected engine paths + Makefile."""

    def test_unaffected_engines_protected(self):
        plan = make_plan(
            ["RAGEngine"],
            ["packages/AIPRDRAGEngine/Sources/BM25.swift"],
        )
        manifest = gm.generate(plan, ENGINE_GRAPH)

        # EncryptionEngine is unaffected, its path should be protected
        self.assertIn("packages/AIPRDEncryptionEngine",
                       manifest["must_not_change"])
        # RAGEngine is affected, should NOT be protected
        self.assertNotIn("packages/AIPRDRAGEngine",
                          manifest["must_not_change"])

    def test_makefile_always_protected(self):
        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        manifest = gm.generate(plan, ENGINE_GRAPH)

        self.assertIn("Makefile", manifest["must_not_change"])


# ---------------------------------------------------------------------------
# UT-GM-003: Correct allowed_new_files
# ---------------------------------------------------------------------------

class TestAllowedNewFiles(unittest.TestCase):
    """UT-GM-003: Matches plan's test_files."""

    def test_test_files_become_allowed(self):
        plan = make_plan(
            ["RAGEngine"],
            ["packages/AIPRDRAGEngine/Sources/BM25.swift"],
            test_files=["packages/AIPRDRAGEngine/Tests/BM25Tests.swift"],
        )
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertEqual(manifest["allowed_new_files"],
                         ["packages/AIPRDRAGEngine/Tests/BM25Tests.swift"])

    def test_no_test_files(self):
        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertEqual(manifest["allowed_new_files"], [])


# ---------------------------------------------------------------------------
# UT-GM-004: Minimal plan
# ---------------------------------------------------------------------------

class TestMinimalPlan(unittest.TestCase):
    """UT-GM-004: Single engine → small must_change, large must_not_change."""

    def test_single_engine_plan(self):
        plan = make_plan(
            ["EncryptionEngine"],
            ["packages/AIPRDEncryptionEngine/Sources/Crypto.swift"],
        )
        manifest = gm.generate(plan, ENGINE_GRAPH)

        # Only 1 file to change
        self.assertEqual(len(manifest["must_change"]), 1)

        # 6 other engines protected + Makefile
        # SharedUtilities, RAGEngine, MetaPromptingEngine, VerificationEngine,
        # StrategyEngine, OrchestrationEngine = 6 engines
        engine_protected = [p for p in manifest["must_not_change"]
                           if p.startswith("packages/") and p != "Makefile"]
        self.assertEqual(len(engine_protected), 6)


# ---------------------------------------------------------------------------
# UT-GM-005: Output schema
# ---------------------------------------------------------------------------

class TestOutputSchema(unittest.TestCase):
    """UT-GM-005: Output has all required fields."""

    def test_schema_fields(self):
        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        manifest = gm.generate(plan, ENGINE_GRAPH)

        self.assertIn("generated_from", manifest)
        self.assertIn("generated_at", manifest)
        self.assertIn("must_change", manifest)
        self.assertIn("must_not_change", manifest)
        self.assertIn("allowed_new_files", manifest)

    def test_generated_from_is_finding_id(self):
        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertEqual(manifest["generated_from"], "tv-test")

    def test_generated_at_is_iso(self):
        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        manifest = gm.generate(plan, ENGINE_GRAPH)
        self.assertRegex(manifest["generated_at"],
                         r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")


# ---------------------------------------------------------------------------
# CLI integration
# ---------------------------------------------------------------------------

class TestCLI(unittest.TestCase):
    """Test main() CLI interface."""

    def test_main_writes_output(self):
        tmpdir = tempfile.mkdtemp()
        plan_path = os.path.join(tmpdir, "plan.json")
        graph_path = os.path.join(tmpdir, "graph.json")
        output_path = os.path.join(tmpdir, "manifest.json")

        plan = make_plan(["RAGEngine"], ["packages/AIPRDRAGEngine/Sources/BM25.swift"])
        with open(plan_path, "w") as f:
            json.dump(plan, f)
        with open(graph_path, "w") as f:
            json.dump(ENGINE_GRAPH, f)

        gm.main(["--plan", plan_path, "--engine-graph", graph_path, "--output", output_path])

        with open(output_path) as f:
            manifest = json.load(f)
        self.assertIn("must_change", manifest)


if __name__ == "__main__":
    unittest.main()
