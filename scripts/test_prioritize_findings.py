#!/usr/bin/env python3
"""
Unit tests for prioritize_findings.py (PIPE-E2-001)

Covers:
  UT-P-001: Scoring — anthropic + retrieval scores higher than academic + benchmarks
  UT-P-002: Post-worthy boost — post_worthy=true ranks above post_worthy=false
  UT-P-003: Deduplication — identical titles keep highest-scored instance
  UT-P-004: Top-N cutoff — --top-n 5 returns exactly 5
  UT-P-005: Output schema — priority_score, priority_breakdown, expected_engines
  UT-P-006: Unknown category excluded
  UT-P-007: Category engine weight — retrieval > security_change
  UT-P-008: Actor relevance — major labs > academic > other
  UT-P-009: Source signal — arxiv/github > rss

Uses synthetic data — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import prioritize_findings as pf


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

CATEGORY_MAP = {
    "description": "Test mapping",
    "mappings": {
        "retrieval": {
            "primary_engines": ["RAGEngine"],
            "related_ports": ["EmbeddingGeneratorPort"],
            "key_services": ["EnrichedContextBuilder"],
        },
        "prompting": {
            "primary_engines": ["MetaPromptingEngine"],
            "related_ports": ["ThinkingPort"],
            "key_services": ["ThinkingOrchestratorUseCase"],
        },
        "verification": {
            "primary_engines": ["VerificationEngine"],
            "related_ports": ["VerificationEvidenceRepositoryPort"],
            "key_services": ["SectionVerification"],
        },
        "benchmarks": {
            "primary_engines": ["VerificationEngine", "StrategyEngine"],
            "related_ports": [],
            "key_services": ["IntelligenceTrackerService"],
        },
        "security_change": {
            "primary_engines": ["EncryptionEngine"],
            "related_ports": ["HashingPort"],
            "key_services": ["SecureLicenseValidator"],
        },
        "cost_optimization": {
            "primary_engines": ["OrchestrationEngine"],
            "related_ports": ["TokenizerPort"],
            "key_services": ["SectionTokenBudgetAllocator"],
        },
        "inference": {
            "primary_engines": ["StrategyEngine", "OrchestrationEngine"],
            "related_ports": ["AIProviderPort"],
            "key_services": ["GeneratePRDUseCase"],
        },
        "embeddings": {
            "primary_engines": ["RAGEngine"],
            "related_ports": ["EmbeddingGeneratorPort"],
            "key_services": ["EnrichedContextBuilder"],
        },
        "api_change": {
            "primary_engines": ["SharedUtilities"],
            "related_ports": ["AIProviderPort"],
            "key_services": [],
        },
        "dependency_change": {
            "primary_engines": ["SharedUtilities"],
            "related_ports": [],
            "key_services": [],
        },
    },
}

ENGINE_GRAPH = {
    "engines": {
        "SharedUtilities": {
            "package_path": "packages/AIPRDSharedUtilities",
            "depends_on": [],
            "depended_by": ["RAGEngine", "VerificationEngine", "StrategyEngine",
                            "EncryptionEngine", "MetaPromptingEngine", "OrchestrationEngine"],
            "feeds": ["RAGEngine", "VerificationEngine", "OrchestrationEngine",
                      "MetaPromptingEngine", "StrategyEngine", "EncryptionEngine"],
            "fed_by": [],
            "role": "common_infrastructure",
        },
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
        "VerificationEngine": {
            "package_path": "packages/AIPRDVerificationEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
            "role": "verification",
        },
        "StrategyEngine": {
            "package_path": "packages/AIPRDStrategyEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": ["OrchestrationEngine"],
            "feeds": ["OrchestrationEngine"],
            "fed_by": ["SharedUtilities"],
            "role": "strategy",
        },
        "EncryptionEngine": {
            "package_path": "packages/AIPRDEncryptionEngine",
            "depends_on": ["SharedUtilities"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities"],
            "role": "encryption",
        },
        "OrchestrationEngine": {
            "package_path": "packages/AIPRDOrchestrationEngine",
            "depends_on": ["SharedUtilities", "RAGEngine", "VerificationEngine",
                           "MetaPromptingEngine", "StrategyEngine"],
            "depended_by": [],
            "feeds": [],
            "fed_by": ["SharedUtilities", "RAGEngine", "VerificationEngine",
                       "MetaPromptingEngine", "StrategyEngine"],
            "role": "orchestration",
        },
    },
}


def make_finding(id_, category, score, actor="anthropic", post_worthy=False,
                 source_type="rss", title=None):
    return {
        "id": id_,
        "title": title or f"Finding {id_}",
        "description": f"Description for {id_}",
        "source_url": f"https://example.com/{id_}",
        "relevance_category": category,
        "relevance_score": score,
        "actor": actor,
        "post_worthy": post_worthy,
        "source_type": source_type,
    }


def write_json(tmpdir, filename, data):
    path = os.path.join(tmpdir, filename)
    with open(path, "w") as f:
        json.dump(data, f)
    return path


def run_prioritize(tmpdir, findings, top_n=20):
    """Run prioritize_findings.main() and return output data."""
    findings_data = {"pipeline_version": "1.0", "findings": findings}
    findings_path = write_json(tmpdir, "findings.json", findings_data)
    cat_map_path = write_json(tmpdir, "category_map.json", CATEGORY_MAP)
    graph_path = write_json(tmpdir, "engine_graph.json", ENGINE_GRAPH)
    output_path = os.path.join(tmpdir, "prioritized.json")

    pf.main([
        "--findings", findings_path,
        "--category-map", cat_map_path,
        "--engine-graph", graph_path,
        "--output", output_path,
        "--top-n", str(top_n),
    ])

    with open(output_path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# UT-P-001: Scoring — anthropic + retrieval > academic + benchmarks
# ---------------------------------------------------------------------------

class TestScoringRanking(unittest.TestCase):
    """UT-P-001: anthropic actor + retrieval category scores higher than
    academic + benchmarks (retrieval has more downstream engines)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_anthropic_retrieval_ranks_higher(self):
        findings = [
            make_finding("f01", "benchmarks", 0.5, actor="academic_research"),
            make_finding("f02", "retrieval", 0.5, actor="anthropic"),
        ]
        result = run_prioritize(self.tmpdir, findings)
        ids = [f["id"] for f in result["findings"]]
        self.assertEqual(ids[0], "f02")  # retrieval+anthropic ranks first


