#!/usr/bin/env python3
"""
Stage 3 Integration Plan Validator (PIPE-E2-004)

Validates integration plans against the product's actual file structure
and contracts. Enforces anti-bolt-on constraints.

Validation rules:
  1. Schema completeness
  2. No new non-test source files
  3. All affected engines have modifications
  4. Cross-engine connections exist
  5. Modified files exist in product
  6. Contract changes reference real protocols
  7. Port changes go through SharedUtilities
  8. Constraint flags
  9. Test files are in correct package

Usage:
    python3 scripts/validate_integration_plan.py \
        --plan integration_plan_tv-001.json \
        --packages-dir ../ai-architect-prd-builder/packages \
        [--contracts contracts.json] \
        --output validation_stage3_tv-001.json
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone


REQUIRED_KEYS = [
    "finding_id",
    "affected_engines",
    "modifications",
    "cross_engine_touchpoints",
    "new_files",
    "test_files",
    "constraints",
]


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_json(path):
    """Load JSON file. Exit 1 on failure."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"ERROR: Cannot load {path}: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------------

def check_schema(plan):
    """Rule 1: Required keys present."""
    missing = [k for k in REQUIRED_KEYS if k not in plan]
    if missing:
        return {"check": "schema_completeness", "result": "FAIL",
                "reason": f"Missing keys: {', '.join(missing)}"}
    return {"check": "schema_completeness", "result": "PASS"}


def check_no_new_source_files(plan):
    """Rule 2: new_files must be empty or only contain test files."""
    new_files = plan.get("new_files", [])
    non_test = [f for f in new_files if "/Tests/" not in f]
    if non_test:
        return {"check": "no_new_source_files", "result": "FAIL",
                "reason": f"Non-test new files: {', '.join(non_test[:5])}"}
    return {"check": "no_new_source_files", "result": "PASS"}


def check_all_engines_have_modifications(plan):
    """Rule 3: Every affected engine must have at least one modification."""
    affected = set(plan.get("affected_engines", []))
    modified_engines = set()
    for mod in plan.get("modifications", []):
        engine = mod.get("engine", "")
        if engine:
            modified_engines.add(engine)
    missing = affected - modified_engines
    if missing:
        return {"check": "all_engines_modified", "result": "FAIL",
                "reason": f"Engines with no modifications: {', '.join(sorted(missing))}"}
    return {"check": "all_engines_modified", "result": "PASS"}


def check_cross_engine_connections(plan):
    """Rule 4: Must have at least 1 cross-engine touchpoint."""
    touchpoints = plan.get("cross_engine_touchpoints", [])
    if len(touchpoints) < 1:
        return {"check": "cross_engine_connections", "result": "FAIL",
                "reason": "Zero cross-engine touchpoints — single-engine change"}
    return {"check": "cross_engine_connections", "result": "PASS"}


def check_files_exist(plan, packages_dir):
    """Rule 5: Modified files must exist in the product."""
    if not packages_dir:
        return {"check": "files_exist", "result": "SKIP",
                "reason": "No packages-dir provided"}

    missing = []
    for mod in plan.get("modifications", []):
        for file_entry in mod.get("files", []):
            action = file_entry.get("action", "")
            path = file_entry.get("path", "")
            if action != "modify":
                continue
            # Construct full path
            full_path = os.path.join(packages_dir, "..", path)
            if not os.path.isfile(full_path):
                # Try with AIPRD prefix
                engine = mod.get("engine", "")
                alt_path = os.path.join(packages_dir, f"AIPRD{engine}", path)
                if not os.path.isfile(alt_path):
                    missing.append(path)

    if missing:
        return {"check": "files_exist", "result": "FAIL",
                "reason": f"Non-existent files: {', '.join(missing[:5])}"}
    return {"check": "files_exist", "result": "PASS"}


def check_contract_references(plan, contracts):
    """Rule 6: Contract changes reference real protocols."""
    if not contracts:
        return {"check": "contract_references", "result": "SKIP",
                "reason": "No contracts provided"}

    engines_data = contracts.get("engines", {})
    invalid = []

    for mod in plan.get("modifications", []):
        for change in mod.get("contract_changes", []):
            protocol = change.get("protocol", "")
            engine = mod.get("engine", "")

            # Check if protocol exists in contracts for this engine
            engine_contracts = engines_data.get(engine, {})
            ports = [p["protocol"] for p in engine_contracts.get("ports", [])]
            protocols = [p["protocol"] for p in engine_contracts.get("protocols", [])]

            # Also check SharedUtilities for ports
            su_contracts = engines_data.get("SharedUtilities", {})
            su_ports = [p["protocol"] for p in su_contracts.get("ports", [])]

            all_protocols = set(ports + protocols + su_ports)
            if protocol not in all_protocols:
                invalid.append(f"{protocol} (engine: {engine})")

    if invalid:
        return {"check": "contract_references", "result": "FAIL",
                "reason": f"Invalid protocols: {', '.join(invalid[:5])}"}
    return {"check": "contract_references", "result": "PASS"}


