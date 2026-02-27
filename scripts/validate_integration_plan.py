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
  7. Interface changes go through domain module
  8. Constraint flags
  9. Test files are in correct package

Usage:
    python3 scripts/validate_integration_plan.py \
        --plan integration_plan_tv-001.json \
        --packages-dir /path/to/target-product/packages \
        [--contracts contracts.json] \
        --output validation_stage3_tv-001.json
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone

# Sibling script import — works both when run as script and when imported as module
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)
from validate_impact_report import (  # noqa: E402
    OUTPUT_FORMAT_JSON,
    OUTPUT_FORMAT_TEXT,
    VALID_OUTPUT_FORMATS,
    ErrorRecord,
    _emit_checks_as_json,
    emit_json_line,
    format_error_record,
)


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
    """Rule 4: Must have at least 1 cross-engine touchpoint (multi-engine only)."""
    affected = plan.get("affected_engines", [])
    if len(affected) <= 1:
        return {"check": "cross_engine_connections", "result": "PASS",
                "reason": "Single-engine change — cross-engine touchpoints not required"}
    touchpoints = plan.get("cross_engine_touchpoints", [])
    if len(touchpoints) < 1:
        return {"check": "cross_engine_connections", "result": "FAIL",
                "reason": "Zero cross-engine touchpoints — multi-engine change requires connections"}
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
            # Try multiple resolution strategies for the file path
            candidates = [
                os.path.join(packages_dir, path),           # path relative to packages dir
                os.path.join(packages_dir, "..", path),      # path relative to packages parent
            ]
            engine = mod.get("engine", "")
            if engine:
                candidates.append(os.path.join(packages_dir, engine, path))  # engine/path under packages
            if not any(os.path.isfile(c) for c in candidates):
                missing.append(path)

    if missing:
        return {"check": "files_exist", "result": "FAIL",
                "reason": f"Non-existent files: {', '.join(missing[:5])}"}
    return {"check": "files_exist", "result": "PASS"}


def check_contract_references(plan, contracts, project_config=None):
    """Rule 6: Contract changes reference real protocols."""
    if not contracts:
        return {"check": "contract_references", "result": "SKIP",
                "reason": "No contracts provided"}

    engines_data = contracts.get("engines", {})

    # If no protocols were extracted at all, the language likely lacks
    # contract extraction support — skip rather than fail.
    total_protocols = sum(
        len(e.get("protocols", [])) + len(e.get("ports", []))
        for e in engines_data.values()
    )
    if total_protocols == 0:
        return {"check": "contract_references", "result": "SKIP",
                "reason": "No protocols extracted (language may lack contract parser)"}
    invalid = []

    for mod in plan.get("modifications", []):
        for change in mod.get("contract_changes", []):
            protocol = change.get("protocol", "")
            engine = mod.get("engine", "")

            # Skip entries that explicitly indicate no protocol change
            if not protocol or protocol.lower() in ("n/a", "none", ""):
                continue

            # Check if protocol exists in contracts for this engine
            engine_contracts = engines_data.get(engine, {})
            ports = [p["protocol"] for p in engine_contracts.get("ports", [])]
            protocols = [p["protocol"] for p in engine_contracts.get("protocols", [])]

            # Also check domain module for ports/interfaces
            domain_mod = project_config.get("domain_module") if project_config else None
            su_contracts = engines_data.get(domain_mod, {}) if domain_mod else {}
            su_ports = [p["protocol"] for p in su_contracts.get("ports", [])]

            all_protocols = set(ports + protocols + su_ports)
            if protocol not in all_protocols:
                invalid.append(f"{protocol} (engine: {engine})")

    if invalid:
        return {"check": "contract_references", "result": "FAIL",
                "reason": f"Invalid protocols: {', '.join(invalid[:5])}"}
    return {"check": "contract_references", "result": "PASS"}


def check_port_location(plan, project_config=None):
    """Rule 7: Interface changes must include domain module modification."""
    domain_module = None
    interface_suffix = None
    if project_config:
        domain_module = project_config.get("domain_module")
        interface_suffix = project_config.get("interface_suffix")

    # If no domain module or interface suffix configured, skip this check
    if not domain_module and not interface_suffix:
        return {"check": "port_location", "result": "PASS",
                "reason": "No domain module or interface suffix configured — skipped"}

    has_interface_change = False
    has_domain_modification = False

    for mod in plan.get("modifications", []):
        engine = mod.get("engine", "")

        for change in mod.get("contract_changes", []):
            protocol = change.get("protocol", "")
            if interface_suffix and protocol.endswith(interface_suffix):
                has_interface_change = True

        if domain_module and engine == domain_module:
            has_domain_modification = True

    if has_interface_change and not has_domain_modification:
        return {"check": "port_location", "result": "FAIL",
                "reason": f"Interface change without {domain_module} modification"}
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


