#!/usr/bin/env python3
"""
Unit tests for extract_contracts.py (PIPE-E2-002)

Covers:
  UT-EC-001: Parse public protocol declarations
  UT-EC-002: Parse public struct/enum declarations
  UT-EC-003: Extract methods from protocol body
  UT-EC-004: Engine filter — --engines RAGEngine returns only RAG contracts
  UT-EC-005: Markdown format has engine section headers
  UT-EC-006: JSON format has engines.ENGINE.protocols array
  UT-EC-007: Ports-only mode
  UT-EC-008: Nested protocol edge case
  UT-EC-009: Discover engines from AIPRD-prefixed directories

Uses synthetic Swift files — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import extract_contracts as ec


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def create_engine_package(tmpdir, engine_name, swift_files):
    """Create a synthetic engine package with Swift files.

    swift_files: dict mapping relative path to content.
    """
    pkg_dir = os.path.join(tmpdir, f"AIPRD{engine_name}")
    for rel_path, content in swift_files.items():
        full_path = os.path.join(pkg_dir, rel_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "w") as f:
            f.write(content)
    return pkg_dir


def create_minimal_packages(tmpdir):
    """Create minimal package structure for testing."""
    # SharedUtilities with ports
    create_engine_package(tmpdir, "SharedUtilities", {
        "Sources/Domain/Ports/EmbeddingGeneratorPort.swift": """\
import Foundation

public protocol EmbeddingGeneratorPort {
    func generateEmbedding(for text: String) async throws -> [Float]
    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]]
}
""",
        "Sources/Domain/Ports/VectorSearchPort.swift": """\
public protocol VectorSearchPort {
    func search(query: [Float], topK: Int) async throws -> [SearchResult]
}
""",
        "Sources/Domain/Models/SearchResult.swift": """\
public struct SearchResult {
    public let id: String
    public let score: Float
    public let content: String
}
""",
    })

    # RAGEngine
    create_engine_package(tmpdir, "RAGEngine", {
        "Sources/RAGEngineProtocol.swift": """\
public protocol RAGEngineProtocol {
    func retrieveContext(query: String, maxResults: Int) async throws -> RAGResult
}

public struct RAGResult {
    public let chunks: [String]
    public let scores: [Float]
}
""",
        "Sources/Internal/InternalHelper.swift": """\
struct InternalHelper {
    func doStuff() {}
}
""",
    })

    # VerificationEngine
    create_engine_package(tmpdir, "VerificationEngine", {
        "Sources/VerificationEngineProtocol.swift": """\
public protocol VerificationEngineProtocol {
    func verify(section: String) async throws -> VerificationResult
}

public enum VerificationResult {
    case passed
    case failed(reason: String)
}
""",
    })

    return tmpdir


# ---------------------------------------------------------------------------
# UT-EC-001: Parse public protocol declarations
# ---------------------------------------------------------------------------

class TestProtocolParsing(unittest.TestCase):
    """UT-EC-001: Parse public protocol declarations."""

    def test_parses_public_protocol(self):
        content = """\
public protocol FooPort {
    func doSomething() async throws -> String
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "FooPort.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["protocols"]), 1)
        self.assertEqual(result["protocols"][0]["name"], "FooPort")

    def test_parses_protocol_without_public(self):
        content = """\
protocol InternalProtocol {
    func internalMethod() -> Bool
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "Internal.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["protocols"]), 1)

    def test_parses_protocol_with_inheritance(self):
        content = """\
public protocol AdvancedPort: Sendable, Hashable {
    func compute(input: Int) -> Int
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "Advanced.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["protocols"]), 1)
        self.assertEqual(result["protocols"][0]["name"], "AdvancedPort")


# ---------------------------------------------------------------------------
# UT-EC-002: Parse public struct/enum
# ---------------------------------------------------------------------------

class TestTypesParsing(unittest.TestCase):
    """UT-EC-002: Parse public struct and enum declarations."""

    def test_parses_public_struct(self):
        content = """\
public struct MyResult {
    public let value: String
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "MyResult.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["structs"]), 1)
        self.assertEqual(result["structs"][0]["name"], "MyResult")

    def test_parses_public_enum(self):
        content = """\
public enum Status {
    case active
    case inactive
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "Status.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["enums"]), 1)
        self.assertEqual(result["enums"][0]["name"], "Status")

    def test_ignores_internal_struct(self):
        content = """\
struct InternalThing {
    let x: Int
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "Internal.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["structs"]), 0)


# ---------------------------------------------------------------------------
# UT-EC-003: Extract methods from protocol body
# ---------------------------------------------------------------------------

class TestMethodExtraction(unittest.TestCase):
    """UT-EC-003: Extract method names from protocol body."""

    def test_extracts_method_names(self):
        content = """\
public protocol SearchPort {
    func search(query: String) async throws -> [Result]
    func index(document: Document) async throws
    var isReady: Bool { get }
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "SearchPort.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        methods = result["protocols"][0]["methods"]
        self.assertIn("search", methods)
        self.assertIn("index", methods)

    def test_extracts_properties(self):
        content = """\
public protocol ConfigPort {
    var isEnabled: Bool { get }
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "ConfigPort.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        props = result["protocols"][0]["properties"]
        self.assertIn("isEnabled", props)


# ---------------------------------------------------------------------------
# UT-EC-004: Engine filter
# ---------------------------------------------------------------------------

class TestEngineFilter(unittest.TestCase):
    """UT-EC-004: --engines RAGEngine returns only RAG contracts."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        create_minimal_packages(self.tmpdir)

    def test_filter_single_engine(self):
        data, _ = ec.extract_all(self.tmpdir, engine_filter=["RAGEngine"],
                                 language="swift", module_prefix="AIPRD",
                                 source_extensions=[".swift"])
        self.assertIn("RAGEngine", data)
        self.assertNotIn("VerificationEngine", data)
        self.assertNotIn("SharedUtilities", data)

