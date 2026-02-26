#!/usr/bin/env python3
"""
resolve_config.py — Unified Config Resolver

Reads pipeline.yml (single source of truth) and generates individual config
files that existing pipeline scripts expect. Also supports reverse migration
from existing config files to pipeline.yml.

Usage:
    python3 scripts/resolve_config.py [--config PATH] [--output-dir PATH]
                                      [--dry-run] [--validate] [--reverse]

Options:
    --config PATH       Path to pipeline.yml (default: config/pipeline.yml)
    --output-dir PATH   Output directory for generated files (default: config)
    --dry-run           Show what would be generated without writing files
    --validate          Validate pipeline.yml without generating files
    --reverse           Migrate existing config files to pipeline.yml
"""

import argparse
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Defaults — reuse from load_project_config.py
# ---------------------------------------------------------------------------

PROJECT_DEFAULTS = {
    "language": "python",
    "source_extensions": [".py"],
    "test_file_patterns": ["**/test_*.py", "**/*_test.py"],
    "test_dir_name": "tests",
    "module_prefix": "",
    "modules_dir": "packages",
    "domain_module": None,
    "interface_suffix": None,
    "base_branch": "main",
    "build_command": "make build",
    "test_command": "make test",
    "deploy_command": None,
    "required_tools": ["python3", "git", "gh", "jq", "claude"],
    "contract_extractor": None,
}

LICENSE_DEFAULTS = {
    "key_file": "~/.aiprd/license-key",
    "validate_on_run": True,
}

GIT_DEFAULTS = {
    "run_branch_pattern": "pipeline/run-{run_ts}",
    "feature_branch_pattern": "pipeline/improvement-{finding_id}",
    "commit_message": "pipeline: {finding_id} — {description}",
    "remote": "origin",
}

PR_DEFAULTS = {
    "title": "pipeline: improve {engines} — {finding_id}",
    "labels": ["pipeline-generated", "improvement"],
    "label_engines": True,
    "prd_max_lines": 100,
}

PIPELINE_DEFAULTS = {
    "top_n_findings": 20,
    "max_implementations": 5,
    "exclude_categories": ["benchmarks"],
    "findings_source": "auto",
    "claude_max_turns": {"analysis": 5, "implementation": 30, "verification": 5},
    "claude_timeout": {"default": 300, "implementation": 1800},
    "claude_model": {
        "analysis": "haiku",
        "prd": "opus",
        "implementation": "sonnet",
        "verification": "sonnet",
        "reviewer": "opus",
        "benchmark": "haiku",
        "default": "sonnet",
    },
}

NOTIFICATIONS_DEFAULTS = {
    "enabled": True,
    "sound": "Glass",
    "title": "AI-Architect Pipeline",
}

SCHEDULE_DEFAULTS = {
    "hour": 2,
    "minute": 0,
}

THRESHOLDS_DEFAULTS = {
    "stage_1": {
        "relevance_score_minimum": 0.5,
        "relevance_categories": [
            "api_change", "behavior_change", "dependency_change",
            "config_change", "schema_change", "performance_change",
            "security_change", "prompting", "retrieval", "verification",
            "embeddings", "inference", "cost_optimization", "benchmarks",
        ],
    },
    "stage_2": {
        "compound_score_minimum": 0.3,
        "engines_affected_minimum": 2,
    },
    "stage_5": {
        "prd_quality_minimum": 0.85,
    },
    "stage_10": {
        "prohibited_patterns_file": "config/prohibited_patterns.txt",
        "orphan_detection_extensions": "from_project_config",
        "orphan_detection_exclude_dirs": [".build", ".git", "runs", "logs", "benchmarks"],
    },
    "stage_12": {
        "regression_threshold": 0.05,
        "dimensions": ["completeness", "accuracy", "consistency", "actionability"],
    },
    "retry": {
        "max_attempts": 3,
    },
}

PATTERNS_DEFAULTS = [
    "TODO", "FIXME", "HACK", "XXX", "TEMP\\b",
    "PLACEHOLDER", "placeholder", "not implemented", "stub\\b",
]


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class ConfigError:
    """A single validation error."""
    def __init__(self, section, field, message):
        self.section = section
        self.field = field
        self.message = message

    def __str__(self):
        return f"[{self.section}] {self.field}: {self.message}"


