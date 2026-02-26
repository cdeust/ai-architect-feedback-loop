#!/usr/bin/env python3
"""
license.py — License validation and tier detection.

Returns license tier: 'pro', 'free', or exits on provably invalid key.

Behavior:
    - No key file       -> free tier
    - Empty key file    -> free tier
    - Valid key         -> pro tier
    - Invalid key       -> exit 1 (only truly invalid keys)
    - API unreachable   -> free tier (graceful degradation)

Usage:
    python3 scripts/license.py --check [--key-file PATH]

    Exit code 0: prints tier ('pro' or 'free') to stdout
    Exit code 1: invalid license key
"""

import argparse
import json
import os
import subprocess
import sys


ENDPOINTS = [
    ("sandbox-api.polar.sh", "33bddceb-c04b-40f7-a881-54402f1ddd4f"),
    ("api.polar.sh", "3c29257d-7ddb-4ef1-98d4-3d63c491d653"),
]


def validate_license(key_file="~/.aiprd/license-key"):
    """Validate license key against Polar API.

    Returns:
        (tier, message) where tier is 'pro', 'free', or None.
        None means provably invalid key (should exit).
    """
    expanded = os.path.expanduser(key_file)

    if not os.path.isfile(expanded):
        return "free", "No license key — using free tier"

    try:
        with open(expanded) as f:
            key = f.read().strip()
    except OSError:
        return "free", "Could not read license key — using free tier"

    if not key:
        return "free", "Empty license key — using free tier"

    for host, org_id in ENDPOINTS:
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
                    return "pro", f"Active ({host.split('-')[0]})"
                # Key exists but was explicitly rejected
                return None, f"License status: {status}"
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            continue

    # All endpoints unreachable — graceful degradation
    return "free", "Could not validate — using free tier"


def check_or_exit(key_file="~/.aiprd/license-key"):
    """Check license and return tier. Exits only on provably invalid key.

    Returns:
        str: 'pro' or 'free'
    """
    tier, msg = validate_license(key_file)
    if tier is None:
        print(f"License invalid: {msg}", file=sys.stderr)
        print("Get a license at https://polar.sh/ai-architect", file=sys.stderr)
        sys.exit(1)
    return tier


def main():
    parser = argparse.ArgumentParser(description="License validation and tier detection")
    parser.add_argument(
        "--check", action="store_true",
        help="Check license and print tier (pro/free)"
    )
    parser.add_argument(
        "--key-file", default="~/.aiprd/license-key",
        help="Path to license key file"
    )
    parser.add_argument(
        "--validate-only", action="store_true",
        help="Validate and print details (tier + message)"
    )
    args = parser.parse_args()

    if args.validate_only:
        tier, msg = validate_license(args.key_file)
        if tier is None:
            print(f"INVALID: {msg}")
            return 1
        print(f"{tier}: {msg}")
        return 0

    if args.check:
        tier = check_or_exit(args.key_file)
        print(tier)
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
