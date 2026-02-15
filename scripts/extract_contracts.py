#!/usr/bin/env python3
"""
Engine Contract Extractor (PIPE-E2-002)

Regex-based Swift parser that extracts the product's public API surface
(port protocols, engine protocols, public types) for prompt injection.

Understands the product's port/adapter naming convention:
  - Ports:   SharedUtilities/Sources/Domain/Ports/*.swift
  - Engines: <Engine>/Sources/**/<Engine>Protocol.swift
  - Types:   Public structs/enums that cross engine boundaries

Usage:
    python3 scripts/extract_contracts.py \
        --packages-dir ../ai-architect-prd-builder/packages \
        --output /tmp/contracts.md \
        [--engines RAGEngine VerificationEngine] \
        [--format markdown|json] \
        [--ports-only]
"""

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Swift parsing regexes
# ---------------------------------------------------------------------------

# Match public protocol declarations with their body
PROTOCOL_PATTERN = re.compile(
    r'^(\s*)(public\s+)?protocol\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)

# Match public struct declarations
STRUCT_PATTERN = re.compile(
    r'^(\s*)public\s+struct\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)

# Match public enum declarations
ENUM_PATTERN = re.compile(
    r'^(\s*)public\s+enum\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)

# Match public class declarations
CLASS_PATTERN = re.compile(
    r'^(\s*)(?:public|open)\s+class\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)

# Match function signatures (for protocol methods)
METHOD_PATTERN = re.compile(
    r'^\s*(?:@\w+\s+)*(?:mutating\s+)?func\s+(\w+)\s*\([^)]*\)(?:\s*(?:async\s*)?(?:throws\s*)?(?:->\s*\S[^\n{]*)?)?\s*$',
    re.MULTILINE
)

# Match var/property declarations in protocols
PROPERTY_PATTERN = re.compile(
    r'^\s*var\s+(\w+)\s*:\s*([^{]+)\s*\{\s*get',
    re.MULTILINE
)


# ---------------------------------------------------------------------------
# Package discovery
# ---------------------------------------------------------------------------

STRIP_PREFIX = "AIPRD"


def strip_prefix(name):
    """Remove AIPRD prefix from package name."""
    if name.startswith(STRIP_PREFIX):
        return name[len(STRIP_PREFIX):]
    return name


def discover_engines(packages_dir):
    """Discover engine package directories under packages_dir."""
    engines = {}
    pattern = os.path.join(packages_dir, "AIPRD*")
    for pkg_dir in sorted(glob.glob(pattern)):
        if not os.path.isdir(pkg_dir):
            continue
        pkg_name = os.path.basename(pkg_dir)
        engine_name = strip_prefix(pkg_name)
        engines[engine_name] = pkg_dir
    return engines


# ---------------------------------------------------------------------------
# Brace matching
# ---------------------------------------------------------------------------

def extract_block(content, start_pos):
    """Extract content between matching braces starting at start_pos.

    start_pos should point to the opening '{'.
    Returns the content between braces (exclusive).
    """
    if start_pos >= len(content) or content[start_pos] != '{':
        return ""

    depth = 0
    pos = start_pos
    while pos < len(content):
        if content[pos] == '{':
            depth += 1
        elif content[pos] == '}':
            depth -= 1
            if depth == 0:
                return content[start_pos + 1:pos]
        pos += 1

    return content[start_pos + 1:]


# ---------------------------------------------------------------------------
# Swift file parsing
# ---------------------------------------------------------------------------

def parse_swift_file(filepath):
    """Parse a Swift file and extract public protocols, structs, enums.

    Returns dict with:
        protocols: [{"name": str, "methods": [str], "properties": [str], "body": str}]
        structs: [{"name": str, "body": str}]
        enums: [{"name": str, "body": str}]
        classes: [{"name": str, "body": str}]
    """
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except OSError:
        return {"protocols": [], "structs": [], "enums": [], "classes": []}

    result = {"protocols": [], "structs": [], "enums": [], "classes": []}

    # Extract protocols
    for match in PROTOCOL_PATTERN.finditer(content):
        name = match.group(3)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)

        methods = [m.group(1) for m in METHOD_PATTERN.finditer(body)]
        properties = [m.group(1) for m in PROPERTY_PATTERN.finditer(body)]

        # Get the full declaration line for display
        decl_end = content.index('{', match.start())
        decl_line = content[match.start():decl_end].strip()

        result["protocols"].append({
            "name": name,
            "methods": methods,
            "properties": properties,
            "body": body.strip(),
            "declaration": decl_line,
        })

    # Extract public structs
    for match in STRUCT_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)

        result["structs"].append({
            "name": name,
            "body": body.strip(),
        })

    # Extract public enums
    for match in ENUM_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)

        result["enums"].append({
            "name": name,
            "body": body.strip(),
        })

    # Extract public classes
    for match in CLASS_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)

        result["classes"].append({
            "name": name,
            "body": body.strip(),
        })

    return result


