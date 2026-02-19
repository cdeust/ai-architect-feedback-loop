#!/usr/bin/env python3
"""
Module Interface Extractor (PIPE-E2-002)

Language-aware parser that extracts the product's public API surface
(interfaces, protocols, public types) for prompt injection.

Supports multiple languages via config/project.json:
  - Swift: protocol/struct/enum/class parsing
  - Python: ABC subclasses, Protocol classes
  - TypeScript: interface/export declarations
  - Go: type X interface declarations
  - Custom: delegates to contract_extractor script from project.json

Usage:
    python3 scripts/extract_contracts.py \
        --packages-dir /path/to/target-product/packages \
        --output /tmp/contracts.md \
        [--engines core api worker] \
        [--format markdown|json] \
        [--ports-only] \
        [--project-config config/project.json]
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Language-specific parsing regexes
# ---------------------------------------------------------------------------

# Swift
SWIFT_PROTOCOL_PATTERN = re.compile(
    r'^(\s*)(public\s+)?protocol\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)
SWIFT_STRUCT_PATTERN = re.compile(
    r'^(\s*)public\s+struct\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)
SWIFT_ENUM_PATTERN = re.compile(
    r'^(\s*)public\s+enum\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)
SWIFT_CLASS_PATTERN = re.compile(
    r'^(\s*)(?:public|open)\s+class\s+(\w+)\s*(?::\s*[^{]+)?\s*\{',
    re.MULTILINE
)
SWIFT_METHOD_PATTERN = re.compile(
    r'^\s*(?:@\w+\s+)*(?:mutating\s+)?func\s+(\w+)\s*\([^)]*\)(?:\s*(?:async\s*)?(?:throws\s*)?(?:->\s*\S[^\n{]*)?)?\s*$',
    re.MULTILINE
)
SWIFT_PROPERTY_PATTERN = re.compile(
    r'^\s*var\s+(\w+)\s*:\s*([^{]+)\s*\{\s*get',
    re.MULTILINE
)

# Python
PYTHON_ABC_PATTERN = re.compile(
    r'^class\s+(\w+)\s*\(\s*(?:ABC|Protocol)\s*(?:,\s*\w+)*\s*\)\s*:',
    re.MULTILINE
)
PYTHON_METHOD_PATTERN = re.compile(
    r'^\s+(?:@abstractmethod\s+)?def\s+(\w+)\s*\(', re.MULTILINE
)

# TypeScript
TS_INTERFACE_PATTERN = re.compile(
    r'^(?:export\s+)?interface\s+(\w+)\s*(?:extends\s+[^{]+)?\s*\{',
    re.MULTILINE
)
TS_EXPORT_TYPE_PATTERN = re.compile(
    r'^export\s+(?:type|class|enum)\s+(\w+)', re.MULTILINE
)

# Go
GO_INTERFACE_PATTERN = re.compile(
    r'^type\s+(\w+)\s+interface\s*\{', re.MULTILINE
)
GO_STRUCT_PATTERN = re.compile(
    r'^type\s+(\w+)\s+struct\s*\{', re.MULTILINE
)


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_project_config(config_path):
    """Load project.json configuration."""
    defaults = {
        "language": "python",
        "source_extensions": [".py"],
        "module_prefix": "",
        "modules_dir": "packages",
        "domain_module": None,
        "interface_suffix": None,
        "contract_extractor": None,
    }
    if config_path and os.path.isfile(config_path):
        with open(config_path, "r") as f:
            user = json.load(f)
        defaults.update(user)
    return defaults


# ---------------------------------------------------------------------------
# Package discovery
# ---------------------------------------------------------------------------

def discover_engines(packages_dir, module_prefix=""):
    """Discover module directories under packages_dir."""
    engines = {}
    if module_prefix:
        pattern = os.path.join(packages_dir, f"{module_prefix}*")
    else:
        pattern = os.path.join(packages_dir, "*")

    for pkg_dir in sorted(glob.glob(pattern)):
        if not os.path.isdir(pkg_dir):
            continue
        pkg_name = os.path.basename(pkg_dir)
        # Skip hidden directories and common non-module dirs
        if pkg_name.startswith('.') or pkg_name in ('node_modules', '__pycache__', '.build'):
            continue
        engine_name = pkg_name
        if module_prefix and engine_name.startswith(module_prefix):
            engine_name = engine_name[len(module_prefix):]
        engines[engine_name] = pkg_dir
    return engines


# ---------------------------------------------------------------------------
# Brace matching
# ---------------------------------------------------------------------------

def extract_block(content, start_pos):
    """Extract content between matching braces starting at start_pos."""
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
    """Parse a Swift file and extract public protocols, structs, enums."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except OSError:
        return {"protocols": [], "structs": [], "enums": [], "classes": []}

    result = {"protocols": [], "structs": [], "enums": [], "classes": []}

    for match in SWIFT_PROTOCOL_PATTERN.finditer(content):
        name = match.group(3)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        methods = [m.group(1) for m in SWIFT_METHOD_PATTERN.finditer(body)]
        properties = [m.group(1) for m in SWIFT_PROPERTY_PATTERN.finditer(body)]
        decl_end = content.index('{', match.start())
        decl_line = content[match.start():decl_end].strip()
        result["protocols"].append({
            "name": name, "methods": methods, "properties": properties,
            "body": body.strip(), "declaration": decl_line,
        })

    for match in SWIFT_STRUCT_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        result["structs"].append({"name": name, "body": body.strip()})

    for match in SWIFT_ENUM_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        result["enums"].append({"name": name, "body": body.strip()})

    for match in SWIFT_CLASS_PATTERN.finditer(content):
        name = match.group(2)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        result["classes"].append({"name": name, "body": body.strip()})

    return result