def check_test_file_location(plan, project_config=None):
    """Rule 9: Test files must be under correct module test directory."""
    affected = set(plan.get("affected_engines", []))
    test_files = plan.get("test_files", [])
    misplaced = []

    test_dir_name = "tests"
    module_prefix = ""
    if project_config:
        test_dir_name = project_config.get("test_dir_name", "tests")
        module_prefix = project_config.get("module_prefix", "")

    test_dir_variants = [f"/{test_dir_name}/", "/Tests/", "/test/"]

    for tf in test_files:
        in_correct_package = False
        for engine in affected:
            for variant in test_dir_variants:
                if f"{module_prefix}{engine}{variant}" in tf or f"{engine}{variant}" in tf:
                    in_correct_package = True
                    break
            if in_correct_package:
                break
        if not in_correct_package:
            # Check if it's at least in some test directory or has test_ prefix
            basename = os.path.basename(tf)
            if not any(v in tf for v in test_dir_variants) and not basename.startswith("test_"):
                misplaced.append(tf)

    if misplaced:
        return {"check": "test_file_location", "result": "FAIL",
                "reason": f"Misplaced test files: {', '.join(misplaced[:5])}"}
    return {"check": "test_file_location", "result": "PASS"}


# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

def validate(plan, packages_dir=None, contracts=None, project_config=None,
             output_format=OUTPUT_FORMAT_TEXT):
    """Run all validation checks. Returns (result, checks)."""
    if output_format not in VALID_OUTPUT_FORMATS:
        raise ValueError(
            f"Invalid output_format '{output_format}'. Must be one of {VALID_OUTPUT_FORMATS}"
        )
    checks = [
        check_schema(plan),
        check_no_new_source_files(plan),
        check_all_engines_have_modifications(plan),
        check_cross_engine_connections(plan),
        check_files_exist(plan, packages_dir),
        check_contract_references(plan, contracts, project_config),
        check_port_location(plan, project_config),
        check_constraints(plan),
        check_test_file_location(plan, project_config),
    ]
    failures = [c for c in checks if c["result"] == "FAIL"]
    result = "REJECTED" if failures else "ACCEPTED"
    if output_format == OUTPUT_FORMAT_JSON:
        _emit_checks_as_json(checks)
    return result, checks


# ---------------------------------------------------------------------------
# CLI helpers
# ---------------------------------------------------------------------------

def _build_arg_parser():
    """Build and return the argument parser for this validator."""
    parser = argparse.ArgumentParser(
        description="Validate Stage 3 integration plan against product constraints"
    )
    parser.add_argument("--plan", required=True, help="Path to integration plan JSON")
    parser.add_argument("--packages-dir", default=None,
                        help="Path to packages/ directory for file existence checks")
    parser.add_argument("--contracts", default=None, help="Path to contracts.json (optional)")
    parser.add_argument("--project-config", default=None, help="Path to project.json (optional)")
    parser.add_argument("--output", required=True, help="Path to write validation result JSON")
    parser.add_argument(
        "--output-format",
        choices=[OUTPUT_FORMAT_TEXT, OUTPUT_FORMAT_JSON],
        default=OUTPUT_FORMAT_TEXT,
        help="Output format: 'text' (default) or 'json' (newline-delimited JSON)",
    )
    return parser


def _write_validation_output(output, path):
    """Write validation result dict to a JSON file."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")


def main(argv=None):
    args = _build_arg_parser().parse_args(argv)
    plan = load_json(args.plan)
    contracts = load_json(args.contracts) if args.contracts else None
    project_config = load_json(args.project_config) if args.project_config else None

    result, checks = validate(
        plan, args.packages_dir, contracts, project_config,
        output_format=args.output_format,
    )

    output = {
        "stage": "validate_integration_plan",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "finding_id": plan.get("finding_id", "unknown"),
        "result": result,
        "checks": checks,
    }
    _write_validation_output(output, args.output)

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