# ---------------------------------------------------------------------------
# Engine extraction
# ---------------------------------------------------------------------------

def extract_ports(engine_dir):
    """Extract port protocols from SharedUtilities/Sources/Domain/Ports/."""
    ports_dir = os.path.join(engine_dir, "Sources", "Domain", "Ports")
    if not os.path.isdir(ports_dir):
        # Try alternate path structures
        ports_dir = os.path.join(engine_dir, "Sources", "AIPRDSharedUtilities", "Domain", "Ports")
    if not os.path.isdir(ports_dir):
        return []

    ports = []
    for swift_file in sorted(glob.glob(os.path.join(ports_dir, "*.swift"))):
        filename = os.path.basename(swift_file)
        parsed = parse_swift_file(swift_file)
        for proto in parsed["protocols"]:
            ports.append({
                "file": filename,
                "protocol": proto["name"],
                "methods": proto["methods"],
                "properties": proto["properties"],
                "body": proto["body"],
                "declaration": proto["declaration"],
            })
    return ports


def extract_engine_contracts(engine_dir, engine_name):
    """Extract public protocols and types from an engine package."""
    sources_dir = os.path.join(engine_dir, "Sources")
    if not os.path.isdir(sources_dir):
        return {"protocols": [], "public_types": []}

    protocols = []
    public_types = []

    # Walk all Swift files in Sources, excluding Tests and .build
    for root, dirs, files in os.walk(sources_dir):
        dirs[:] = [d for d in dirs if d not in (".build", "Tests", "test")]
        for filename in sorted(files):
            if not filename.endswith(".swift"):
                continue

            filepath = os.path.join(root, filename)
            parsed = parse_swift_file(filepath)

            for proto in parsed["protocols"]:
                protocols.append({
                    "file": filename,
                    "protocol": proto["name"],
                    "methods": proto["methods"],
                    "properties": proto["properties"],
                    "declaration": proto["declaration"],
                })

            for struct in parsed["structs"]:
                public_types.append({
                    "file": filename,
                    "type": "struct",
                    "name": struct["name"],
                })

            for enum in parsed["enums"]:
                public_types.append({
                    "file": filename,
                    "type": "enum",
                    "name": enum["name"],
                })

            for cls in parsed["classes"]:
                public_types.append({
                    "file": filename,
                    "type": "class",
                    "name": cls["name"],
                })

    return {"protocols": protocols, "public_types": public_types}


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def format_markdown(data):
    """Format extraction results as markdown."""
    lines = ["# Engine Contracts \u2014 AI-PRD Generator", ""]

    # SharedUtilities ports first
    if "SharedUtilities" in data:
        su = data["SharedUtilities"]
        ports = su.get("ports", [])
        lines.append(f"## SharedUtilities \u2014 Domain Ports ({len(ports)} protocols)")
        lines.append("")

        for port in ports:
            lines.append(f"### {port['file']}")
            lines.append("```swift")
            lines.append(port["declaration"] + " {")
            if port["body"]:
                for line in port["body"].split("\n"):
                    lines.append("    " + line if line.strip() else "")
            lines.append("}")
            lines.append("```")
            lines.append("")

    # Other engines
    for engine_name in sorted(data.keys()):
        if engine_name == "SharedUtilities":
            continue
        engine = data[engine_name]
        protocols = engine.get("protocols", [])
        public_types = engine.get("public_types", [])

        if not protocols and not public_types:
            continue

        lines.append(f"## {engine_name} \u2014 Public API")
        lines.append("")

        for proto in protocols:
            lines.append(f"### {proto['file']}")
            lines.append("```swift")
            lines.append(proto["declaration"] + " {")
            methods = proto.get("methods", [])
            for method in methods:
                lines.append(f"    func {method}(...)")
            lines.append("}")
            lines.append("```")
            lines.append("")

        if public_types:
            lines.append("**Public Types:**")
            for t in public_types:
                lines.append(f"- `{t['type']} {t['name']}` ({t['file']})")
            lines.append("")

    return "\n".join(lines)


