#!/usr/bin/env python3
"""
Unit tests for generate_engine_graph.py (PIPE-E1-003)

Covers:
  AC-E1-008: Package.swift parsing (9 engines, correct edges)
  AC-E1-009: Override merging (feeds, fed_by, role fields)
  AC-E1-010: Cycle detection (injected cycle detected, exit 1)
  AC-E1-011: Output schema (all required keys present)

Uses temp directories with synthetic Package.swift files — no dependency
on the real codebase.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

# Import the module under test
sys.path.insert(0, os.path.dirname(__file__))
import generate_engine_graph as gen


# ---------------------------------------------------------------------------
# Helpers — synthetic Package.swift content
# ---------------------------------------------------------------------------

PACKAGE_TEMPLATES = {
    "AIPRDSharedUtilities": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDSharedUtilities",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDSharedUtilities", targets: ["AIPRDSharedUtilities"])],
    dependencies: [],
    targets: [.target(name: "AIPRDSharedUtilities", dependencies: [], path: "Sources")]
)
""",
    "AIPRDRAGEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDRAGEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDRAGEngine", targets: ["AIPRDRAGEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities")
    ],
    targets: [.target(name: "AIPRDRAGEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities")
    ], path: "Sources")]
)
""",
    "AIPRDVerificationEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDVerificationEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDVerificationEngine", targets: ["AIPRDVerificationEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities")
    ],
    targets: [.target(name: "AIPRDVerificationEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities")
    ], path: "Sources")]
)
""",
    "AIPRDStrategyEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDStrategyEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDStrategyEngine", targets: ["AIPRDStrategyEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities")
    ],
    targets: [.target(name: "AIPRDStrategyEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities")
    ], path: "Sources")]
)
""",
    "AIPRDEncryptionEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDEncryptionEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDEncryptionEngine", targets: ["AIPRDEncryptionEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities")
    ],
    targets: [.target(name: "AIPRDEncryptionEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities")
    ], path: "Sources")]
)
""",
    "AIPRDVisionEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDVisionEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDVisionEngine", targets: ["AIPRDVisionEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "0.30.0")
    ],
    targets: [.target(name: "AIPRDVisionEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities"),
        .product(name: "AWSBedrockRuntime", package: "aws-sdk-swift")
    ], path: "Sources")]
)
""",
    "AIPRDMetaPromptingEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDMetaPromptingEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDMetaPromptingEngine", targets: ["AIPRDMetaPromptingEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities"),
        .package(path: "../AIPRDRAGEngine")
    ],
    targets: [.target(name: "AIPRDMetaPromptingEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities"),
        .product(name: "AIPRDRAGEngine", package: "AIPRDRAGEngine")
    ], path: "Sources")]
)
""",
    "AIPRDVisionEngineApple": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDVisionEngineApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDVisionEngineApple", targets: ["AIPRDVisionEngineApple"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities"),
        .package(path: "../AIPRDVisionEngine")
    ],
    targets: [.target(name: "AIPRDVisionEngineApple", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities"),
        .product(name: "AIPRDVisionEngine", package: "AIPRDVisionEngine")
    ], path: "Sources")]
)
""",
    "AIPRDOrchestrationEngine": """\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AIPRDOrchestrationEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIPRDOrchestrationEngine", targets: ["AIPRDOrchestrationEngine"])],
    dependencies: [
        .package(path: "../AIPRDSharedUtilities"),
        .package(path: "../AIPRDRAGEngine"),
        .package(path: "../AIPRDVerificationEngine"),
        .package(path: "../AIPRDMetaPromptingEngine"),
        .package(path: "../AIPRDStrategyEngine")
    ],
    targets: [.target(name: "AIPRDOrchestrationEngine", dependencies: [
        .product(name: "AIPRDSharedUtilities", package: "AIPRDSharedUtilities"),
        .product(name: "AIPRDRAGEngine", package: "AIPRDRAGEngine"),
        .product(name: "AIPRDVerificationEngine", package: "AIPRDVerificationEngine"),
        .product(name: "AIPRDMetaPromptingEngine", package: "AIPRDMetaPromptingEngine"),
        .product(name: "AIPRDStrategyEngine", package: "AIPRDStrategyEngine")
    ], path: "Sources")]
)
""",
}


def create_synthetic_packages(tmpdir):
    """Create a packages/ dir with all 9 synthetic Package.swift files."""
    packages_dir = os.path.join(tmpdir, "packages")
    for pkg_name, content in PACKAGE_TEMPLATES.items():
        pkg_dir = os.path.join(packages_dir, pkg_name)
        os.makedirs(pkg_dir, exist_ok=True)
        with open(os.path.join(pkg_dir, "Package.swift"), "w") as f:
            f.write(content)
    return packages_dir


def create_overrides(tmpdir):
    """Create a sample overrides file matching the real project structure."""
    overrides = {
        "description": "Test overrides",
        "engines": {
            "SharedUtilities": {
                "role": "common_infrastructure",
                "feeds": ["RAGEngine", "VerificationEngine"],
                "fed_by": [],
            },
            "RAGEngine": {
                "role": "retrieval",
                "feeds": ["OrchestrationEngine"],
                "fed_by": ["SharedUtilities"],
            },
        },
    }
    path = os.path.join(tmpdir, "overrides.json")
    with open(path, "w") as f:
        json.dump(overrides, f)
    return path


# ---------------------------------------------------------------------------
# AC-E1-008: Package.swift parsing
# ---------------------------------------------------------------------------

class TestPackageParsing(unittest.TestCase):
    """AC-E1-008: Parse 9 Package.swift files → all engines present with correct edges."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.packages_dir = create_synthetic_packages(self.tmpdir)

    def test_discovers_all_9_packages(self):
        files = gen.discover_packages(self.packages_dir)
        self.assertEqual(len(files), 9)

    def test_parses_package_name(self):
        filepath = os.path.join(
            self.packages_dir, "AIPRDSharedUtilities", "Package.swift"
        )
        name, deps = gen.parse_package_swift(filepath)
        self.assertEqual(name, "AIPRDSharedUtilities")
        self.assertEqual(deps, [])

    def test_parses_local_dependencies(self):
        filepath = os.path.join(
            self.packages_dir, "AIPRDOrchestrationEngine", "Package.swift"
        )
        name, deps = gen.parse_package_swift(filepath)
        self.assertEqual(name, "AIPRDOrchestrationEngine")
        self.assertEqual(sorted(deps), [
            "AIPRDMetaPromptingEngine",
            "AIPRDRAGEngine",
            "AIPRDSharedUtilities",
            "AIPRDStrategyEngine",
            "AIPRDVerificationEngine",
        ])

    def test_ignores_url_dependencies(self):
        filepath = os.path.join(
            self.packages_dir, "AIPRDVisionEngine", "Package.swift"
        )
        name, deps = gen.parse_package_swift(filepath)
        self.assertEqual(name, "AIPRDVisionEngine")
        # Only local dep, URL dep (aws-sdk-swift) excluded
        self.assertEqual(deps, ["AIPRDSharedUtilities"])

    def test_build_graph_all_engines(self):
        engines = gen.build_graph(self.packages_dir)
        self.assertEqual(len(engines), 9)
        expected_names = {
            "SharedUtilities", "RAGEngine", "VerificationEngine",
            "StrategyEngine", "EncryptionEngine", "VisionEngine",
            "MetaPromptingEngine", "VisionEngineApple", "OrchestrationEngine",
        }
        self.assertEqual(set(engines.keys()), expected_names)

    def test_shared_utilities_has_no_deps(self):
        engines = gen.build_graph(self.packages_dir)
        self.assertEqual(engines["SharedUtilities"]["depends_on"], [])

    def test_shared_utilities_depended_by_all(self):
        engines = gen.build_graph(self.packages_dir)
        # Every engine except SharedUtilities depends on it
        depended_by = engines["SharedUtilities"]["depended_by"]
        self.assertEqual(len(depended_by), 8)

    def test_orchestration_depends_on_5(self):
        engines = gen.build_graph(self.packages_dir)
        deps = engines["OrchestrationEngine"]["depends_on"]
        self.assertEqual(sorted(deps), [
            "MetaPromptingEngine", "RAGEngine", "SharedUtilities",
            "StrategyEngine", "VerificationEngine",
        ])

    def test_meta_prompting_depends_on_shared_and_rag(self):
        engines = gen.build_graph(self.packages_dir)
        deps = engines["MetaPromptingEngine"]["depends_on"]
        self.assertEqual(sorted(deps), ["RAGEngine", "SharedUtilities"])

    def test_vision_engine_apple_depends_on_shared_and_vision(self):
        engines = gen.build_graph(self.packages_dir)
        deps = engines["VisionEngineApple"]["depends_on"]
        self.assertEqual(sorted(deps), ["SharedUtilities", "VisionEngine"])

    def test_edge_count_is_14(self):
        engines = gen.build_graph(self.packages_dir)
        edge_count = sum(len(d["depends_on"]) for d in engines.values())
        self.assertEqual(edge_count, 14)