# ---------------------------------------------------------------------------
# Python file parsing
# ---------------------------------------------------------------------------

def parse_python_file(filepath):
    """Parse a Python file for ABC/Protocol classes."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except OSError:
        return {"protocols": [], "structs": [], "enums": [], "classes": []}

    result = {"protocols": [], "structs": [], "enums": [], "classes": []}

    for match in PYTHON_ABC_PATTERN.finditer(content):
        name = match.group(1)
        # Extract methods from the class body (indented lines after class def)
        class_start = match.end()
        methods = []
        for m in PYTHON_METHOD_PATTERN.finditer(content[class_start:class_start + 5000]):
            mname = m.group(1)
            if mname != '__init__':
                methods.append(mname)
        result["protocols"].append({
            "name": name, "methods": methods, "properties": [],
            "body": "", "declaration": f"class {name}(ABC)",
        })

    return result


# ---------------------------------------------------------------------------
# TypeScript file parsing
# ---------------------------------------------------------------------------

def parse_typescript_file(filepath):
    """Parse a TypeScript file for interfaces and exports."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except OSError:
        return {"protocols": [], "structs": [], "enums": [], "classes": []}

    result = {"protocols": [], "structs": [], "enums": [], "classes": []}

    for match in TS_INTERFACE_PATTERN.finditer(content):
        name = match.group(1)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        result["protocols"].append({
            "name": name, "methods": [], "properties": [],
            "body": body.strip(), "declaration": f"interface {name}",
        })

    for match in TS_EXPORT_TYPE_PATTERN.finditer(content):
        name = match.group(1)
        result["structs"].append({"name": name, "body": ""})

    return result


# ---------------------------------------------------------------------------
# Go file parsing
# ---------------------------------------------------------------------------