def check_port_location(plan):
    """Rule 7: Port changes must include SharedUtilities file modification."""
    has_port_change = False
    has_su_modification = False

    for mod in plan.get("modifications", []):
        engine = mod.get("engine", "")

        for change in mod.get("contract_changes", []):
            protocol = change.get("protocol", "")
            if protocol.endswith("Port"):
                has_port_change = True

        if engine == "SharedUtilities":
            has_su_modification = True
            for file_entry in mod.get("files", []):
                path = file_entry.get("path", "")
                if "Ports/" in path or "Domain/" in path:
                    has_su_modification = True

    if has_port_change and not has_su_modification:
        return {"check": "port_location", "result": "FAIL",
                "reason": "Port protocol change without SharedUtilities modification"}
    return {"check": "port_location", "result": "PASS"}


def check_constraints(plan):
    """Rule 8: Constraint flags must all be true."""
    constraints = plan.get("constraints", {})
    violations = []
    for flag in ["no_new_packages", "no_standalone_modules", "existing_dependency_graph_only"]:
        if not constraints.get(flag, True):
            violations.append(flag)
    if violations:
        return {"check": "constraint_flags", "result": "FAIL",
                "reason": f"False constraint flags: {', '.join(violations)}"}
    return {"check": "constraint_flags", "result": "PASS"}


def check_test_file_location(plan):
    """Rule 9: Test files must be under correct package Tests/ directory."""
    affected = set(plan.get("affected_engines", []))
    test_files = plan.get("test_files", [])
    misplaced = []

    for tf in test_files:
        in_correct_package = False
        for engine in affected:
            # Check both AIPRD-prefixed and plain engine name patterns
            if f"AIPRD{engine}/Tests/" in tf or f"{engine}/Tests/" in tf:
                in_correct_package = True
                break
        if not in_correct_package and "/Tests/" not in tf:
            misplaced.append(tf)

    if misplaced:
        return {"check": "test_file_location", "result": "FAIL",
                "reason": f"Misplaced test files: {', '.join(misplaced[:5])}"}
    return {"check": "test_file_location", "result": "PASS"}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def validate(plan, packages_dir=None, contracts=None):
    """Run all validation checks. Returns (result, checks)."""
    checks = [
        check_schema(plan),
        check_no_new_source_files(plan),
        check_all_engines_have_modifications(plan),
        check_cross_engine_connections(plan),
        check_files_exist(plan, packages_dir),
        check_contract_references(plan, contracts),
        check_port_location(plan),
        check_constraints(plan),
        check_test_file_location(plan),
    ]

    failures = [c for c in checks if c["result"] == "FAIL"]
    result = "REJECTED" if failures else "ACCEPTED"

    return result, checks


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate Stage 3 integration plan against product constraints"
    )
    parser.add_argument(
        "--plan", required=True,
        help="Path to integration plan JSON"
    )
    parser.add_argument(
        "--packages-dir", default=None,
        help="Path to packages/ directory for file existence checks"
    )
    parser.add_argument(
        "--contracts", default=None,
        help="Path to contracts.json (optional)"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write validation result JSON"
    )
    args = parser.parse_args(argv)

    plan = load_json(args.plan)
    contracts = load_json(args.contracts) if args.contracts else None

    result, checks = validate(plan, args.packages_dir, contracts)

    output = {
        "stage": "validate_integration_plan",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "finding_id": plan.get("finding_id", "unknown"),
        "result": result,
        "checks": checks,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(json.dumps({
        "stage": "validate_integration_plan",
        "finding_id": plan.get("finding_id", "unknown"),
        "result": result,
        "checks_passed": sum(1 for c in checks if c["result"] == "PASS"),
        "checks_failed": sum(1 for c in checks if c["result"] == "FAIL"),
        "status": "complete",
    }))

    if result == "REJECTED":
        sys.exit(1)


if __name__ == "__main__":
    main()