# ---------------------------------------------------------------------------
# AC-E1-009: Override merging
# ---------------------------------------------------------------------------

class TestOverrideMerging(unittest.TestCase):
    """AC-E1-009: Override merging adds feeds/fed_by/role fields."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.packages_dir = create_synthetic_packages(self.tmpdir)

    def test_merge_adds_feeds_and_role(self):
        engines = gen.build_graph(self.packages_dir)
        overrides = {
            "SharedUtilities": {
                "role": "common_infrastructure",
                "feeds": ["RAGEngine", "VerificationEngine"],
                "fed_by": [],
            },
        }
        engines = gen.merge_overrides(engines, overrides)
        su = engines["SharedUtilities"]
        self.assertEqual(su["role"], "common_infrastructure")
        self.assertEqual(su["feeds"], ["RAGEngine", "VerificationEngine"])
        self.assertEqual(su["fed_by"], [])

    def test_merge_preserves_depends_on(self):
        engines = gen.build_graph(self.packages_dir)
        overrides = {
            "OrchestrationEngine": {
                "role": "orchestration",
                "feeds": [],
                "fed_by": ["SharedUtilities"],
            },
        }
        engines = gen.merge_overrides(engines, overrides)
        oe = engines["OrchestrationEngine"]
        # depends_on from Package.swift should be untouched
        self.assertIn("RAGEngine", oe["depends_on"])
        # override fields merged
        self.assertEqual(oe["role"], "orchestration")

    def test_all_engines_have_feeds_fed_by_role_after_merge(self):
        engines = gen.build_graph(self.packages_dir)
        engines = gen.merge_overrides(engines, {})
        for name, data in engines.items():
            self.assertIn("feeds", data, f"{name} missing feeds")
            self.assertIn("fed_by", data, f"{name} missing fed_by")
            self.assertIn("role", data, f"{name} missing role")

    def test_override_file_loading(self):
        overrides_path = create_overrides(self.tmpdir)
        overrides = gen.load_overrides(overrides_path)
        self.assertIn("SharedUtilities", overrides)
        self.assertEqual(overrides["SharedUtilities"]["role"], "common_infrastructure")

    def test_nonexistent_override_returns_empty(self):
        overrides = gen.load_overrides("/nonexistent/path.json")
        self.assertEqual(overrides, {})

    def test_override_for_unknown_engine_adds_entry(self):
        engines = gen.build_graph(self.packages_dir)
        overrides = {
            "PromptEngine": {
                "role": "prompting",
                "feeds": ["OrchestrationEngine"],
                "fed_by": ["SharedUtilities"],
            },
        }
        engines = gen.merge_overrides(engines, overrides)
        self.assertIn("PromptEngine", engines)
        self.assertEqual(engines["PromptEngine"]["role"], "prompting")


# ---------------------------------------------------------------------------
# AC-E1-010: Cycle detection
# ---------------------------------------------------------------------------

class TestCycleDetection(unittest.TestCase):
    """AC-E1-010: Injected cycle (A→B→C→A) → detected with cycle path."""

    def test_no_cycles_in_valid_graph(self):
        engines = {
            "A": {"depends_on": []},
            "B": {"depends_on": ["A"]},
            "C": {"depends_on": ["A", "B"]},
        }
        cycles = gen.detect_cycles(engines)
        self.assertEqual(len(cycles), 0)

    def test_detects_simple_cycle(self):
        engines = {
            "A": {"depends_on": ["C"]},
            "B": {"depends_on": ["A"]},
            "C": {"depends_on": ["B"]},
        }
        cycles = gen.detect_cycles(engines)
        self.assertGreater(len(cycles), 0)

    def test_cycle_path_contains_all_nodes(self):
        engines = {
            "A": {"depends_on": ["C"]},
            "B": {"depends_on": ["A"]},
            "C": {"depends_on": ["B"]},
        }
        cycles = gen.detect_cycles(engines)
        # At least one cycle should contain all three nodes
        cycle_nodes = set()
        for cycle in cycles:
            cycle_nodes.update(cycle)
        self.assertTrue({"A", "B", "C"}.issubset(cycle_nodes))

    def test_detects_self_cycle(self):
        engines = {
            "A": {"depends_on": ["A"]},
        }
        cycles = gen.detect_cycles(engines)
        self.assertGreater(len(cycles), 0)

    def test_no_cycles_in_real_package_graph(self):
        tmpdir = tempfile.mkdtemp()
        packages_dir = create_synthetic_packages(tmpdir)
        engines = gen.build_graph(packages_dir)
        cycles = gen.detect_cycles(engines)
        self.assertEqual(len(cycles), 0)

    def test_script_exits_1_on_cycle(self):
        """Integration: run the script with a cyclic Package.swift setup."""
        tmpdir = tempfile.mkdtemp()

        # Create two packages that depend on each other
        packages_dir = os.path.join(tmpdir, "packages")
        for pkg_name, dep_name in [("AIPRDAlpha", "AIPRDBeta"), ("AIPRDBeta", "AIPRDAlpha")]:
            pkg_dir = os.path.join(packages_dir, pkg_name)
            os.makedirs(pkg_dir, exist_ok=True)
            content = f"""\
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "{pkg_name}",
    dependencies: [.package(path: "../{dep_name}")],
    targets: [.target(name: "{pkg_name}", dependencies: [
        .product(name: "{dep_name}", package: "{dep_name}")
    ])]
)
"""
            with open(os.path.join(pkg_dir, "Package.swift"), "w") as f:
                f.write(content)

        output_path = os.path.join(tmpdir, "graph.json")
        script = os.path.join(os.path.dirname(__file__), "generate_engine_graph.py")
        result = subprocess.run(
            [sys.executable, script,
             "--packages-dir", packages_dir,
             "--output", output_path],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("Cycle", result.stderr)


# ---------------------------------------------------------------------------
# AC-E1-011: Output schema
# ---------------------------------------------------------------------------

class TestOutputSchema(unittest.TestCase):
    """AC-E1-011: Output matches expected schema (all required keys present)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.packages_dir = create_synthetic_packages(self.tmpdir)
        self.overrides_path = create_overrides(self.tmpdir)
        self.output_path = os.path.join(self.tmpdir, "engine_graph.json")

    def _generate(self):
        """Run main() to produce output file."""
        gen.main([
            "--packages-dir", self.packages_dir,
            "--overrides", self.overrides_path,
            "--output", self.output_path,
        ])
        with open(self.output_path) as f:
            return json.load(f)

    def test_top_level_keys(self):
        data = self._generate()
        for key in ["generated_at", "generator_version", "source", "engines", "stats"]:
            self.assertIn(key, data, f"Missing top-level key: {key}")

    def test_generator_version(self):
        data = self._generate()
        self.assertEqual(data["generator_version"], "1.0")

    def test_source_value(self):
        data = self._generate()
        self.assertEqual(data["source"], "Package.swift + overrides")

    def test_stats_keys(self):
        data = self._generate()
        stats = data["stats"]
        for key in ["engine_count", "edge_count", "max_depth", "cycles_detected"]:
            self.assertIn(key, stats, f"Missing stats key: {key}")

    def test_stats_values(self):
        data = self._generate()
        stats = data["stats"]
        self.assertEqual(stats["engine_count"], 9)
        self.assertEqual(stats["edge_count"], 14)
        self.assertEqual(stats["max_depth"], 3)
        self.assertEqual(stats["cycles_detected"], 0)

    def test_engine_entry_keys(self):
        data = self._generate()
        for name, engine in data["engines"].items():
            for key in ["package_path", "depends_on", "depended_by", "feeds", "fed_by", "role"]:
                self.assertIn(key, engine, f"Engine {name} missing key: {key}")

    def test_generated_at_is_iso(self):
        data = self._generate()
        ts = data["generated_at"]
        self.assertTrue(ts.endswith("Z"), f"Timestamp not UTC: {ts}")
        self.assertRegex(ts, r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")

    def test_max_depth_is_3(self):
        """OrchestrationEngine -> MetaPromptingEngine -> RAGEngine -> SharedUtilities = depth 3."""
        data = self._generate()
        self.assertEqual(data["stats"]["max_depth"], 3)

    def test_output_is_valid_json_file(self):
        self._generate()
        with open(self.output_path) as f:
            data = json.load(f)
        self.assertIsInstance(data, dict)


# ---------------------------------------------------------------------------
# Utility function tests
# ---------------------------------------------------------------------------

class TestUtilities(unittest.TestCase):
    """Test helper functions."""

    def test_strip_prefix(self):
        self.assertEqual(gen.strip_prefix("AIPRDSharedUtilities"), "SharedUtilities")
        self.assertEqual(gen.strip_prefix("AIPRDRAGEngine"), "RAGEngine")
        self.assertEqual(gen.strip_prefix("PlainName"), "PlainName")

    def test_compute_max_depth_empty(self):
        self.assertEqual(gen.compute_max_depth({}), 0)

    def test_compute_max_depth_linear(self):
        engines = {
            "A": {"depends_on": []},
            "B": {"depends_on": ["A"]},
            "C": {"depends_on": ["B"]},
        }
        self.assertEqual(gen.compute_max_depth(engines), 2)

    def test_compute_max_depth_diamond(self):
        engines = {
            "A": {"depends_on": []},
            "B": {"depends_on": ["A"]},
            "C": {"depends_on": ["A"]},
            "D": {"depends_on": ["B", "C"]},
        }
        self.assertEqual(gen.compute_max_depth(engines), 2)


if __name__ == "__main__":
    unittest.main()