def parse_go_file(filepath):
    """Parse a Go file for interface and struct declarations."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except OSError:
        return {"protocols": [], "structs": [], "enums": [], "classes": []}

    result = {"protocols": [], "structs": [], "enums": [], "classes": []}

    for match in GO_INTERFACE_PATTERN.finditer(content):
        name = match.group(1)
        brace_pos = content.index('{', match.start())
        body = extract_block(content, brace_pos)
        result["protocols"].append({
            "name": name, "methods": [], "properties": [],
            "body": body.strip(), "declaration": f"type {name} interface",
        })

    for match in GO_STRUCT_PATTERN.finditer(content):
        name = match.group(1)
        result["structs"].append({"name": name, "body": ""})

    return result


# ---------------------------------------------------------------------------
# Language-aware file parser dispatch
# ---------------------------------------------------------------------------

PARSERS = {
    "swift": parse_swift_file,
    "python": parse_python_file,
    "typescript": parse_typescript_file,
    "go": parse_go_file,
}

LANG_EXTENSIONS = {
    "swift": [".swift"],
    "python": [".py"],
    "typescript": [".ts", ".tsx"],
    "go": [".go"],
}


def parse_source_file(filepath, language):
    """Parse a source file using the appropriate language parser."""
    parser = PARSERS.get(language)
    if parser:
        return parser(filepath)
    return {"protocols": [], "structs": [], "enums": [], "classes": []}


# ---------------------------------------------------------------------------
# Engine extraction
# ---------------------------------------------------------------------------

def extract_ports(engine_dir, language, domain_module=None):
    """Extract port/interface definitions from the domain module."""
    # Try common paths for the domain/ports directory
    candidates = []
    if domain_module:
        candidates.append(os.path.join(engine_dir, "Sources", "Domain", "Ports"))
        candidates.append(os.path.join(engine_dir, "Sources", domain_module, "Domain", "Ports"))
        candidates.append(os.path.join(engine_dir, "src", "ports"))
        candidates.append(os.path.join(engine_dir, "ports"))
        candidates.append(os.path.join(engine_dir, "interfaces"))

    ports_dir = None
    for candidate in candidates:
        if os.path.isdir(candidate):
            ports_dir = candidate
            break

    if not ports_dir:
        return []

    extensions = LANG_EXTENSIONS.get(language, [".py"])
    ports = []
    for ext in extensions:
        for source_file in sorted(glob.glob(os.path.join(ports_dir, f"*{ext}"))):
            filename = os.path.basename(source_file)
            parsed = parse_source_file(source_file, language)
            for proto in parsed["protocols"]:
                ports.append({
                    "file": filename,
                    "protocol": proto["name"],
                    "methods": proto["methods"],
                    "properties": proto.get("properties", []),
                    "body": proto.get("body", ""),
                    "declaration": proto.get("declaration", ""),
                })
    return ports


def extract_engine_contracts(engine_dir, engine_name, language, source_extensions):
    """Extract public protocols and types from a module."""
    sources_dir = os.path.join(engine_dir, "Sources")
    if not os.path.isdir(sources_dir):
        # Try alternate source directory structures
        for alt in ["src", "lib", engine_dir]:
            if os.path.isdir(alt):
                sources_dir = alt
                break
        else:
            return {"protocols": [], "public_types": []}

    protocols = []
    public_types = []
    exclude_dirs = {".build", "Tests", "test", "tests", "node_modules",
                    "__pycache__", ".git", "vendor"}

    for root, dirs, files in os.walk(sources_dir):
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for filename in sorted(files):
            if not any(filename.endswith(ext) for ext in source_extensions):
                continue
            filepath = os.path.join(root, filename)
            parsed = parse_source_file(filepath, language)

            for proto in parsed["protocols"]:
                protocols.append({
                    "file": filename,
                    "protocol": proto["name"],
                    "methods": proto["methods"],
                    "properties": proto.get("properties", []),
                    "declaration": proto.get("declaration", ""),
                })
            for struct in parsed["structs"]:
                public_types.append({
                    "file": filename, "type": "struct", "name": struct["name"],
                })
            for enum in parsed["enums"]:
                public_types.append({
                    "file": filename, "type": "enum", "name": enum["name"],
                })
            for cls in parsed["classes"]:
                public_types.append({
                    "file": filename, "type": "class", "name": cls["name"],
                })

    return {"protocols": protocols, "public_types": public_types}


# ---------------------------------------------------------------------------
# Custom extractor delegation
# ---------------------------------------------------------------------------

def run_custom_extractor(extractor_path, packages_dir, output_path, fmt):
    """Delegate to a custom contract extractor script."""
    cmd = [extractor_path, "--packages-dir", packages_dir,
           "--output", output_path, "--format", fmt]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: Custom extractor failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def format_markdown(data, language):
    """Format extraction results as markdown."""
    lines = ["# Module Contracts", ""]

    # Domain ports first
    for engine_name in sorted(data.keys()):
        engine = data[engine_name]
        ports = engine.get("ports", [])
        if ports:
            lines.append(f"## {engine_name} — Domain Ports ({len(ports)} interfaces)")
            lines.append("")
            for port in ports:
                lines.append(f"### {port['file']}")
                lines.append(f"```{language}")
                lines.append(port.get("declaration", port["protocol"]) + " {")
                if port.get("body"):
                    for line in port["body"].split("\n"):
                        lines.append("    " + line if line.strip() else "")
                lines.append("}")
                lines.append("```")
                lines.append("")

    # Other engines
    for engine_name in sorted(data.keys()):
        engine = data[engine_name]
        if "ports" in engine:
            continue
        protocols = engine.get("protocols", [])
        public_types = engine.get("public_types", [])

        if not protocols and not public_types:
            continue

        lines.append(f"## {engine_name} — Public API")
        lines.append("")

        for proto in protocols:
            lines.append(f"### {proto['file']}")
            lines.append(f"```{language}")
            lines.append(proto.get("declaration", proto["protocol"]) + " {")
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
        if "ports" in engine_data:
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

def extract_all(packages_dir, engine_filter=None, ports_only=False,
                language="python", module_prefix="", source_extensions=None,
                domain_module=None):
    """Extract contracts from all modules (or filtered subset)."""
    if source_extensions is None:
        source_extensions = LANG_EXTENSIONS.get(language, [".py"])

    engines = discover_engines(packages_dir, module_prefix)
    data = {}

    for engine_name, engine_dir in engines.items():
        if engine_filter and engine_name not in engine_filter:
            continue

        if domain_module and engine_name == domain_module:
            ports = extract_ports(engine_dir, language, domain_module)
            data[engine_name] = {"ports": ports}
        elif not ports_only:
            contracts = extract_engine_contracts(
                engine_dir, engine_name, language, source_extensions)
            data[engine_name] = contracts

    return data, len(engines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract module contracts (interfaces, protocols, public types)"
    )
    parser.add_argument(
        "--packages-dir", required=True,
        help="Path to modules directory"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write output file"
    )
    parser.add_argument(
        "--engines", nargs="+", default=None,
        help="Filter to specific modules (default: all)"
    )
    parser.add_argument(
        "--format", choices=["markdown", "json"], default="markdown",
        help="Output format (default: markdown)"
    )
    parser.add_argument(
        "--ports-only", action="store_true",
        help="Only extract from domain module ports"
    )
    parser.add_argument(
        "--project-config", default=None,
        help="Path to project.json (optional)"
    )
    args = parser.parse_args(argv)

    # Load project config
    config = load_project_config(args.project_config)
    language = config.get("language", "python")
    module_prefix = config.get("module_prefix", "")
    source_extensions = config.get("source_extensions", LANG_EXTENSIONS.get(language, [".py"]))
    domain_module = config.get("domain_module")
    contract_extractor = config.get("contract_extractor")

    if not os.path.isdir(args.packages_dir):
        print(f"ERROR: Packages directory not found: {args.packages_dir}", file=sys.stderr)
        sys.exit(1)

    # Delegate to custom extractor if configured
    if contract_extractor and os.path.isfile(contract_extractor):
        run_custom_extractor(contract_extractor, args.packages_dir, args.output, args.format)
        return

    # Skip extraction if contract_extractor is explicitly null and no source files
    data, packages_scanned = extract_all(
        args.packages_dir,
        engine_filter=args.engines,
        ports_only=args.ports_only,
        language=language,
        module_prefix=module_prefix,
        source_extensions=source_extensions,
        domain_module=domain_module,
    )

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    if args.format == "markdown":
        content = format_markdown(data, language)
        with open(args.output, "w") as f:
            f.write(content)
            f.write("\n")
    else:
        output = format_json(data, packages_scanned)
        with open(args.output, "w") as f:
            json.dump(output, f, indent=2)
            f.write("\n")

    # Summary to stdout
    total_ports = sum(
        len(e.get("ports", []))
        for e in data.values()
    )
    total_protocols = sum(
        len(e.get("protocols", []))
        for e in data.values()
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
