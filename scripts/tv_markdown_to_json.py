#!/usr/bin/env python3
"""
Technical Veil Markdown-to-JSON Converter

Reads Technical Veil markdown files from a date directory and produces
a JSON file matching the input format expected by parse_findings.py.

TV structure:
    TechnicalVeil/
        2026-02-11/
            INDEX.md              (skip)
            _daily_digest.md      (skip)
            _linkedin_angles.md   (skip)
            anthropic.md          (actor file — parse findings)
            openai.md
            ...

Each actor file has domain sections:
    ## 1. AI Breakthroughs & Latest Models
    ### 1.1 Finding Title
    Description...
    | Attribute | Value |
    | Source | arxiv |
    | Importance | —/10 |
    | Post-Worthy | No |
    | Classification | keyword |
    **Source:** [URL](URL)

Usage:
    python3 scripts/tv_markdown_to_json.py \
        --tv-dir /path/to/TechnicalVeil \
        --date 2026-02-11 \
        --output tv_output.json
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Domain → relevance category mapping
# ---------------------------------------------------------------------------

DOMAIN_TO_CATEGORY = {
    "ai breakthroughs & latest models": "benchmarks",
    "prompting techniques & best practices": "prompting",
    "rag (retrieval-augmented generation) management": "retrieval",
    "llm response management": "inference",
    "decomposition & recomposition strategies": "inference",
    "memory management": "inference",
    "context management": "inference",
    "tokenization approaches": "inference",
    "cost optimization": "cost_optimization",
    "token optimization": "cost_optimization",
}

# Files to skip (not actor finding files)
SKIP_FILES = {"INDEX.md", "_daily_digest.md", "_linkedin_angles.md"}


# ---------------------------------------------------------------------------
# Markdown parsing
# ---------------------------------------------------------------------------

def resolve_date_dir(tv_dir, date_str):
    """Resolve the date directory to use.

    If date_str is 'latest', picks the most recent date directory.
    """
    if date_str and date_str != "latest":
        path = os.path.join(tv_dir, date_str)
        if os.path.isdir(path):
            return path
        print(f"ERROR: Date directory not found: {path}", file=sys.stderr)
        sys.exit(1)

    # Find latest date directory
    entries = []
    for name in os.listdir(tv_dir):
        full = os.path.join(tv_dir, name)
        if os.path.isdir(full) and re.match(r"\d{4}-\d{2}-\d{2}", name):
            entries.append(name)

    if not entries:
        print(f"ERROR: No date directories found in {tv_dir}", file=sys.stderr)
        sys.exit(1)

    return os.path.join(tv_dir, sorted(entries)[-1])


def parse_importance(value):
    """Parse importance string like '8/10' or '—/10'.

    Returns a float 0.0-1.0, or None if not a real number.
    """
    match = re.match(r"(\d+(?:\.\d+)?)\s*/\s*10", value.strip())
    if match:
        return float(match.group(1)) / 10.0
    return None


def parse_actor_file(filepath, actor_name):
    """Parse a single TV actor markdown file and extract findings.

    Returns list of finding dicts.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    findings = []
    current_domain = None
    current_category = None

    lines = content.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]

        # Match domain header: ## N. Domain Name
        domain_match = re.match(r"^## \d+\.\s+(.+)$", line)
        if domain_match:
            domain_name = domain_match.group(1).strip()
            current_domain = domain_name
            current_category = DOMAIN_TO_CATEGORY.get(domain_name.lower(), None)
            i += 1
            continue

        # Match finding header: ### N.M Finding Title
        finding_match = re.match(r"^### (\d+\.\d+)\s+(.+)$", line)
        if finding_match:
            section_num = finding_match.group(1)
            title = finding_match.group(2).strip()

            # Skip "Strategic Implications" subsections
            if "strategic implications" in title.lower():
                i += 1
                continue

            # Collect description (lines until next table or section)
            i += 1
            description_lines = []
            while i < len(lines):
                if lines[i].startswith("| ") or lines[i].startswith("### ") or lines[i].startswith("## "):
                    break
                if lines[i].strip():
                    description_lines.append(lines[i].strip())
                i += 1
            description = " ".join(description_lines)

            # Parse attributes table (header row, separator row, data rows)
            attrs = {}
            while i < len(lines) and lines[i].startswith("|"):
                attr_match = re.match(r"^\|\s*(.+?)\s*\|\s*(.+?)\s*\|", lines[i])
                if attr_match:
                    key = attr_match.group(1).strip()
                    val = attr_match.group(2).strip()
                    # Skip header and separator rows
                    if key not in ("Attribute",) and not key.startswith("-"):
                        attrs[key] = val
                i += 1

            # Parse source URL
            source_url = ""
            while i < len(lines) and not lines[i].startswith("### ") and not lines[i].startswith("## "):
                url_match = re.match(r"\*\*Source:\*\*\s*\[.*?\]\((.*?)\)", lines[i])
                if url_match:
                    source_url = url_match.group(1)
                    i += 1
                    break
                if lines[i].strip().startswith("---"):
                    break
                i += 1

            # Build finding
            importance = parse_importance(attrs.get("Importance", ""))
            post_worthy = attrs.get("Post-Worthy", "No").strip().lower() == "yes"

            # Score: use importance if available, else base score with post-worthy boost
            if importance is not None:
                score = importance
            else:
                score = 0.5
            if post_worthy:
                score = max(score, 0.9)

            # Only emit if we have a mapped category
            if current_category:
                finding_id = f"tv-{actor_name}-{section_num}"
                findings.append({
                    "id": finding_id,
                    "title": title,
                    "description": description[:500] if description else "",
                    "source_url": source_url,
                    "relevance_category": current_category,
                    "relevance_score": round(score, 2),
                    "raw_data": {
                        "actor": actor_name,
                        "domain": current_domain or "",
                        "source_type": attrs.get("Source", ""),
                        "classification": attrs.get("Classification", ""),
                        "post_worthy": post_worthy,
                    },
                })
            continue

        i += 1

    return findings


def parse_date_directory(date_dir):
    """Parse all actor markdown files in a date directory.

    Returns list of all findings across all actors.
    """
    all_findings = []

    for filename in sorted(os.listdir(date_dir)):
        if filename in SKIP_FILES:
            continue
        if not filename.endswith(".md"):
            continue

        filepath = os.path.join(date_dir, filename)
        actor_name = filename.replace(".md", "")
        findings = parse_actor_file(filepath, actor_name)
        all_findings.extend(findings)

    return all_findings


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert Technical Veil markdown files to pipeline JSON"
    )
    parser.add_argument(
        "--tv-dir", required=True,
        help="Path to the TechnicalVeil root directory"
    )
    parser.add_argument(
        "--date", default="latest",
        help="Date directory to parse (YYYY-MM-DD or 'latest')"
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write the JSON output"
    )
    args = parser.parse_args(argv)

    # Resolve date directory
    date_dir = resolve_date_dir(args.tv_dir, args.date)
    date_name = os.path.basename(date_dir)

    # Parse all actor files
    findings = parse_date_directory(date_dir)

    # Build output (matching parse_findings.py expected input format)
    output = {
        "source": "technical_veil",
        "date": date_name,
        "converted_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "findings": findings,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    # Summary by category
    categories = {}
    for finding in findings:
        cat = finding["relevance_category"]
        categories[cat] = categories.get(cat, 0) + 1

    print(json.dumps({
        "stage": "tv_markdown_to_json",
        "date": date_name,
        "total_findings": len(findings),
        "categories": categories,
        "status": "complete",
    }))


if __name__ == "__main__":
    main()