def format_json(data, packages_scanned):
    """Format extraction results as JSON."""
    output = {
        "extracted_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packages_scanned": packages_scanned,
        "engines": {},
    }

    for engine_name, engine_data in data.items():
        if engine_name == "SharedUtilities":
            output["engines"][engine_name] = {
                "ports": [
                    {
                        "file": p["file"],
                        "protocol": p["protocol"],
                        "methods": p["methods"],
                        "properties": p.get("properties", []),
                    }
                    for p in engine_data.get("ports", [])
                ]
            }
        else:
            output["engines"][engine_name] = {
                "protocols": [
                    {
                        "file": p["file"],
                        "protocol": p["protocol"],
                        "methods": p["methods"],
                    }
                    for p in engine_data.get("protocols", [])
                ],
                "public_types": engine_data.get("public_types", []),
            }

    return output


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def extract_all(packages_dir, engine_filter=None, ports_only=False):
    """Extract contracts from all engines (or filtered subset).

    Returns dict mapping engine_name -> extraction data.
    """
    engines = discover_engines(packages_dir)
    data = {}

    for engine_name, engine_dir in engines.items():
        if engine_filter and engine_name not in engine_filter:
            continue

        if engine_name == "SharedUtilities":
            ports = extract_ports(engine_dir)
            data["SharedUtilities"] = {"ports": ports}
        elif not ports_only:
            contracts = extract_engine_contracts(engine_dir, engine_name)
            data[engine_name] = contracts

    return data, len(engines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract engine contracts (ports, protocols, public types) from Swift packages"
    )
    parser.add_argument(
        "--packages-dir", required=True,
        help="Path to packages/ directory"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write output file"
    )
    parser.add_argument(
        "--engines", nargs="+", default=None,
        help="Filter to specific engines (default: all)"
    )
    parser.add_argument(
        "--format", choices=["markdown", "json"], default="markdown",
        help="Output format (default: markdown)"
    )
    parser.add_argument(
        "--ports-only", action="store_true",
        help="Only extract from SharedUtilities/Domain/Ports/"
    )
    args = parser.parse_args(argv)

    if not os.path.isdir(args.packages_dir):
        print(f"ERROR: Packages directory not found: {args.packages_dir}", file=sys.stderr)
        sys.exit(1)

    data, packages_scanned = extract_all(
        args.packages_dir,
        engine_filter=args.engines,
        ports_only=args.ports_only,
    )

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    if args.format == "markdown":
        content = format_markdown(data)
        with open(args.output, "w") as f:
            f.write(content)
            f.write("\n")
    else:
        output = format_json(data, packages_scanned)
        with open(args.output, "w") as f:
            json.dump(output, f, indent=2)
            f.write("\n")

    # Summary to stdout
    total_ports = len(data.get("SharedUtilities", {}).get("ports", []))
    total_protocols = sum(
        len(e.get("protocols", []))
        for name, e in data.items()
        if name != "SharedUtilities"
    ) + total_ports
    print(json.dumps({
        "stage": "extract_contracts",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packages_scanned": packages_scanned,
        "ports_extracted": total_ports,
        "total_protocols": total_protocols,
        "format": args.format,
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