def validate_config(config):
    """Validate pipeline.yml config, returning (errors, warnings) lists of ConfigError."""
    errors = []
    warnings = []

    # Validate module refs in categories
    modules = config.get("modules", {})
    categories = config.get("categories", {})
    for cat_name, cat_data in categories.items():
        if isinstance(cat_data, dict):
            for engine in cat_data.get("primary_engines", []):
                if engine not in modules:
                    errors.append(ConfigError(
                        "categories", f"{cat_name}.primary_engines",
                        f"Engine '{engine}' not found in modules section"
                    ))

    # Validate patterns compile as regex
    for i, pattern in enumerate(config.get("patterns", [])):
        try:
            re.compile(pattern)
        except re.error as e:
            errors.append(ConfigError("patterns", f"[{i}]", f"Invalid regex: {e}"))

    # Validate schedule
    schedule = config.get("schedule", {})
    if isinstance(schedule, dict):
        hour = schedule.get("hour", 2)
        minute = schedule.get("minute", 0)
        if not (0 <= hour <= 23):
            errors.append(ConfigError("schedule", "hour", f"Must be 0-23, got {hour}"))
        if not (0 <= minute <= 59):
            errors.append(ConfigError("schedule", "minute", f"Must be 0-59, got {minute}"))

    # Validate license key file path (warning only — license checked at runtime)
    license_cfg = config.get("license", {})
    if isinstance(license_cfg, dict):
        key_file = license_cfg.get("key_file", "~/.aiprd/license-key")
        expanded = os.path.expanduser(key_file)
        parent = os.path.dirname(expanded)
        if parent and not os.path.isdir(parent) and not os.path.isfile(expanded):
            warnings.append(ConfigError(
                "license", "key_file",
                f"Neither file '{expanded}' nor parent dir '{parent}' exists (free tier will be used)"
            ))

    # Validate branch patterns contain required variables
    git_cfg = config.get("git", {})
    if isinstance(git_cfg, dict):
        run_pattern = git_cfg.get("run_branch_pattern", "")
        if run_pattern and "{run_ts}" not in run_pattern:
            errors.append(ConfigError(
                "git", "run_branch_pattern",
                "Must contain {run_ts} variable"
            ))
        feat_pattern = git_cfg.get("feature_branch_pattern", "")
        if feat_pattern and "{finding_id}" not in feat_pattern:
            errors.append(ConfigError(
                "git", "feature_branch_pattern",
                "Must contain {finding_id} variable"
            ))
        commit_msg = git_cfg.get("commit_message", "")
        if commit_msg and "{finding_id}" not in commit_msg:
            errors.append(ConfigError(
                "git", "commit_message",
                "Must contain {finding_id} variable"
            ))

    # Validate PR title contains {finding_id}
    pr_cfg = config.get("pr", {})
    if isinstance(pr_cfg, dict):
        pr_title = pr_cfg.get("title", "")
        if pr_title and "{finding_id}" not in pr_title:
            errors.append(ConfigError(
                "pr", "title",
                "Must contain {finding_id} variable"
            ))

    # Validate claude_max_turns values are positive integers
    pipeline_cfg = config.get("pipeline", {})
    if isinstance(pipeline_cfg, dict):
        max_turns = pipeline_cfg.get("claude_max_turns", {})
        if isinstance(max_turns, dict):
            for key, val in max_turns.items():
                if not isinstance(val, int) or val <= 0:
                    errors.append(ConfigError(
                        "pipeline", f"claude_max_turns.{key}",
                        f"Must be a positive integer, got {val}"
                    ))
        timeouts = pipeline_cfg.get("claude_timeout", {})
        if isinstance(timeouts, dict):
            for key, val in timeouts.items():
                if not isinstance(val, int) or val <= 0:
                    errors.append(ConfigError(
                        "pipeline", f"claude_timeout.{key}",
                        f"Must be a positive integer, got {val}"
                    ))

    return errors, warnings


# ---------------------------------------------------------------------------
# Config Loading
# ---------------------------------------------------------------------------