    def test_filter_includes_shared(self):
        data, _ = ec.extract_all(self.tmpdir, engine_filter=["SharedUtilities"],
                                 language="swift", module_prefix="AIPRD",
                                 source_extensions=[".swift"],
                                 domain_module="SharedUtilities")
        self.assertIn("SharedUtilities", data)
        self.assertNotIn("RAGEngine", data)


# ---------------------------------------------------------------------------
# UT-EC-005: Markdown format
# ---------------------------------------------------------------------------

class TestMarkdownFormat(unittest.TestCase):
    """UT-EC-005: Markdown contains engine section headers."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        create_minimal_packages(self.tmpdir)

    def test_has_engine_headers(self):
        data, _ = ec.extract_all(self.tmpdir, language="swift",
                                 module_prefix="AIPRD",
                                 source_extensions=[".swift"],
                                 domain_module="SharedUtilities")
        md = ec.format_markdown(data, "swift")
        self.assertIn("## SharedUtilities", md)
        self.assertIn("## RAGEngine", md)

    def test_has_code_blocks(self):
        data, _ = ec.extract_all(self.tmpdir, language="swift",
                                 module_prefix="AIPRD",
                                 source_extensions=[".swift"],
                                 domain_module="SharedUtilities")
        md = ec.format_markdown(data, "swift")
        self.assertIn("```swift", md)


# ---------------------------------------------------------------------------
# UT-EC-006: JSON format
# ---------------------------------------------------------------------------

class TestJsonFormat(unittest.TestCase):
    """UT-EC-006: JSON has engines.ENGINE.protocols array."""

    EXTRACT_KWARGS = {
        "language": "swift", "module_prefix": "AIPRD",
        "source_extensions": [".swift"], "domain_module": "SharedUtilities",
    }

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        create_minimal_packages(self.tmpdir)

    def test_json_structure(self):
        data, count = ec.extract_all(self.tmpdir, **self.EXTRACT_KWARGS)
        output = ec.format_json(data, count)

        self.assertIn("extracted_at", output)
        self.assertIn("packages_scanned", output)
        self.assertIn("engines", output)
        self.assertIn("SharedUtilities", output["engines"])

    def test_shared_utilities_has_ports(self):
        data, count = ec.extract_all(self.tmpdir, **self.EXTRACT_KWARGS)
        output = ec.format_json(data, count)

        su = output["engines"]["SharedUtilities"]
        self.assertIn("ports", su)
        port_names = [p["protocol"] for p in su["ports"]]
        self.assertIn("EmbeddingGeneratorPort", port_names)

    def test_rag_engine_has_protocols(self):
        data, count = ec.extract_all(self.tmpdir, **self.EXTRACT_KWARGS)
        output = ec.format_json(data, count)

        rag = output["engines"]["RAGEngine"]
        self.assertIn("protocols", rag)
        proto_names = [p["protocol"] for p in rag["protocols"]]
        self.assertIn("RAGEngineProtocol", proto_names)


# ---------------------------------------------------------------------------
# UT-EC-007: Ports-only mode
# ---------------------------------------------------------------------------

class TestPortsOnly(unittest.TestCase):
    """UT-EC-007: --ports-only returns only SharedUtilities ports."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        create_minimal_packages(self.tmpdir)

    def test_ports_only_excludes_engines(self):
        data, _ = ec.extract_all(self.tmpdir, ports_only=True,
                                 language="swift", module_prefix="AIPRD",
                                 source_extensions=[".swift"],
                                 domain_module="SharedUtilities")
        self.assertIn("SharedUtilities", data)
        self.assertNotIn("RAGEngine", data)
        self.assertNotIn("VerificationEngine", data)


# ---------------------------------------------------------------------------
# UT-EC-008: Nested protocol edge case
# ---------------------------------------------------------------------------

class TestEdgeCases(unittest.TestCase):
    """UT-EC-008: Edge cases in Swift parsing."""

    def test_multiple_protocols_same_file(self):
        content = """\
public protocol AlphaPort {
    func alpha() -> Int
}

public protocol BetaPort {
    func beta() -> String
}
"""
        tmpdir = tempfile.mkdtemp()
        filepath = os.path.join(tmpdir, "Multi.swift")
        with open(filepath, "w") as f:
            f.write(content)

        result = ec.parse_swift_file(filepath)
        self.assertEqual(len(result["protocols"]), 2)
        names = {p["name"] for p in result["protocols"]}
        self.assertEqual(names, {"AlphaPort", "BetaPort"})

    def test_nonexistent_file(self):
        result = ec.parse_swift_file("/nonexistent/path.swift")
        self.assertEqual(result["protocols"], [])
        self.assertEqual(result["structs"], [])


# ---------------------------------------------------------------------------
# UT-EC-009: Discover engines
# ---------------------------------------------------------------------------

class TestDiscoverEngines(unittest.TestCase):
    """UT-EC-009: Discover engine directories with module prefix."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        create_minimal_packages(self.tmpdir)

    def test_discovers_engines_with_prefix(self):
        engines = ec.discover_engines(self.tmpdir, module_prefix="AIPRD")
        self.assertIn("SharedUtilities", engines)
        self.assertIn("RAGEngine", engines)
        self.assertIn("VerificationEngine", engines)

    def test_discovers_engines_without_prefix(self):
        engines = ec.discover_engines(self.tmpdir)
        # Without prefix stripping, full directory names are used
        self.assertIn("AIPRDSharedUtilities", engines)
        self.assertIn("AIPRDRAGEngine", engines)


if __name__ == "__main__":
    unittest.main()
