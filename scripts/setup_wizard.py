#!/usr/bin/env python3
"""
setup_wizard.py — Interactive Pipeline Setup Wizard

Guides non-technical users through configuring the AI Architect Pipeline.
Auto-detects project settings, validates licenses, and generates pipeline.yml.

Usage:
    python3 scripts/setup_wizard.py [--builder-dir PATH] [--output PATH] [--non-interactive]

Every question has a default — press Enter to accept.
"""

import argparse
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Terminal Helpers
# ---------------------------------------------------------------------------

def color(text, code):
    """Apply ANSI color if terminal supports it."""
    if sys.stdout.isatty():
        return f"\033[{code}m{text}\033[0m"
    return text


def green(text):
    return color(text, "32")


def yellow(text):
    return color(text, "33")


def cyan(text):
    return color(text, "36")


def bold(text):
    return color(text, "1")


def ask(prompt, default="", choices=None):
    """Ask a question with optional default and choices."""
    if choices:
        choice_str = "/".join(choices)
        full_prompt = f"{prompt} [{choice_str}] ({default}): " if default else f"{prompt} [{choice_str}]: "
    elif default:
        full_prompt = f"{prompt} [{default}]: "
    else:
        full_prompt = f"{prompt}: "

    try:
        answer = input(full_prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return default

    return answer if answer else default


def ask_yn(prompt, default=True):
    """Ask a yes/no question."""
    suffix = "[Y/n]" if default else "[y/N]"
    answer = ask(f"{prompt} {suffix}", "")
    if not answer:
        return default
    return answer.lower().startswith("y")


def section_header(title):
    """Print a section header."""
    print(f"\n{bold(cyan(f'=== {title} ==='))}\n")


# ---------------------------------------------------------------------------
# Auto-detection Functions
# ---------------------------------------------------------------------------

LANGUAGE_MANIFESTS = {
    "python": ["pyproject.toml", "setup.py", "setup.cfg"],
    "typescript": ["package.json", "tsconfig.json"],
    "swift": ["Package.swift"],
    "go": ["go.mod"],
    "rust": ["Cargo.toml"],
}

LANGUAGE_EXTENSIONS = {
    "python": [".py"],
    "typescript": [".ts", ".tsx"],
    "swift": [".swift"],
    "go": [".go"],
    "rust": [".rs"],
}

LANGUAGE_TEST_PATTERNS = {
    "python": ["**/test_*.py", "**/*_test.py"],
    "typescript": ["**/*.test.ts", "**/*.spec.ts"],
    "swift": ["**/*Tests.swift", "**/*Test.swift"],
    "go": ["**/*_test.go"],
    "rust": ["**/tests/**/*.rs"],
}


def detect_language(builder_dir):
    """Detect project language from manifest files."""
    for lang, manifests in LANGUAGE_MANIFESTS.items():
        for manifest in manifests:
            if os.path.isfile(os.path.join(builder_dir, manifest)):
                return lang, manifest
    return None, None


def detect_modules_dir(builder_dir):
    """Detect the modules/packages directory."""
    candidates = ["packages", "src", "lib", "Sources", "crates", "modules"]
    for candidate in candidates:
        path = os.path.join(builder_dir, candidate)
        if os.path.isdir(path):
            entries = [e for e in os.listdir(path) if os.path.isdir(os.path.join(path, e))]
            if entries:
                return candidate, entries
    # Root-level project (single module)
    return ".", []


def detect_base_branch(builder_dir):
    """Detect the default branch from git."""
    try:
        result = subprocess.run(
            ["git", "-C", builder_dir, "rev-parse", "--abbrev-ref", "origin/HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            branch = result.stdout.strip().replace("origin/", "")
            if branch:
                return branch
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Fallback: check for main or master
    try:
        result = subprocess.run(
            ["git", "-C", builder_dir, "branch", "--list", "main", "master"],
            capture_output=True, text=True, timeout=5,
        )
        branches = [b.strip().lstrip("* ") for b in result.stdout.strip().split("\n") if b.strip()]
        if "main" in branches:
            return "main"
        if "master" in branches:
            return "master"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return "main"


def detect_build_command(builder_dir, language):
    """Detect the build command."""
    makefile = os.path.join(builder_dir, "Makefile")
    if os.path.isfile(makefile):
        with open(makefile) as f:
            content = f.read()
        if re.search(r"^build\s*:", content, re.MULTILINE):
            return "make build"

    pkg_json = os.path.join(builder_dir, "package.json")
    if os.path.isfile(pkg_json):
        with open(pkg_json) as f:
            data = json.load(f)
        scripts = data.get("scripts", {})
        if "build" in scripts:
            return "npm run build"

    defaults = {
        "python": "make build",
        "typescript": "npm run build",
        "swift": "swift build",
        "go": "go build ./...",
        "rust": "cargo build",
    }
    return defaults.get(language, "make build")


def detect_test_command(builder_dir, language):
    """Detect the test command."""
    makefile = os.path.join(builder_dir, "Makefile")
    if os.path.isfile(makefile):
        with open(makefile) as f:
            content = f.read()
        if re.search(r"^test\s*:", content, re.MULTILINE):
            return "make test"

    pkg_json = os.path.join(builder_dir, "package.json")
    if os.path.isfile(pkg_json):
        with open(pkg_json) as f:
            data = json.load(f)
        scripts = data.get("scripts", {})
        if "test" in scripts:
            return "npm test"

    defaults = {
        "python": "make test",
        "typescript": "npm test",
        "swift": "swift test",
        "go": "go test ./...",
        "rust": "cargo test",
    }
    return defaults.get(language, "make test")


def detect_modules(builder_dir, modules_dir):
    """Detect modules in the modules directory."""
    if modules_dir == ".":
        return {}

    modules_path = os.path.join(builder_dir, modules_dir)
    if not os.path.isdir(modules_path):
        return {}

    modules = {}
    for entry in sorted(os.listdir(modules_path)):
        entry_path = os.path.join(modules_path, entry)
        if not os.path.isdir(entry_path):
            continue
        if entry.startswith(".") or entry == "__pycache__":
            continue

        # Determine role heuristically
        name_lower = entry.lower()
        if "core" in name_lower or "common" in name_lower or "shared" in name_lower:
            role = "shared_infrastructure"
        elif "api" in name_lower or "server" in name_lower or "web" in name_lower:
            role = "api_layer"
        elif "worker" in name_lower or "job" in name_lower or "queue" in name_lower:
            role = "background_processing"
        elif "test" in name_lower:
            continue  # Skip test directories
        else:
            role = "domain_logic"

        modules[entry] = {
            "role": role,
            "feeds": [],
            "fed_by": [],
        }

    return modules


def generate_category_mappings(modules):
    """Generate default category-engine mappings from module names."""
    mappings = {}
    module_names = list(modules.keys())

    # Find likely candidates
    api_engines = [m for m in module_names if "api" in m.lower()]
    core_engines = [m for m in module_names if "core" in m.lower() or "common" in m.lower()]

    if not core_engines:
        core_engines = module_names[:1] if module_names else []
    if not api_engines:
        api_engines = core_engines

    default_categories = {
        "api_change": api_engines,
        "behavior_change": core_engines,
        "dependency_change": core_engines,
        "config_change": core_engines,
        "schema_change": api_engines,
        "performance_change": list(set(core_engines + api_engines)),
        "security_change": core_engines,
    }

    for category, engines in default_categories.items():
        mappings[category] = {
            "primary_engines": engines,
            "related_ports": [],
            "key_services": [],
        }

    return mappings


def validate_license(key_file):
    """Validate license key against Polar API."""
    expanded = os.path.expanduser(key_file)
    if not os.path.isfile(expanded):
        return None, "Key file not found"

    with open(expanded) as f:
        key = f.read().strip()

    if not key:
        return None, "Key file is empty"

    # Try sandbox first, then production
    endpoints = [
        ("sandbox-api.polar.sh", "33bddceb-c04b-40f7-a881-54402f1ddd4f"),
        ("api.polar.sh", "3c29257d-7ddb-4ef1-98d4-3d63c491d653"),
    ]

    for host, org_id in endpoints:
        try:
            result = subprocess.run(
                [
                    "curl", "-sf", "-X", "POST",
                    f"https://{host}/v1/customer-portal/license-keys/validate",
                    "-H", "Content-Type: application/json",
                    "-d", json.dumps({"key": key, "organization_id": org_id}),
                ],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                status = data.get("status", "unknown")
                if status == "granted":
                    return "granted", f"Active ({host.split('-')[0]})"
                return status, f"Status: {status}"
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            continue

    return None, "Could not validate (API unreachable)"


# ---------------------------------------------------------------------------
# Wizard Flow
# ---------------------------------------------------------------------------

def run_wizard(builder_dir=None, output_path=None, non_interactive=False):
    """Run the interactive setup wizard."""
    config = {}

    # ===== Phase A: Welcome & Target =====
    section_header("AI Architect Pipeline Setup")
    print("This wizard will configure the pipeline for your project.")
    print("Every question has a default — press Enter to accept.\n")

    # Target project
    default_builder = builder_dir or os.environ.get("PIPELINE_BUILDER", "")
    if non_interactive:
        target = default_builder
    else:
        target = ask("Target project path", default_builder)

    if not target:
        print("ERROR: Target project path is required.")
        return 1

    target = os.path.expanduser(target)
    target = os.path.abspath(target)

    if not os.path.isdir(target):
        print(f"ERROR: Directory not found: {target}")
        return 1

    # Check if git repo
    git_dir = os.path.join(target, ".git")
    if not os.path.isdir(git_dir):
        print(f"WARNING: {target} is not a git repository")
        if not non_interactive and not ask_yn("Continue anyway?", False):
            return 1

    print(f"  Target: {green(target)}")

    # ===== Phase B: License =====
    section_header("License")

    license_cfg = dict()
    key_file = "~/.aiprd/license-key"
    expanded_key = os.path.expanduser(key_file)

    if os.path.isfile(expanded_key):
        print(f"  Found license key at {key_file}")
        status, detail = validate_license(key_file)
        if status == "granted":
            print(f"  License: {green(detail)}")
        else:
            print(f"  License: {yellow(detail)}")
    else:
        print(f"  No license key found at {key_file}")
        if not non_interactive:
            has_key = ask_yn("Do you have an AIPRD license key?", False)
            if has_key:
                key_value = ask("Enter your license key")
                if key_value:
                    os.makedirs(os.path.dirname(expanded_key), exist_ok=True)
                    with open(expanded_key, "w") as f:
                        f.write(key_value + "\n")
                    os.chmod(expanded_key, 0o600)
                    print(f"  Key saved to {key_file}")
                    status, detail = validate_license(key_file)
                    if status == "granted":
                        print(f"  License: {green(detail)}")
                    else:
                        print(f"  License: {yellow(detail)}")
            else:
                print("  License is needed for Stage 4 (PRD generation).")
                print("  Get one at: https://polar.sh/ai-architect")
                print("  You can add it later by editing pipeline.yml.")

    license_cfg["key_file"] = key_file
    license_cfg["validate_on_run"] = True
    config["license"] = license_cfg

    # ===== Phase C: Project Detection =====
    section_header("Project Detection")

    # Language
    language, manifest = detect_language(target)
    if language:
        print(f"  Detected: {green(language)} (found {manifest})")
        if not non_interactive:
            if not ask_yn("Correct?"):
                language = ask("Language", language)
    else:
        language = "python" if non_interactive else ask("Project language", "python")

    # Modules dir
    modules_dir, module_list = detect_modules_dir(target)
    if module_list:
        print(f"  Found modules at: {green(modules_dir + '/')} ({len(module_list)} modules)")
        if not non_interactive:
            if not ask_yn("Correct?"):
                modules_dir = ask("Modules directory", modules_dir)
    else:
        if modules_dir == ".":
            print("  Single-module project (no packages directory found)")
        else:
            print(f"  Modules directory: {modules_dir}")
        if not non_interactive:
            alt = ask("Modules directory (or '.' for single-module)", modules_dir)
            if alt:
                modules_dir = alt

    # Base branch
    base_branch = detect_base_branch(target)
    print(f"  Base branch: {green(base_branch)}")

    # Build/test commands
    build_cmd = detect_build_command(target, language)
    test_cmd = detect_test_command(target, language)
    print(f"  Build command: {green(build_cmd)}")
    print(f"  Test command: {green(test_cmd)}")

    if not non_interactive:
        if ask_yn("Run build command now to verify?", False):
            print(f"  Running: {build_cmd}")
            result = subprocess.run(
                build_cmd, shell=True, cwd=target,
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode == 0:
                print(f"  {green('Build succeeded')}")
            else:
                print(f"  {yellow('Build failed')} — you can fix this later")
                alt = ask("Alternative build command (or Enter to keep)", build_cmd)
                if alt:
                    build_cmd = alt

    # Source extensions and test patterns
    extensions = LANGUAGE_EXTENSIONS.get(language, [".py"])
    test_patterns = LANGUAGE_TEST_PATTERNS.get(language, ["**/test_*.py"])

    config["project"] = {
        "language": language,
        "source_extensions": extensions,
        "test_file_patterns": test_patterns,
        "test_dir_name": "tests",
        "module_prefix": "",
        "modules_dir": modules_dir,
        "domain_module": None,
        "interface_suffix": None,
        "base_branch": base_branch,
        "build_command": build_cmd,
        "test_command": test_cmd,
        "deploy_command": None,
        "required_tools": ["python3", "git", "gh", "jq", "claude"],
        "contract_extractor": None,
    }

    # Detect modules and build dependency graph
    modules = detect_modules(target, modules_dir)
    if modules:
        print(f"\n  Detected {len(modules)} module(s): {', '.join(modules.keys())}")
    config["modules"] = modules

    # Generate category mappings
    categories = generate_category_mappings(modules)
    config["categories"] = categories

    # ===== Phase D: Git & PR Conventions =====
    section_header("Git & PR Conventions")

    git_cfg = {}
    if non_interactive:
        git_cfg = {
            "run_branch_pattern": "pipeline/run-{run_ts}",
            "feature_branch_pattern": "pipeline/improvement-{finding_id}",
            "commit_message": "pipeline: {finding_id} \u2014 {description}",
            "remote": "origin",
        }
    else:
        print("  How should pipeline branches be named?")
        print(f"    Default: pipeline/improvement-{{finding_id}}")
        print(f"    Examples: feature/{{finding_id}}, auto/{{finding_id}}")
        feat_pattern = ask("Feature branch pattern", "pipeline/improvement-{finding_id}")
        run_pattern = ask("Run branch pattern", "pipeline/run-{run_ts}")

        print(f"\n  Commit message format?")
        print(f"    Default: pipeline: {{finding_id}} \u2014 {{description}}")
        commit_msg = ask("Commit message", "pipeline: {finding_id} \u2014 {description}")

        git_cfg = {
            "run_branch_pattern": run_pattern,
            "feature_branch_pattern": feat_pattern,
            "commit_message": commit_msg,
            "remote": "origin",
        }

    config["git"] = git_cfg

    pr_cfg = {}
    if non_interactive:
        pr_cfg = {
            "title": "pipeline: improve {engines} \u2014 {finding_id}",
            "labels": ["pipeline-generated", "improvement"],
            "label_engines": True,
            "prd_max_lines": 100,
        }
    else:
        pr_title = ask("PR title format", "pipeline: improve {engines} \u2014 {finding_id}")
        pr_labels = ask("PR labels (comma-separated)", "pipeline-generated,improvement")
        label_engines = ask_yn("Also add engine names as labels?")

        pr_cfg = {
            "title": pr_title,
            "labels": [l.strip() for l in pr_labels.split(",")],
            "label_engines": label_engines,
            "prd_max_lines": 100,
        }

    config["pr"] = pr_cfg

    # ===== Phase E: Architecture =====
    section_header("Architecture")

    if non_interactive:
        config["architecture"] = (
            "# Project Architecture\n\n"
            "Describe your project architecture here.\n"
        )
    else:
        print("  Describe your project architecture (injected into AI prompts).")
        print("  You can edit this later in pipeline.yml.")
        if ask_yn("Skip for now?"):
            config["architecture"] = (
                "# Project Architecture\n\n"
                "Describe your project architecture here.\n"
            )
        else:
            editor = os.environ.get("EDITOR", "nano")
            import tempfile
            with tempfile.NamedTemporaryFile(suffix=".md", mode="w", delete=False) as tmp:
                tmp.write("# Project Architecture\n\n")
                tmp.write("Describe your modules and their responsibilities.\n\n")
                tmp.write("## Module Structure\n\n")
                for name in modules:
                    tmp.write(f"- **{name}**: \n")
                tmp.write("\n## Key Patterns\n\n")
                tmp.write("## Constraints\n\n")
                tmp_path = tmp.name

            subprocess.run([editor, tmp_path])
            with open(tmp_path) as f:
                config["architecture"] = f.read()
            os.unlink(tmp_path)

    # ===== Phase F: Tuning =====
    section_header("Pipeline Tuning")

    if non_interactive:
        config["thresholds"] = {
            "stage_1": {
                "relevance_score_minimum": 0.5,
                "relevance_categories": [
                    "api_change", "behavior_change", "dependency_change",
                    "config_change", "schema_change", "performance_change",
                    "security_change", "prompting", "retrieval", "verification",
                    "embeddings", "inference", "cost_optimization", "benchmarks",
                ],
            },
            "stage_2": {"compound_score_minimum": 0.3, "engines_affected_minimum": 2},
            "stage_4": {"prd_quality_minimum": 0.85},
            "stage_6": {
                "prohibited_patterns_file": "config/prohibited_patterns.txt",
                "orphan_detection_extensions": "from_project_config",
                "orphan_detection_exclude_dirs": [".build", ".git", "runs", "logs", "benchmarks"],
            },
            "stage_8": {
                "regression_threshold": 0.05,
                "dimensions": ["completeness", "accuracy", "consistency", "actionability"],
            },
            "retry": {"max_attempts": 3},
        }
        config["patterns"] = [
            "TODO", "FIXME", "HACK", "XXX", "TEMP\\b",
            "PLACEHOLDER", "placeholder", "not implemented", "stub\\b",
        ]
        config["pipeline"] = {
            "top_n_findings": 20,
            "max_implementations": 5,
            "exclude_categories": ["benchmarks"],
            "findings_source": "auto",
            "claude_max_turns": {"analysis": 5, "implementation": 30, "verification": 5},
            "claude_timeout": {"default": 300, "implementation": 1800},
        }
        config["notifications"] = {"enabled": True, "sound": "Glass", "title": "AI-Architect Pipeline"}
        config["schedule"] = {"hour": 2, "minute": 0}
    else:
        use_defaults = ask_yn("Use default thresholds and patterns?")
        if use_defaults:
            config["thresholds"] = {
                "stage_1": {
                    "relevance_score_minimum": 0.5,
                    "relevance_categories": [
                        "api_change", "behavior_change", "dependency_change",
                        "config_change", "schema_change", "performance_change",
                        "security_change", "prompting", "retrieval", "verification",
                        "embeddings", "inference", "cost_optimization", "benchmarks",
                    ],
                },
                "stage_2": {"compound_score_minimum": 0.3, "engines_affected_minimum": 2},
                "stage_4": {"prd_quality_minimum": 0.85},
                "stage_6": {
                    "prohibited_patterns_file": "config/prohibited_patterns.txt",
                    "orphan_detection_extensions": "from_project_config",
                    "orphan_detection_exclude_dirs": [".build", ".git", "runs", "logs", "benchmarks"],
                },
                "stage_8": {
                    "regression_threshold": 0.05,
                    "dimensions": ["completeness", "accuracy", "consistency", "actionability"],
                },
                "retry": {"max_attempts": 3},
            }
            config["patterns"] = [
                "TODO", "FIXME", "HACK", "XXX", "TEMP\\b",
                "PLACEHOLDER", "placeholder", "not implemented", "stub\\b",
            ]
        else:
            # Walk through thresholds
            min_relevance = float(ask("Stage 1 — minimum relevance score (0.0-1.0)", "0.5"))
            min_compound = float(ask("Stage 2 — minimum compound score (0.0-1.0)", "0.3"))
            min_engines = int(ask("Stage 2 — minimum engines affected", "2"))
            prd_quality = float(ask("Stage 4 — PRD quality minimum (0.0-1.0)", "0.85"))
            regression = float(ask("Stage 8 — regression threshold (0.0-1.0)", "0.05"))
            max_retries = int(ask("Max retry attempts", "3"))

            config["thresholds"] = {
                "stage_1": {
                    "relevance_score_minimum": min_relevance,
                    "relevance_categories": [
                        "api_change", "behavior_change", "dependency_change",
                        "config_change", "schema_change", "performance_change",
                        "security_change", "prompting", "retrieval", "verification",
                        "embeddings", "inference", "cost_optimization", "benchmarks",
                    ],
                },
                "stage_2": {
                    "compound_score_minimum": min_compound,
                    "engines_affected_minimum": min_engines,
                },
                "stage_4": {"prd_quality_minimum": prd_quality},
                "stage_6": {
                    "prohibited_patterns_file": "config/prohibited_patterns.txt",
                    "orphan_detection_extensions": "from_project_config",
                    "orphan_detection_exclude_dirs": [".build", ".git", "runs", "logs", "benchmarks"],
                },
                "stage_8": {
                    "regression_threshold": regression,
                    "dimensions": ["completeness", "accuracy", "consistency", "actionability"],
                },
                "retry": {"max_attempts": max_retries},
            }
            config["patterns"] = [
                "TODO", "FIXME", "HACK", "XXX", "TEMP\\b",
                "PLACEHOLDER", "placeholder", "not implemented", "stub\\b",
            ]

        top_n = int(ask("Max findings per run", "20"))
        max_impl = int(ask("Max implementations per run", "5"))
        schedule_hour = int(ask("Schedule hour for nightly run (0-23)", "2"))

        config["pipeline"] = {
            "top_n_findings": top_n,
            "max_implementations": max_impl,
            "exclude_categories": ["benchmarks"],
            "findings_source": "auto",
            "claude_max_turns": {"analysis": 5, "implementation": 30, "verification": 5},
            "claude_timeout": {"default": 300, "implementation": 1800},
        }
        config["notifications"] = {"enabled": True, "sound": "Glass", "title": "AI-Architect Pipeline"}
        config["schedule"] = {"hour": schedule_hour, "minute": 0}

    # ===== Phase G: Generate & Validate =====
    section_header("Generating Configuration")

    # Determine output path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    config_dir = os.path.join(repo_dir, "config")

    if output_path is None:
        output_path = os.path.join(config_dir, "pipeline.yml")

    # Write pipeline.yml
    # Reorder sections for readability
    ordered = {}
    for key in ["project", "license", "architecture", "modules", "categories",
                 "git", "pr", "pipeline", "notifications", "thresholds",
                 "patterns", "schedule"]:
        if key in config:
            ordered[key] = config[key]

    content = yaml.dump(
        ordered,
        default_flow_style=False,
        allow_unicode=True,
        sort_keys=False,
        width=120,
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        f.write(content)
    print(f"  Written: {green(output_path)}")

    # Run resolver
    print("\n  Generating individual config files...")
    resolve_script = os.path.join(script_dir, "resolve_config.py")
    result = subprocess.run(
        [sys.executable, resolve_script, "--config", output_path, "--output-dir", config_dir],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode == 0:
        # Print resolver output indented
        for line in result.stdout.strip().split("\n"):
            print(f"    {line}")
    else:
        print(f"  {yellow('Warning')}: Resolver reported issues:")
        for line in (result.stdout + result.stderr).strip().split("\n"):
            print(f"    {line}")

    # Summary
    section_header("Setup Complete")
    print(f"  Config file:  {output_path}")
    print(f"  License:      {config['license']['key_file']}")
    print(f"  Language:      {config['project']['language']}")
    print(f"  Modules:       {len(config.get('modules', {}))} detected")
    print(f"  Base branch:   {config['project']['base_branch']}")
    print(f"  Build:         {config['project']['build_command']}")
    print(f"  Test:          {config['project']['test_command']}")
    print(f"  Schedule:      {config['schedule']['hour']}:{config['schedule']['minute']:02d}")
    print()
    print(f"  Next: run '{bold('make pipeline-health')}' to verify the setup")
    print()

    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="AI Architect Pipeline Setup Wizard")
    parser.add_argument(
        "--builder-dir", default=None,
        help="Target project directory (or set PIPELINE_BUILDER env var)",
    )
    parser.add_argument(
        "--output", default=None,
        help="Output path for pipeline.yml (default: config/pipeline.yml)",
    )
    parser.add_argument(
        "--non-interactive", action="store_true",
        help="Use all defaults without prompting (for CI/testing)",
    )
    args = parser.parse_args()

    return run_wizard(
        builder_dir=args.builder_dir,
        output_path=args.output,
        non_interactive=args.non_interactive,
    )


if __name__ == "__main__":
    sys.exit(main())
