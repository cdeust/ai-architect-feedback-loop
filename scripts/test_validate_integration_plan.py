#!/usr/bin/env python3
"""
Unit tests for validate_integration_plan.py (PIPE-E2-004)

Covers:
  UT-VIP-001: ACCEPTED — 3-engine plan with cross-engine touchpoints
  UT-VIP-002: REJECTED — new_files contains non-test .swift file
  UT-VIP-003: REJECTED — affected_engines lists 3 but modifications only covers 2
  UT-VIP-004: REJECTED — zero cross-engine touchpoints
  UT-VIP-005: REJECTED — modifications file doesn't exist
  UT-VIP-006: REJECTED — contract changes reference fake protocol
  UT-VIP-007: REJECTED — port protocol change without SharedUtilities modification
  UT-VIP-008: Constraint flags — false flags rejected
  UT-VIP-009: Test file location — misplaced test files

Uses synthetic data — no external dependencies.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import validate_integration_plan as vip


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def make_valid_plan():
    """Create a valid integration plan."""
    return {
        "finding_id": "tv-001",
        "affected_engines": ["RAGEngine", "MetaPromptingEngine", "OrchestrationEngine"],
        "modifications": [
            {
                "engine": "RAGEngine",
                "files": [
                    {"path": "packages/AIPRDRAGEngine/Sources/Retrieval/BM25.swift",
                     "action": "modify", "description": "Update scoring"},
                ],
                "contract_changes": [],
            },
            {
                "engine": "MetaPromptingEngine",
                "files": [
                    {"path": "packages/AIPRDMetaPromptingEngine/Sources/Strategy/Selector.swift",
                     "action": "modify", "description": "Use new scores"},
                ],
                "contract_changes": [],
            },
            {
                "engine": "OrchestrationEngine",
                "files": [
                    {"path": "packages/AIPRDOrchestrationEngine/Sources/Pipeline/Context.swift",
                     "action": "modify", "description": "Pass new params"},
                ],
                "contract_changes": [],
            },
        ],
        "cross_engine_touchpoints": [
            {"from": "RAGEngine", "to": "MetaPromptingEngine",
             "via": "RAGEngineProtocol", "description": "New weighted results"},
            {"from": "RAGEngine", "to": "OrchestrationEngine",
             "via": "RAGEngineProtocol", "description": "Updated context"},
        ],
        "new_files": [],
        "test_files": ["packages/AIPRDRAGEngine/Tests/BM25Tests.swift"],
        "constraints": {
            "no_new_packages": True,
            "no_standalone_modules": True,
            "existing_dependency_graph_only": True,
        },
    }


CONTRACTS = {
    "engines": {
        "SharedUtilities": {
            "ports": [
                {"protocol": "EmbeddingGeneratorPort", "methods": ["generateEmbedding"]},
                {"protocol": "VectorSearchPort", "methods": ["search"]},
            ],
        },
        "RAGEngine": {
            "protocols": [
                {"protocol": "RAGEngineProtocol", "methods": ["retrieveContext"]},
            ],
            "public_types": [],
        },
    },
}


# ---------------------------------------------------------------------------
# UT-VIP-001: ACCEPTED
# ---------------------------------------------------------------------------

class TestAccepted(unittest.TestCase):
    """UT-VIP-001: Valid 3-engine plan accepted."""

    def test_valid_plan_accepted(self):
        plan = make_valid_plan()
        result, checks = vip.validate(plan)
        self.assertEqual(result, "ACCEPTED")

    def test_all_checks_pass(self):
        plan = make_valid_plan()
        _, checks = vip.validate(plan)
        failures = [c for c in checks if c["result"] == "FAIL"]
        self.assertEqual(len(failures), 0)


# ---------------------------------------------------------------------------
# UT-VIP-002: REJECTED — new source files
# ---------------------------------------------------------------------------

class TestRejectedNewFiles(unittest.TestCase):
    """UT-VIP-002: Non-test new files rejected."""

    def test_new_source_file_rejected(self):
        plan = make_valid_plan()
        plan["new_files"] = ["packages/AIPRDRAGEngine/Sources/NewModule.swift"]

        result, checks = vip.validate(plan)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "no_new_source_files")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("Non-test new files", check["reason"])

    def test_new_test_file_accepted(self):
        plan = make_valid_plan()
        plan["new_files"] = ["packages/AIPRDRAGEngine/Tests/NewTest.swift"]

        result, checks = vip.validate(plan)
        check = next(c for c in checks if c["check"] == "no_new_source_files")
        self.assertEqual(check["result"], "PASS")


# ---------------------------------------------------------------------------
# UT-VIP-003: REJECTED — missing engine modifications
# ---------------------------------------------------------------------------

class TestRejectedMissingMods(unittest.TestCase):
    """UT-VIP-003: Not all affected engines have modifications."""

    def test_missing_engine_modification(self):
        plan = make_valid_plan()
        # Remove OrchestrationEngine modification
        plan["modifications"] = [m for m in plan["modifications"]
                                 if m["engine"] != "OrchestrationEngine"]

        result, checks = vip.validate(plan)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "all_engines_modified")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("OrchestrationEngine", check["reason"])


# ---------------------------------------------------------------------------
# UT-VIP-004: REJECTED — zero cross-engine touchpoints
# ---------------------------------------------------------------------------

class TestRejectedNoTouchpoints(unittest.TestCase):
    """UT-VIP-004: Zero cross-engine touchpoints."""

    def test_no_touchpoints_rejected(self):
        plan = make_valid_plan()
        plan["cross_engine_touchpoints"] = []

        result, checks = vip.validate(plan)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "cross_engine_connections")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("single-engine", check["reason"])


# ---------------------------------------------------------------------------
# UT-VIP-005: REJECTED — non-existent file
# ---------------------------------------------------------------------------

class TestRejectedFakeFile(unittest.TestCase):
    """UT-VIP-005: Modified file doesn't exist in product."""

    def test_nonexistent_file_rejected(self):
        plan = make_valid_plan()
        # Create a temp packages dir without the file
        tmpdir = tempfile.mkdtemp()
        os.makedirs(os.path.join(tmpdir, "AIPRDRAGEngine", "Sources"), exist_ok=True)

        result, checks = vip.validate(plan, packages_dir=tmpdir)
        check = next(c for c in checks if c["check"] == "files_exist")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("Non-existent files", check["reason"])


