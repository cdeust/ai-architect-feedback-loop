"""
artifact_paths.py — Standardized artifact path helpers for Python scripts.

Provides functions to resolve artifact paths using the new directory layout
with backward compatibility for the old flat layout.

Usage:
    from artifact_paths import finding_dir, list_findings, resolve_artifact
"""

import os


def finding_dir(run_dir, fid):
    """Create and return the finding directory."""
    d = os.path.join(run_dir, "findings", fid)
    os.makedirs(d, exist_ok=True)
    return d


def attempt_dir(run_dir, fid, attempt):
    """Create and return the attempt directory."""
    d = os.path.join(run_dir, "findings", fid, "attempts", str(attempt))
    os.makedirs(d, exist_ok=True)
    return d


def list_findings(run_dir):
    """List all finding IDs from the findings/ directory."""
    d = os.path.join(run_dir, "findings")
    if os.path.isdir(d):
        return sorted(
            e for e in os.listdir(d)
            if os.path.isdir(os.path.join(d, e))
        )
    return []


def _resolve(run_dir, fid, new_name, old_name):
    """Resolve a file: new path first, fall back to old flat path."""
    new_path = os.path.join(run_dir, "findings", fid, new_name)
    old_path = os.path.join(run_dir, old_name)
    if os.path.isfile(new_path):
        return new_path
    if os.path.isfile(old_path):
        return old_path
    # Default to new path for writes
    os.makedirs(os.path.dirname(new_path), exist_ok=True)
    return new_path


def _resolve_dir(run_dir, fid, new_name, old_name):
    """Resolve a directory: new path first, fall back to old flat path."""
    new_path = os.path.join(run_dir, "findings", fid, new_name)
    old_path = os.path.join(run_dir, old_name)
    if os.path.isdir(new_path):
        return new_path
    if os.path.isdir(old_path):
        return old_path
    os.makedirs(new_path, exist_ok=True)
    return new_path


# Stage 2
def impact_report(run_dir, fid):
    return _resolve(run_dir, fid, "stage2-impact.json", f"impact_report_{fid}.json")


def validation_stage2(run_dir, fid):
    return _resolve(run_dir, fid, "stage2-validation.json", f"validation_stage2_{fid}.json")


# Stage 3
def integration_plan(run_dir, fid):
    return _resolve(run_dir, fid, "stage3-integration.json", f"integration_plan_{fid}.json")


def validation_stage3(run_dir, fid):
    return _resolve(run_dir, fid, "stage3-validation.json", f"validation_stage3_{fid}.json")


def manifest(run_dir, fid):
    return _resolve(run_dir, fid, "stage3-manifest.json", f"manifest_{fid}.json")


# Stage 5 (PRD generation — was stage 4)
def prd_dir(run_dir, fid):
    """Resolve PRD dir with 3-tier fallback: stage5-prd → stage4-prd → prd_output_FID."""
    new_path = os.path.join(run_dir, "findings", fid, "stage5-prd")
    old_numbered = os.path.join(run_dir, "findings", fid, "stage4-prd")
    old_flat = os.path.join(run_dir, f"prd_output_{fid}")
    if os.path.isdir(new_path):
        return new_path
    if os.path.isdir(old_numbered):
        return old_numbered
    if os.path.isdir(old_flat):
        return old_flat
    os.makedirs(new_path, exist_ok=True)
    return new_path


def validation_stage5(run_dir, fid):
    return _resolve(run_dir, fid, "stage5-validation.json", f"validation_stage4_{fid}.json")


# Backward compat alias
validation_stage4 = validation_stage5


# Stage 6 (PRD Review — NEW)
def review_stage6(run_dir, fid):
    return _resolve(run_dir, fid, "stage6-review.json", "")


# Retry
def retry_state(run_dir, fid):
    return _resolve(run_dir, fid, "retry-state.json", f"retry_state_{fid}.json")


def retry_summary(run_dir, fid):
    return _resolve(run_dir, fid, "retry-summary.json", f"retry_summary_{fid}.json")


# Stage 11 (Semantic Verification — was stage 7)
def verification_stage11(run_dir, fid):
    return _resolve(run_dir, fid, "stage11-verification.json", f"verification_stage7_{fid}.json")


# Backward compat alias
verification_stage7 = verification_stage11
