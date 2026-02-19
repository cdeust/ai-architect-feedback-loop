#!/usr/bin/env python3
"""
Shared project configuration loader.

Loads config/project.json and provides helpers used by all pipeline scripts.

Usage (Python):
    from load_project_config import load_config
    config = load_config("/path/to/config/project.json")

Usage (Bash — inline):
    MODULE_PREFIX=$(python3 -c "import json; print(json.load(open('config/project.json')).get('module_prefix', ''))")
"""

import json
import os
import sys


DEFAULTS = {
    "language": "python",
    "source_extensions": [".py"],
    "test_file_patterns": ["**/test_*.py", "**/*_test.py"],
    "test_dir_name": "tests",
    "module_prefix": "",
    "modules_dir": "packages",
    "domain_module": None,
    "interface_suffix": None,
    "build_command": "make build",
    "test_command": "make test",
    "deploy_command": None,
    "required_tools": ["python3", "git", "gh", "jq", "claude"],
    "contract_extractor": None,
}


def load_config(config_path):
    """Load project.json with defaults for missing keys."""
    config = dict(DEFAULTS)
    if config_path and os.path.isfile(config_path):
        with open(config_path, "r") as f:
            user = json.load(f)
        config.update(user)
    return config


def find_config(config_dir=None):
    """Find project.json in the given config directory or common locations."""
    if config_dir:
        path = os.path.join(config_dir, "project.json")
        if os.path.isfile(path):
            return path

    # Try relative to script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    path = os.path.join(repo_dir, "config", "project.json")
    if os.path.isfile(path):
        return path

    return None


def load_architecture(config_dir=None):
    """Load config/architecture.md content."""
    if config_dir:
        path = os.path.join(config_dir, "architecture.md")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_dir = os.path.dirname(script_dir)
        path = os.path.join(repo_dir, "config", "architecture.md")

    if os.path.isfile(path):
        with open(path, "r") as f:
            return f.read()
    return ""


if __name__ == "__main__":
    # CLI helper: python3 load_project_config.py [config_path] [key]
    config_path = sys.argv[1] if len(sys.argv) > 1 else None
    key = sys.argv[2] if len(sys.argv) > 2 else None

    if config_path is None:
        config_path = find_config()

    config = load_config(config_path)

    if key:
        value = config.get(key)
        if isinstance(value, (list, dict)):
            print(json.dumps(value))
        elif value is None:
            print("")
        else:
            print(value)
    else:
        print(json.dumps(config, indent=2))