def load_pipeline_yaml(config_path):
    """Load and parse pipeline.yml, applying defaults."""
    with open(config_path) as f:
        raw = yaml.safe_load(f) or {}

    config = {}

    # Section 1: project
    project = dict(PROJECT_DEFAULTS)
    project.update(raw.get("project", {}))
    config["project"] = project

    # Section 2: license
    license_cfg = dict(LICENSE_DEFAULTS)
    license_cfg.update(raw.get("license", {}))
    config["license"] = license_cfg

    # Section 3: architecture
    config["architecture"] = raw.get("architecture", "")

    # Section 4: modules
    config["modules"] = raw.get("modules", {})

    # Section 5: categories
    config["categories"] = raw.get("categories", {})

    # Section 6: git
    git_cfg = dict(GIT_DEFAULTS)
    git_cfg.update(raw.get("git", {}))
    config["git"] = git_cfg

    # Section 7: pr
    pr_cfg = dict(PR_DEFAULTS)
    pr_cfg.update(raw.get("pr", {}))
    config["pr"] = pr_cfg

    # Section 8: pipeline
    pipeline_cfg = dict(PIPELINE_DEFAULTS)
    raw_pipeline = raw.get("pipeline", {})
    # Deep-merge nested dicts
    for key in ("claude_max_turns", "claude_timeout", "claude_model"):
        if key in raw_pipeline and isinstance(raw_pipeline[key], dict):
            merged = dict(PIPELINE_DEFAULTS.get(key, {}))
            merged.update(raw_pipeline[key])
            raw_pipeline[key] = merged
    pipeline_cfg.update(raw_pipeline)
    config["pipeline"] = pipeline_cfg

    # Section 9: notifications
    notif_cfg = dict(NOTIFICATIONS_DEFAULTS)
    notif_cfg.update(raw.get("notifications", {}))
    config["notifications"] = notif_cfg

    # Section 10: thresholds
    thresholds = dict(THRESHOLDS_DEFAULTS)
    raw_thresholds = raw.get("thresholds", {})
    for stage_key in raw_thresholds:
        if stage_key in thresholds and isinstance(thresholds[stage_key], dict):
            merged = dict(thresholds[stage_key])
            merged.update(raw_thresholds[stage_key])
            thresholds[stage_key] = merged
        else:
            thresholds[stage_key] = raw_thresholds[stage_key]
    config["thresholds"] = thresholds

    # Section 11: patterns
    config["patterns"] = raw.get("patterns", list(PATTERNS_DEFAULTS))

    # Section 12: schedule
    schedule = dict(SCHEDULE_DEFAULTS)
    schedule.update(raw.get("schedule", {}))
    config["schedule"] = schedule

    return config


# ---------------------------------------------------------------------------
# Generators — produce individual config files
# ---------------------------------------------------------------------------

def generate_project_json(config):
    """Generate config/project.json from project section."""
    return json.dumps(config["project"], indent=2) + "\n"


def generate_architecture_md(config):
    """Generate config/architecture.md from architecture section."""
    content = config.get("architecture", "")
    if not content:
        return ""
    if not content.endswith("\n"):
        content += "\n"
    return content


def generate_engine_graph_overrides(config):
    """Generate config/engine_graph_overrides.json from modules section."""
    modules = config.get("modules", {})
    output = {
        "description": "Module dependency graph. Define your modules with roles and relationships.",
        "engines": modules,
    }
    return json.dumps(output, indent=2) + "\n"


def generate_category_engine_map(config):
    """Generate config/category_engine_map.json from categories section."""
    categories = config.get("categories", {})
    output = {
        "description": "Maps finding categories to affected modules, interfaces, and services",
        "mappings": categories,
    }
    return json.dumps(output, indent=2) + "\n"


def generate_thresholds_json(config):
    """Generate config/thresholds.json from thresholds section."""
    return json.dumps(config["thresholds"], indent=2) + "\n"


def generate_prohibited_patterns(config):
    """Generate config/prohibited_patterns.txt from patterns section."""
    patterns = config.get("patterns", [])
    return "\n".join(patterns) + "\n" if patterns else ""


def generate_plist(config, repo_dir):
    """Generate config/com.ai-architect.pipeline-feedback.plist from schedule."""
    schedule = config.get("schedule", {})
    hour = schedule.get("hour", 2)
    minute = schedule.get("minute", 0)

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ai-architect.pipeline-feedback</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-i</string>
        <string>__REPO_DIR__/scripts/pipeline.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>{hour}</integer>
        <key>Minute</key><integer>{minute}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>__REPO_DIR__/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>__REPO_DIR__/logs/launchd-stderr.log</string>
    <key>WorkingDirectory</key>
    <string>__REPO_DIR__</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