# ---------------------------------------------------------------------------
# UT-P-002: Post-worthy boost
# ---------------------------------------------------------------------------

class TestPostWorthyBoost(unittest.TestCase):
    """UT-P-002: post_worthy=true finding ranks above post_worthy=false."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_post_worthy_ranks_higher(self):
        findings = [
            make_finding("f01", "retrieval", 0.5, post_worthy=False, source_type="rss"),
            make_finding("f02", "retrieval", 0.5, post_worthy=True, source_type="rss"),
        ]
        result = run_prioritize(self.tmpdir, findings)
        ids = [f["id"] for f in result["findings"]]
        self.assertEqual(ids[0], "f02")


# ---------------------------------------------------------------------------
# UT-P-003: Deduplication
# ---------------------------------------------------------------------------

class TestDeduplication(unittest.TestCase):
    """UT-P-003: Two findings with identical titles keep only highest-scored."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_duplicate_titles_deduped(self):
        findings = [
            make_finding("f01", "retrieval", 0.5, title="Same Title", actor="other"),
            make_finding("f02", "retrieval", 0.5, title="Same Title", actor="anthropic"),
        ]
        result = run_prioritize(self.tmpdir, findings)
        self.assertEqual(result["total_output"], 1)
        # anthropic actor scores higher, so f02 survives
        self.assertEqual(result["findings"][0]["id"], "f02")


# ---------------------------------------------------------------------------
# UT-P-004: Top-N cutoff
# ---------------------------------------------------------------------------

class TestTopNCutoff(unittest.TestCase):
    """UT-P-004: --top-n 5 returns exactly 5 findings, sorted desc."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_top_n_cutoff(self):
        findings = [
            make_finding(f"f{i:02d}", "retrieval", 0.5 + i * 0.01)
            for i in range(10)
        ]
        result = run_prioritize(self.tmpdir, findings, top_n=5)
        self.assertEqual(result["total_output"], 5)
        self.assertEqual(result["total_input"], 10)

    def test_sorted_descending(self):
        findings = [
            make_finding(f"f{i:02d}", "retrieval", 0.5 + i * 0.01)
            for i in range(10)
        ]
        result = run_prioritize(self.tmpdir, findings, top_n=5)
        scores = [f["priority_score"] for f in result["findings"]]
        self.assertEqual(scores, sorted(scores, reverse=True))


# ---------------------------------------------------------------------------
# UT-P-005: Output schema
# ---------------------------------------------------------------------------

class TestOutputSchema(unittest.TestCase):
    """UT-P-005: Each finding has priority_score, priority_breakdown, expected_engines."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_enriched_fields_present(self):
        findings = [make_finding("f01", "retrieval", 0.9)]
        result = run_prioritize(self.tmpdir, findings)

        f = result["findings"][0]
        self.assertIn("priority_score", f)
        self.assertIn("priority_breakdown", f)
        self.assertIn("expected_engines", f)

    def test_breakdown_keys(self):
        findings = [make_finding("f01", "retrieval", 0.9)]
        result = run_prioritize(self.tmpdir, findings)

        breakdown = result["findings"][0]["priority_breakdown"]
        for key in ["relevance", "category_weight", "source_signal", "actor_relevance"]:
            self.assertIn(key, breakdown)

    def test_top_level_schema(self):
        findings = [make_finding("f01", "retrieval", 0.9)]
        result = run_prioritize(self.tmpdir, findings)

        for key in ["pipeline_version", "prioritized_at", "total_input",
                     "total_output", "findings"]:
            self.assertIn(key, result)


