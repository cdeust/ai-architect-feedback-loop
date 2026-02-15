#!/usr/bin/env python3
"""
Unit tests for compose_prd_input.py (PIPE-E3-001)

Covers:
  UT-CPI-001: Engine mapping — affected_engines → package path from engine_graph
  UT-CPI-002: Port resolution — category retrieval → related ports
  UT-CPI-003: Service resolution — category retrieval → key services
  UT-CPI-004: Dependency subgraph — RAGEngine → feeds: OrchestrationEngine
  UT-CPI-005: Manifest constraints — must_change / must_not_change in output
  UT-CPI-006: Contract embedding — contracts markdown in output
  UT-CPI-007: Missing impact report → sys.exit(1)
  UT-CPI-008: Missing manifest → graceful degradation
  UT-CPI-009: Batch mode — 3 findings → 3 output files
  UT-CPI-010: Empty affected_engines → sys.exit(1)
  UT-CPI-011: Cross-engine touchpoints in output
  UT-CPI-012: Finding metadata present
  UT-CPI-013: Architecture guidelines in output
  UT-CPI-014: Unknown engine → warning but no failure

Uses synthetic data — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import compose_prd_input as cpi


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

ENGINE_GRAPH = {
    "engines": {
        "RAGEngine": {
            "package_path": "packages/AIPRDRAGEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["MetaPromptingEngine", "OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
            "role": "retrieval",
        },
        "MetaPromptingEngine": {
            "package_path": "packages/AIPRDMetaPromptingEngine",
            "depends_on": ["RAGEngine", "SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
            "role": "prompting",
        },
        "OrchestrationEngine": {
            "package_path": "packages/AIPRDOrchestrationEngine",
            "depends_on": ["MetaPromptingEngine", "RAGEngine", "SharedUtilities"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities", "RAGEngine"],
            "role": "orchestration",
        },
        "SharedUtilities": {
            "package_path": "packages/AIPRDSharedUtilities",
            "depends_on": [],
            "depended_by": ["RAGEngine", "MetaPromptingEngine", "OrchestrationEngine"],
            "feeds": ["RAGEngine", "OrchestrationEngine", "MetaPromptingEngine"],
            "fed_by": [],
            "role": "common_infrastructure",
        },
    },
    "stats": {"engine_count": 4, "edge_count": 6, "max_depth": 3, "cycles_detected": 0},
}

CATEGORY_MAP = {
    "mappings": {
        "retrieval": {
            "primary_engines": ["RAGEngine"],
            "related_ports": ["EmbeddingGeneratorPort", "VectorSearchPort", "FullTextSearchPort"],
            "key_services": ["EnrichedContextBuilder.gatherCodebaseContext()"],
        },
        "prompting": {
            "primary_engines": ["MetaPromptingEngine"],
            "related_ports": ["ThinkingPort", "FewShotPromptPort"],
            "key_services": ["ThinkingOrchestratorUseCase"],
        },
    }
}


def make_impact_report(**overrides):
    base = {
        "finding_id": "tv-001",
        "finding_title": "Contextual BM25 Scoring",
        "finding_description": "Microsoft research shows contextual BM25 outperforms vanilla BM25",
        "source_url": "http://arxiv.org/abs/2401.12345",
        "finding_category": "retrieval",
        "relevance_score": 0.87,
        "affected_engines": ["RAGEngine", "OrchestrationEngine"],
        "compound_score": 0.65,
        "propagation_paths": [
            {"from": "RAGEngine", "to": "OrchestrationEngine", "relationship": "depends_on"}
        ],
        "recommendation": "PROCEED",
    }
    base.update(overrides)
    return base


def make_integration_plan(**overrides):
    base = {
        "finding_id": "tv-001",
        "affected_engines": ["RAGEngine", "OrchestrationEngine"],
        "modifications": [],
        "cross_engine_touchpoints": [
            {"from": "RAGEngine", "to": "OrchestrationEngine",
             "via": "RetrievalPort", "description": "updated scoring results"}
        ],
        "contract_changes": [],
        "new_files": [],
        "test_files": [],
        "constraints": {},
    }
    base.update(overrides)
    return base


def make_manifest(**overrides):
    base = {
        "must_change": [
            "packages/AIPRDRAGEngine/Sources/Retrieval/ContextualBM25.swift",
            "packages/AIPRDSharedUtilities/Sources/Domain/Ports/RetrievalPort.swift",
        ],
        "must_not_change": [
            "packages/AIPRDEncryptionEngine/Package.swift",
            "library/Package.swift",
        ],
        "allowed_new_files": [],
    }
    base.update(overrides)
    return base


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestCompose(unittest.TestCase):
    """Unit tests for compose() function."""

    def test_engine_mapping(self):
        """UT-CPI-001: affected_engines → package path from engine_graph."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("packages/AIPRDRAGEngine", md)

    def test_port_resolution(self):
        """UT-CPI-002: category retrieval → related ports."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("EmbeddingGeneratorPort", md)
        self.assertIn("VectorSearchPort", md)

    def test_service_resolution(self):
        """UT-CPI-003: category retrieval → key services."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("EnrichedContextBuilder.gatherCodebaseContext()", md)

    def test_dependency_subgraph(self):
        """UT-CPI-004: RAGEngine → feeds: OrchestrationEngine."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("feeds: OrchestrationEngine", md)

    def test_manifest_constraints(self):
        """UT-CPI-005: must_change / must_not_change in output."""
        manifest = make_manifest()
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), manifest,
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("ContextualBM25.swift", md)
        self.assertIn("EncryptionEngine/Package.swift", md)

    def test_contract_embedding(self):
        """UT-CPI-006: contracts markdown embedded."""
        contracts = "public protocol EmbeddingGeneratorPort {\n    func generate() -> [Float]\n}"
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            contracts, ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("public protocol EmbeddingGeneratorPort", md)

    def test_missing_manifest_graceful(self):
        """UT-CPI-008: missing manifest → graceful degradation."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), None,
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("No manifest constraints available", md)

    def test_cross_engine_touchpoints(self):
        """UT-CPI-011: touchpoints appear in output."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("RAGEngine -> OrchestrationEngine via RetrievalPort", md)

    def test_finding_metadata(self):
        """UT-CPI-012: title, description, source URL, relevance score present."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("tv-001", md)
        self.assertIn("Contextual BM25 Scoring", md)
        self.assertIn("http://arxiv.org/abs/2401.12345", md)
        self.assertIn("0.87", md)

    def test_architecture_guidelines(self):
        """UT-CPI-013: output includes port/adapter rules."""
        md = cpi.compose(
            make_impact_report(), make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        self.assertIn("SharedUtilities = domain layer", md)
        self.assertIn("NO @_exported import", md)
        self.assertIn("EnrichedContextBuilder", md)

    def test_unknown_engine_warning(self):
        """UT-CPI-014: unknown engine → no crash."""
        report = make_impact_report(affected_engines=["RAGEngine", "UnknownEngine"])
        md = cpi.compose(
            report, make_integration_plan(), make_manifest(),
            "", ENGINE_GRAPH, CATEGORY_MAP
        )
        # Should still contain RAGEngine info
        self.assertIn("packages/AIPRDRAGEngine", md)


class TestCLI(unittest.TestCase):
    """Test CLI interface for compose_prd_input.py."""

    def _write_json(self, tmpdir, name, data):
        path = os.path.join(tmpdir, name)
        with open(path, "w") as f:
            json.dump(data, f)
        return path

    def test_missing_impact_report_exits(self):
        """UT-CPI-007: missing impact report → sys.exit(1)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            eg = self._write_json(tmpdir, "eg.json", ENGINE_GRAPH)
            cm = self._write_json(tmpdir, "cm.json", CATEGORY_MAP)
            out = os.path.join(tmpdir, "out.md")

            with self.assertRaises(SystemExit) as ctx:
                cpi.main([
                    "--impact-report", os.path.join(tmpdir, "nonexistent.json"),
                    "--engine-graph", eg,
                    "--category-map", cm,
                    "--output", out,
                ])
            self.assertEqual(ctx.exception.code, 1)

    def test_empty_affected_engines_exits(self):
        """UT-CPI-010: empty affected_engines → sys.exit(1)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            report = make_impact_report(affected_engines=[])
            ir = self._write_json(tmpdir, "ir.json", report)
            eg = self._write_json(tmpdir, "eg.json", ENGINE_GRAPH)
            cm = self._write_json(tmpdir, "cm.json", CATEGORY_MAP)
            out = os.path.join(tmpdir, "out.md")

            with self.assertRaises(SystemExit) as ctx:
                cpi.main([
                    "--impact-report", ir,
                    "--engine-graph", eg,
                    "--category-map", cm,
                    "--output", out,
                ])
            self.assertEqual(ctx.exception.code, 1)

    def test_batch_mode(self):
        """UT-CPI-009: batch mode — 3 findings → 3 output files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            eg = self._write_json(tmpdir, "eg.json", ENGINE_GRAPH)
            cm = self._write_json(tmpdir, "cm.json", CATEGORY_MAP)

            for i in range(1, 4):
                fid = f"tv-{i:03d}"
                self._write_json(tmpdir, f"validation_stage3_{fid}.json", {
                    "result": "ACCEPTED", "finding_id": fid,
                })
                self._write_json(tmpdir, f"impact_report_{fid}.json",
                    make_impact_report(finding_id=fid))
                self._write_json(tmpdir, f"integration_plan_{fid}.json",
                    make_integration_plan(finding_id=fid))

            cpi.main([
                "--batch-dir", tmpdir,
                "--engine-graph", eg,
                "--category-map", cm,
            ])

            for i in range(1, 4):
                fid = f"tv-{i:03d}"
                self.assertTrue(
                    os.path.isfile(os.path.join(tmpdir, f"prd_input_{fid}.md")),
                    f"Missing prd_input_{fid}.md"
                )


if __name__ == "__main__":
    unittest.main()