"""


def generate_pipeline_preferences(config):
    """Generate config/pipeline_preferences.json from new sections."""
    prefs = {
        "_generated_from": "pipeline.yml",
        "license": config["license"],
        "git": config["git"],
        "pr": config["pr"],
        "pipeline": config["pipeline"],
        "notifications": config["notifications"],
    }
    return json.dumps(prefs, indent=2) + "\n"


# ---------------------------------------------------------------------------
# Reverse Migration — read existing configs, produce pipeline.yml
# ---------------------------------------------------------------------------

def reverse_migrate(config_dir):
    """Read existing config files and produce pipeline.yml content."""
    pipeline = {}

    # project.json → project section
    project_path = os.path.join(config_dir, "project.json")
    if os.path.isfile(project_path):
        with open(project_path) as f:
            pipeline["project"] = json.load(f)

    # architecture.md → architecture section
    arch_path = os.path.join(config_dir, "architecture.md")
    if os.path.isfile(arch_path):
        with open(arch_path) as f:
            pipeline["architecture"] = f.read()

    # engine_graph_overrides.json → modules section
    graph_path = os.path.join(config_dir, "engine_graph_overrides.json")
    if os.path.isfile(graph_path):
        with open(graph_path) as f:
            data = json.load(f)
        pipeline["modules"] = data.get("engines", {})

    # category_engine_map.json → categories section
    cat_path = os.path.join(config_dir, "category_engine_map.json")
    if os.path.isfile(cat_path):
        with open(cat_path) as f:
            data = json.load(f)
        pipeline["categories"] = data.get("mappings", {})

    # thresholds.json → thresholds section
    thresh_path = os.path.join(config_dir, "thresholds.json")
    if os.path.isfile(thresh_path):
        with open(thresh_path) as f:
            pipeline["thresholds"] = json.load(f)

    # prohibited_patterns.txt → patterns section
    patterns_path = os.path.join(config_dir, "prohibited_patterns.txt")
    if os.path.isfile(patterns_path):
        with open(patterns_path) as f:
            patterns = [
                line.rstrip("\n")
                for line in f
                if line.strip() and not line.startswith("#")
            ]
        pipeline["patterns"] = patterns

    # plist → schedule section
    plist_path = os.path.join(config_dir, "com.ai-architect.pipeline-feedback.plist")
    if os.path.isfile(plist_path):
        with open(plist_path) as f:
            content = f.read()
        hour_match = re.search(r"<key>Hour</key>\s*<integer>(\d+)</integer>", content)
        minute_match = re.search(r"<key>Minute</key>\s*<integer>(\d+)</integer>", content)
        pipeline["schedule"] = {
            "hour": int(hour_match.group(1)) if hour_match else 2,
            "minute": int(minute_match.group(1)) if minute_match else 0,
        }

    # pipeline_preferences.json → license, git, pr, pipeline, notifications
    prefs_path = os.path.join(config_dir, "pipeline_preferences.json")
    if os.path.isfile(prefs_path):
        with open(prefs_path) as f:
            prefs = json.load(f)
        for section in ("license", "git", "pr", "pipeline", "notifications"):
            if section in prefs:
                pipeline[section] = prefs[section]

    # Apply defaults for new sections not yet in config
    if "license" not in pipeline:
        pipeline["license"] = dict(LICENSE_DEFAULTS)
    if "git" not in pipeline:
        pipeline["git"] = dict(GIT_DEFAULTS)
    if "pr" not in pipeline:
        pipeline["pr"] = dict(PR_DEFAULTS)
    if "pipeline" not in pipeline:
        pipeline["pipeline"] = dict(PIPELINE_DEFAULTS)
    if "notifications" not in pipeline:
        pipeline["notifications"] = dict(NOTIFICATIONS_DEFAULTS)

    return pipeline


# ---------------------------------------------------------------------------
# File Writing
# ---------------------------------------------------------------------------

def write_file(path, content, dry_run=False):
    """Write content to file, creating parent dirs. Returns True if changed."""
    if dry_run:
        exists = os.path.isfile(path)
        if exists:
            with open(path) as f:
                old = f.read()
            changed = old != content
        else:
            changed = True
        status = "CHANGED" if changed else "UNCHANGED"
        print(f"  [DRY-RUN] {path} — {status} ({len(content)} bytes)")
        return changed

    os.makedirs(os.path.dirname(path), exist_ok=True)

    # Check if content changed
    if os.path.isfile(path):
        with open(path) as f:
            old = f.read()
        if old == content:
            print(f"  {path} — unchanged")
            return False

    with open(path, "w") as f:
        f.write(content)
    print(f"  {path} — written ({len(content)} bytes)")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def resolve(config_path, output_dir, dry_run=False, validate_only=False):
    """Load pipeline.yml, validate, and generate config files."""
    print(f"Loading {config_path}...")
    config = load_pipeline_yaml(config_path)

    # Validate
    errors, warnings = validate_config(config)
    if warnings:
        print(f"\nValidation warnings ({len(warnings)}):")
        for warn in warnings:
            print(f"  WARN: {warn}")
    if errors:
        print(f"\nValidation errors ({len(errors)}):")
        for err in errors:
            print(f"  ERROR: {err}")
        if validate_only:
            return 1
        print("\nAborting due to validation errors.")
        return 1

    print("Validation passed.")

    if validate_only:
        return 0

    # Resolve repo_dir for plist
    repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(config_path)))

    # Generate files
    print(f"\nGenerating config files in {output_dir}/:")
    changed = 0

    files = [
        ("project.json", generate_project_json(config)),
        ("architecture.md", generate_architecture_md(config)),
        ("engine_graph_overrides.json", generate_engine_graph_overrides(config)),
        ("category_engine_map.json", generate_category_engine_map(config)),
        ("thresholds.json", generate_thresholds_json(config)),
        ("prohibited_patterns.txt", generate_prohibited_patterns(config)),
        ("com.ai-architect.pipeline-feedback.plist", generate_plist(config, repo_dir)),
        ("pipeline_preferences.json", generate_pipeline_preferences(config)),
    ]

    for filename, content in files:
        if content:  # Skip empty files
            path = os.path.join(output_dir, filename)
            if write_file(path, content, dry_run):
                changed += 1

    # Write sentinel
    sentinel_path = os.path.join(output_dir, ".config_resolved")
    if not dry_run:
        with open(sentinel_path, "w") as f:
            from datetime import datetime, timezone
            f.write(datetime.now(timezone.utc).isoformat() + "\n")

    print(f"\nDone. {changed} file(s) {'would be ' if dry_run else ''}updated.")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Resolve pipeline.yml to individual config files"
    )
    parser.add_argument(
        "--config", default=None,
        help="Path to pipeline.yml (default: config/pipeline.yml)"
    )
    parser.add_argument(
        "--output-dir", default=None,
        help="Output directory (default: config)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be generated without writing"
    )
    parser.add_argument(
        "--validate", action="store_true",
        help="Validate pipeline.yml without generating files"
    )
    parser.add_argument(
        "--reverse", action="store_true",
        help="Migrate existing config files to pipeline.yml"
    )
    args = parser.parse_args()

    # Resolve default paths relative to repo root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    config_dir = os.path.join(repo_dir, "config")

    config_path = args.config or os.path.join(config_dir, "pipeline.yml")
    output_dir = args.output_dir or config_dir

    if args.reverse:
        print(f"Migrating existing configs from {output_dir} to pipeline.yml...")
        pipeline = reverse_migrate(output_dir)

        output_path = config_path
        content = yaml.dump(
            pipeline,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
            width=120,
        )

        if args.dry_run:
            print(f"\n[DRY-RUN] Would write {output_path}")
            print("---")
            print(content)
            return 0

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            f.write(content)
        print(f"Written: {output_path} ({len(content)} bytes)")

        # Validate the generated config
        config = load_pipeline_yaml(output_path)
        errors, warns = validate_config(config)
        if warns:
            for w in warns:
                print(f"  Warning: {w}")
        if errors:
            print(f"\nWarning: generated config has {len(errors)} validation issue(s):")
            for err in errors:
                print(f"  {err}")
        else:
            print("Generated config validates successfully.")
        return 0

    if not os.path.isfile(config_path):
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        print("Run 'make setup' to create one, or use --reverse to migrate existing configs.")
        return 1

    return resolve(config_path, output_dir, args.dry_run, args.validate)


if __name__ == "__main__":
    sys.exit(main())