# ---------------------------------------------------------------------------
# UT-P-006: Unknown category excluded
# ---------------------------------------------------------------------------

class TestUnknownCategory(unittest.TestCase):
    """UT-P-006: Finding with unknown category excluded (no engine mapping)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_unknown_category_excluded(self):
        findings = [
            make_finding("f01", "retrieval", 0.9),
            make_finding("f02", "completely_unknown", 0.95),
        ]
        result = run_prioritize(self.tmpdir, findings)
        self.assertEqual(result["total_output"], 1)
        self.assertEqual(result["findings"][0]["id"], "f01")


# ---------------------------------------------------------------------------
# UT-P-007: Category engine weight
# ---------------------------------------------------------------------------

class TestCategoryEngineWeight(unittest.TestCase):
    """UT-P-007: retrieval (3 downstream) weights higher than security_change (0 downstream)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def test_retrieval_higher_weight_than_security(self):
        weights = pf.compute_category_engine_weights(CATEGORY_MAP, ENGINE_GRAPH)
        self.assertGreater(weights["retrieval"], weights["security_change"])

    def test_security_lowest_weight(self):
        weights = pf.compute_category_engine_weights(CATEGORY_MAP, ENGINE_GRAPH)
        # EncryptionEngine has no downstream engines (feeds=[])
        self.assertLessEqual(weights["security_change"], weights["retrieval"])


# ---------------------------------------------------------------------------
# UT-P-008: Actor relevance
# ---------------------------------------------------------------------------

class TestActorRelevance(unittest.TestCase):
    """UT-P-008: Major labs > academic > other."""

    def test_major_lab_score(self):
        finding = make_finding("f01", "retrieval", 0.5, actor="anthropic")
        self.assertEqual(pf.compute_actor_relevance(finding), 1.0)

    def test_openai_score(self):
        finding = make_finding("f01", "retrieval", 0.5, actor="openai")
        self.assertEqual(pf.compute_actor_relevance(finding), 1.0)

    def test_academic_score(self):
        finding = {"actor": "stanford", "actor_type": "academic", "source_url": ""}
        self.assertEqual(pf.compute_actor_relevance(finding), 0.5)

    def test_other_score(self):
        finding = {"actor": "random_startup", "actor_type": "", "source_url": ""}
        self.assertEqual(pf.compute_actor_relevance(finding), 0.3)

    def test_arxiv_url_academic(self):
        finding = {"actor": "unknown", "actor_type": "", "source_url": "https://arxiv.org/abs/2401.01234"}
        self.assertEqual(pf.compute_actor_relevance(finding), 0.5)


# ---------------------------------------------------------------------------
# UT-P-009: Source signal
# ---------------------------------------------------------------------------

class TestSourceSignal(unittest.TestCase):
    """UT-P-009: post_worthy > arxiv/github > rss."""

    def test_post_worthy(self):
        finding = {"post_worthy": True, "source_type": "rss", "source_url": ""}
        self.assertEqual(pf.compute_source_signal(finding), 1.0)

    def test_arxiv_source(self):
        finding = {"post_worthy": False, "source_type": "arxiv", "source_url": ""}
        self.assertEqual(pf.compute_source_signal(finding), 0.7)

    def test_github_source(self):
        finding = {"post_worthy": False, "source_type": "github", "source_url": ""}
        self.assertEqual(pf.compute_source_signal(finding), 0.7)

    def test_rss_source(self):
        finding = {"post_worthy": False, "source_type": "rss", "source_url": ""}
        self.assertEqual(pf.compute_source_signal(finding), 0.3)

    def test_github_url_detection(self):
        finding = {"post_worthy": False, "source_type": "", "source_url": "https://github.com/foo/bar"}
        self.assertEqual(pf.compute_source_signal(finding), 0.7)


# ---------------------------------------------------------------------------
# Expected engines
# ---------------------------------------------------------------------------

class TestExpectedEngines(unittest.TestCase):
    """Test expected engine computation."""

    def test_retrieval_includes_downstream(self):
        engines = pf.compute_expected_engines("retrieval", CATEGORY_MAP, ENGINE_GRAPH)
        self.assertIn("RAGEngine", engines)
        self.assertIn("OrchestrationEngine", engines)  # via feeds

    def test_security_no_downstream(self):
        engines = pf.compute_expected_engines("security_change", CATEGORY_MAP, ENGINE_GRAPH)
        self.assertIn("EncryptionEngine", engines)


if __name__ == "__main__":
    unittest.main()
