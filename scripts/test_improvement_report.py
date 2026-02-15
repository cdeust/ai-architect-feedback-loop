#!/usr/bin/env python3
"""
test_improvement_report.py — Tests for compose_improvement_report.py

Tests:
    UT-E5-IR1: engines_improved maps findings -> ports
    UT-E5-IR2: engines_unaffected lists untouched engines
    UT-E5-IR3: quality_impact includes baseline comparison
    UT-E5-IR4: pr_urls collected from stage10 summaries
    UT-E5-IR5: failed_findings includes issue URLs
    UT-E5-IR6: Markdown report has engine table
    UT-E5-IR7: Handles missing optional files gracefully

Usage:
    python3 -m unittest scripts/test_improvement_report.py -v
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

# Add scripts dir to path for import
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from compose_improvement_report import (
    collect_engines_improved,
    collect_failed_findings,
    collect_findings_summary,
    collect_pr_urls,
    collect_quality_impact,
    format_duration,
    generate_markdown,
)


class TestImprovementReport(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.tmpdir, "run")
        self.baselines_dir = os.path.join(self.tmpdir, "baselines")
        os.makedirs(self.run_dir)
        os.makedirs(self.baselines_dir)

        # Standard engine graph (9 engines)
        self.engine_graph = {
            "engines": {
                "EncryptionEngine": {"package_path": "packages/AIPRDEncryptionEngine"},
                "MetaPromptingEngine": {"package_path": "packages/AIPRDMetaPromptingEngine"},
                "OrchestrationEngine": {"package_path": "packages/AIPRDOrchestrationEngine"},
                "RAGEngine": {"package_path": "packages/AIPRDRAGEngine"},
                "SharedUtilities": {"package_path": "packages/AIPRDSharedUtilities"},
                "StrategyEngine": {"package_path": "packages/AIPRDStrategyEngine"},
                "VerificationEngine": {"package_path": "packages/AIPRDVerificationEngine"},
                "VisionEngine": {"package_path": "packages/AIPRDVisionEngine"},
                "VisionEngineApple": {"package_path": "packages/AIPRDVisionEngineApple"},
            }
        }

        # Standard category map
        self.category_map = {
            "mappings": {
                "retrieval": {
                    "primary_engines": ["RAGEngine"],
                    "related_ports": ["EmbeddingGeneratorPort", "VectorSearchPort"],
                },
                "verification": {
                    "primary_engines": ["VerificationEngine"],
                    "related_ports": ["VerificationEvidenceRepositoryPort"],
                },
                "cost_optimization": {
                    "primary_engines": ["OrchestrationEngine"],
                    "related_ports": ["TokenizerPort", "ContextCompressorPort"],
                },
            }
        }

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _write_json(self, path, data):
        with open(path, "w") as f:
            json.dump(data, f)

    # UT-E5-IR1: engines_improved maps findings -> ports
    def test_engines_improved_maps_findings_to_ports(self):
        """Findings should be mapped to engines and ports via category_engine_map."""
        # Impact report for a retrieval finding
        self._write_json(
            os.path.join(self.run_dir, "impact_report_tv-001.json"),
            {
                "finding_id": "tv-001",
                "category": "retrieval",
                "affected_engines": ["RAGEngine"],
                "affected_ports": ["EmbeddingGeneratorPort", "VectorSearchPort"],
            },
        )

        # Retry summary showing success
        self._write_json(
            os.path.join(self.run_dir, "retry_summary_tv-001.json"),
            {"finding_id": "tv-001", "result": "ACCEPTED", "attempts": 1},
        )

        # Stage 10 PR
        self._write_json(
            os.path.join(self.run_dir, "stage10_summary_tv-001.json"),
            {"finding_id": "tv-001", "pr_url": "https://github.com/test/repo/pull/42"},
        )

        engines_improved, _ = collect_engines_improved(
            self.run_dir, self.engine_graph, self.category_map
        )

        self.assertIn("RAGEngine", engines_improved)
        self.assertIn("tv-001", engines_improved["RAGEngine"]["findings"])
        self.assertIn("EmbeddingGeneratorPort", engines_improved["RAGEngine"]["ports_touched"])
        self.assertIn("VectorSearchPort", engines_improved["RAGEngine"]["ports_touched"])
        self.assertEqual(
            engines_improved["RAGEngine"]["pr_url"],
            "https://github.com/test/repo/pull/42",
        )

    # UT-E5-IR2: engines_unaffected lists untouched engines
    def test_engines_unaffected_lists_untouched_engines(self):
        """All 9 engines minus improved ones should appear in unaffected."""
        # Only RAGEngine was improved
        self._write_json(
            os.path.join(self.run_dir, "impact_report_tv-001.json"),
            {"finding_id": "tv-001", "category": "retrieval", "affected_engines": ["RAGEngine"], "affected_ports": []},
        )
        self._write_json(
            os.path.join(self.run_dir, "retry_summary_tv-001.json"),
            {"finding_id": "tv-001", "result": "ACCEPTED"},
        )

        _, engines_unaffected = collect_engines_improved(
            self.run_dir, self.engine_graph, self.category_map
        )

        self.assertEqual(len(engines_unaffected), 8)
        self.assertNotIn("RAGEngine", engines_unaffected)
        self.assertIn("VerificationEngine", engines_unaffected)
        self.assertIn("EncryptionEngine", engines_unaffected)
        self.assertIn("VisionEngine", engines_unaffected)

    # UT-E5-IR3: quality_impact includes baseline comparison
    def test_quality_impact_includes_baseline_comparison(self):
        """Should compare benchmark scores against baseline averages."""
        # Create baseline with metrics
        baseline_dir = os.path.join(self.baselines_dir, "auth_feature")
        os.makedirs(baseline_dir)
        self._write_json(
            os.path.join(baseline_dir, "metrics.json"),
            {
                "verification": {
                    "overall_score": 0.93,
                    "section_scores": {
                        "completeness": 0.91,
                        "accuracy": 0.93,
                        "consistency": 0.90,
                        "actionability": 0.89,
                    },
                }
            },
        )

        # Benchmark report with current scores
        self._write_json(
            os.path.join(self.run_dir, "benchmark_report.json"),
            {
                "result": "PASS",
                "scores": {
                    "completeness": 0.92,
                    "accuracy": 0.93,
                    "consistency": 0.91,
                    "actionability": 0.90,
                },
            },
        )

        quality = collect_quality_impact(self.run_dir, self.baselines_dir)

        self.assertEqual(quality["benchmark_result"], "PASS")
        self.assertFalse(quality["regression_detected"])
        self.assertIn("completeness", quality["dimensions"])
        self.assertEqual(quality["dimensions"]["completeness"]["baseline"], 0.91)
        self.assertEqual(quality["dimensions"]["completeness"]["current"], 0.92)

    # UT-E5-IR4: pr_urls collected from stage10 summaries
    def test_pr_urls_collected_from_stage10(self):
        """All PR URLs should be collected from stage10_summary files."""
        self._write_json(
            os.path.join(self.run_dir, "stage10_summary_tv-001.json"),
            {"pr_url": "https://github.com/test/repo/pull/42"},
        )
        self._write_json(
            os.path.join(self.run_dir, "stage10_summary_tv-003.json"),
            {"pr_url": "https://github.com/test/repo/pull/43"},
        )

        urls = collect_pr_urls(self.run_dir)

        self.assertEqual(len(urls), 2)
        self.assertIn("https://github.com/test/repo/pull/42", urls)
        self.assertIn("https://github.com/test/repo/pull/43", urls)

    # UT-E5-IR5: failed_findings includes issue URLs
    def test_failed_findings_includes_issue_urls(self):
        """Failed findings with EXHAUSTED result should include issue URLs."""
        self._write_json(
            os.path.join(self.run_dir, "retry_summary_tv-002.json"),
            {
                "finding_id": "tv-002",
                "result": "EXHAUSTED",
                "category": "verification",
                "failed_stage": "stage_7",
                "attempts": 3,
                "issue_url": "https://github.com/test/repo/issues/99",
            },
        )

        failed = collect_failed_findings(self.run_dir)

        self.assertEqual(len(failed), 1)
        self.assertEqual(failed[0]["finding_id"], "tv-002")
        self.assertEqual(failed[0]["attempts"], 3)
        self.assertEqual(
            failed[0]["issue_url"], "https://github.com/test/repo/issues/99"
        )

    # UT-E5-IR6: Markdown report has engine table
    def test_markdown_report_has_engine_table(self):
        """Markdown output should contain an engine improvement table."""
        report = {
            "timestamp": "2026-02-15T02:45:00Z",
            "findings_summary": {
                "total_found": 3,
                "prioritized": 3,
                "implemented": 2,
                "failed": 1,
                "prs_created": 2,
            },
            "engines_improved": {
                "RAGEngine": {
                    "findings": ["tv-001"],
                    "ports_touched": ["EmbeddingGeneratorPort"],
                    "pr_url": "https://github.com/test/repo/pull/42",
                }
            },
            "engines_unaffected": ["VerificationEngine"],
            "quality_impact": {
                "benchmark_result": "PASS",
                "dimensions": {
                    "completeness": {"baseline": 0.91, "current": 0.92, "delta": "+0.01"}
                },
                "regression_detected": False,
            },
            "architecture_compliance": {
                "enforcement_gates_passed": True,
                "deployment_verified": True,
            },
            "timing": {
                "total_seconds": 2700,
                "per_finding": {"tv-001": {"attempts": 1, "seconds": 450}},
                "warning_threshold_seconds": 18000,
                "duration_warning": False,
            },
            "pr_urls": ["https://github.com/test/repo/pull/42"],
            "failed_findings": [],
        }

        md = generate_markdown(report)

        self.assertIn("## Engines Improved", md)
        self.assertIn("RAGEngine", md)
        self.assertIn("EmbeddingGeneratorPort", md)
        self.assertIn("| Engine |", md)
        self.assertIn("## Quality Trend", md)
        self.assertIn("Completeness", md)

    # UT-E5-IR7: Handles missing optional files gracefully
    def test_handles_missing_optional_files(self):
        """Report should still generate when optional files are missing."""
        # Only create findings.json — no benchmark, no deployment, no stage10
        self._write_json(
            os.path.join(self.run_dir, "findings.json"),
            {"stats": {"filtered_findings": 0}, "findings": []},
        )

        summary = collect_findings_summary(self.run_dir)
        quality = collect_quality_impact(self.run_dir, self.baselines_dir)
        pr_urls = collect_pr_urls(self.run_dir)

        self.assertEqual(summary["total_found"], 0)
        self.assertEqual(quality["benchmark_result"], "UNKNOWN")
        self.assertEqual(len(pr_urls), 0)


class TestFormatDuration(unittest.TestCase):
    def test_seconds(self):
        self.assertEqual(format_duration(45), "45s")

    def test_minutes(self):
        self.assertEqual(format_duration(120), "2m")

    def test_hours(self):
        self.assertEqual(format_duration(3720), "1h 2m")


if __name__ == "__main__":
    unittest.main()