# ---------------------------------------------------------------------------
# UT-VIP-006: REJECTED — fake protocol
# ---------------------------------------------------------------------------

class TestRejectedFakeProtocol(unittest.TestCase):
    """UT-VIP-006: Contract changes reference non-existent protocol."""

    def test_fake_protocol_rejected(self):
        plan = make_valid_plan()
        plan["modifications"][0]["contract_changes"] = [
            {"protocol": "NonExistentProtocol", "change": "add method",
             "description": "Fake"}
        ]

        result, checks = vip.validate(plan, contracts=CONTRACTS)
        check = next(c for c in checks if c["check"] == "contract_references")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("NonExistentProtocol", check["reason"])

    def test_valid_protocol_passes(self):
        plan = make_valid_plan()
        plan["modifications"][0]["contract_changes"] = [
            {"protocol": "RAGEngineProtocol", "change": "add method",
             "description": "Valid"}
        ]

        _, checks = vip.validate(plan, contracts=CONTRACTS)
        check = next(c for c in checks if c["check"] == "contract_references")
        self.assertEqual(check["result"], "PASS")


# ---------------------------------------------------------------------------
# UT-VIP-007: REJECTED — port change without SharedUtilities
# ---------------------------------------------------------------------------

class TestRejectedPortLocation(unittest.TestCase):
    """UT-VIP-007: Port protocol change not accompanied by domain module modification."""

    PORT_CONFIG = {"domain_module": "SharedUtilities", "interface_suffix": "Port"}

    def test_port_without_su_rejected(self):
        plan = make_valid_plan()
        # Add a port change to RAGEngine without SharedUtilities modification
        plan["modifications"][0]["contract_changes"] = [
            {"protocol": "EmbeddingGeneratorPort", "change": "add method",
             "description": "New embedding method"}
        ]
        # Ensure no SharedUtilities in modifications
        plan["modifications"] = [m for m in plan["modifications"]
                                 if m["engine"] != "SharedUtilities"]
        # But keep affected_engines consistent
        plan["affected_engines"] = ["RAGEngine", "MetaPromptingEngine", "OrchestrationEngine"]

        result, checks = vip.validate(plan, project_config=self.PORT_CONFIG)
        check = next(c for c in checks if c["check"] == "port_location")
        self.assertEqual(check["result"], "FAIL")

    def test_port_with_su_passes(self):
        plan = make_valid_plan()
        # Add SharedUtilities modification
        plan["affected_engines"].append("SharedUtilities")
        plan["modifications"].append({
            "engine": "SharedUtilities",
            "files": [
                {"path": "packages/AIPRDSharedUtilities/Sources/Domain/Ports/EmbeddingGeneratorPort.swift",
                 "action": "modify", "description": "Add new method"}
            ],
            "contract_changes": [
                {"protocol": "EmbeddingGeneratorPort", "change": "add method"}
            ],
        })

        _, checks = vip.validate(plan, project_config=self.PORT_CONFIG)
        check = next(c for c in checks if c["check"] == "port_location")
        self.assertEqual(check["result"], "PASS")


# ---------------------------------------------------------------------------
# UT-VIP-008: Constraint flags
# ---------------------------------------------------------------------------

class TestConstraintFlags(unittest.TestCase):
    """UT-VIP-008: False constraint flags rejected."""

    def test_false_no_new_packages(self):
        plan = make_valid_plan()
        plan["constraints"]["no_new_packages"] = False

        result, checks = vip.validate(plan)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "constraint_flags")
        self.assertEqual(check["result"], "FAIL")
        self.assertIn("no_new_packages", check["reason"])


# ---------------------------------------------------------------------------
# UT-VIP-009: Test file location
# ---------------------------------------------------------------------------

class TestTestFileLocation(unittest.TestCase):
    """UT-VIP-009: Test files must be under correct package Tests/ dir."""

    def test_misplaced_test_file(self):
        plan = make_valid_plan()
        plan["test_files"] = ["some/random/path/Test.swift"]

        result, checks = vip.validate(plan)
        check = next(c for c in checks if c["check"] == "test_file_location")
        self.assertEqual(check["result"], "FAIL")

    def test_correct_test_location(self):
        plan = make_valid_plan()
        plan["test_files"] = ["packages/AIPRDRAGEngine/Tests/BM25Tests.swift"]

        _, checks = vip.validate(plan)
        check = next(c for c in checks if c["check"] == "test_file_location")
        self.assertEqual(check["result"], "PASS")


# ---------------------------------------------------------------------------
# Schema checks
# ---------------------------------------------------------------------------

class TestSchemaChecks(unittest.TestCase):
    """Test schema validation."""

    def test_missing_keys(self):
        plan = {"finding_id": "tv-001"}
        result, checks = vip.validate(plan)
        self.assertEqual(result, "REJECTED")
        check = next(c for c in checks if c["check"] == "schema_completeness")
        self.assertEqual(check["result"], "FAIL")


if __name__ == "__main__":
    unittest.main()
