#!/usr/bin/env python3
"""Extract PRD files from Claude CLI raw output.

When claude -p is called with --output-format json, the output is a JSON
conversation. This script extracts the text content, looks for PRD file
sections, and writes them to the workspace directory.

It looks for files in multiple ways:
1. Write tool calls in the conversation JSON (tool_use blocks)
2. Explicit delimiters like "--- FILE: prd.md ---"
3. Markdown headers like "# prd.md" or "## File: prd.md"
4. Content between code fences with file names

Usage:
    python3 extract_prd_from_ai.py <raw_output_file> <workspace_dir>

Exit codes:
    0  — At least 1 PRD file extracted
    1  — No files found
"""
import json
import os
import re
import sys

PRD_FILES = ["prd.md", "prd-verification.md", "prd-jira.md", "prd-tests.md"]


def _get_text_and_tool_writes(raw: str) -> tuple[str, dict[str, str]]:
    """Parse Claude CLI JSON output to get text and any Write tool calls."""
    full_text = ""
    tool_writes: dict[str, str] = {}  # filename -> content

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return raw, {}

    # Handle {"result": "..."} format
    if isinstance(data, dict) and "result" in data:
        return data["result"], {}

    # Handle conversation array format
    if isinstance(data, list):
        for msg in data:
            if not isinstance(msg, dict):
                continue

            content = msg.get("content", "")
            if isinstance(content, str):
                if msg.get("role") == "assistant":
                    full_text += content + "\n"
                continue

            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        full_text += block.get("text", "") + "\n"
                    elif block.get("type") == "tool_use":
                        _extract_write_tool(block, tool_writes)
                    elif block.get("type") == "tool_result":
                        # Tool results may contain confirmation of writes
                        pass

    return full_text, tool_writes


def _extract_write_tool(block: dict, writes: dict[str, str]) -> None:
    """Extract file content from a Write tool call."""
    name = block.get("name", "")
    input_data = block.get("input", {})

    if name in ("Write", "write", "write_file"):
        file_path = input_data.get("file_path", "") or input_data.get("path", "")
        content = input_data.get("content", "")
        if file_path and content:
            basename = os.path.basename(file_path)
            if basename in PRD_FILES:
                writes[basename] = content


def _extract_from_text(text: str) -> dict[str, str]:
    """Extract PRD file contents from text using pattern matching."""
    results: dict[str, str] = {}

    # Strategy 1: Look for explicit file delimiters
    # Pattern: --- FILE: prd.md --- or === prd.md === or similar
    for fname in PRD_FILES:
        escaped = re.escape(fname)
        patterns = [
            # --- FILE: prd.md ---\n<content>\n--- END ---
            rf"---\s*(?:FILE:\s*)?{escaped}\s*---\s*\n(.*?)(?=\n---\s*(?:FILE:|END)|$)",
            # === prd.md ===
            rf"===\s*{escaped}\s*===\s*\n(.*?)(?=\n===|$)",
        ]
        for pat in patterns:
            m = re.search(pat, text, re.DOTALL)
            if m and len(m.group(1).strip()) > 100:
                results[fname] = m.group(1).strip()
                break

    if len(results) >= 2:
        return results

    # Strategy 2: Look for code fences with filenames
    # ```markdown prd.md\n<content>\n```
    fence_pattern = re.compile(
        r"```(?:markdown|md)?\s*\n(.*?)```", re.DOTALL
    )
    for match in fence_pattern.finditer(text):
        content = match.group(1).strip()
        if len(content) < 100:
            continue
        # Try to identify which PRD file this is
        fname = _identify_prd_file(content)
        if fname and fname not in results:
            results[fname] = content

    if len(results) >= 2:
        return results

    # Strategy 3: Look for headers that match PRD file names
    # # prd.md or ## prd-jira.md
    for fname in PRD_FILES:
        escaped = re.escape(fname)
        name_no_ext = fname.replace(".md", "")
        patterns = [
            rf"#{1,3}\s+(?:File:\s*)?{escaped}\s*\n(.*?)(?=\n#{1,3}\s+(?:File:\s*)?(?:prd|$))",
            rf"#{1,3}\s+{re.escape(name_no_ext)}\s*\n(.*?)(?=\n#{1,3}\s+prd|$)",
        ]
        for pat in patterns:
            m = re.search(pat, text, re.DOTALL | re.IGNORECASE)
            if m and len(m.group(1).strip()) > 100:
                results[fname] = m.group(1).strip()
                break

    if len(results) >= 1:
        return results

    # Strategy 4: If text is very long and looks like a single PRD, save as prd.md
    if len(text) > 2000 and ("# Overview" in text or "## Goals" in text):
        results["prd.md"] = text.strip()

    return results


def _identify_prd_file(content: str) -> str | None:
    """Identify which PRD file a block of content belongs to."""
    content_lower = content[:500].lower()

    if "verification report" in content_lower or "overall score" in content_lower:
        return "prd-verification.md"
    if "jira tickets" in content_lower or "epic overview" in content_lower:
        return "prd-jira.md"
    if "test cases" in content_lower or "ut-001" in content_lower:
        return "prd-tests.md"
    if "overview" in content_lower and ("requirements" in content_lower or "goals" in content_lower):
        return "prd.md"

    return None


def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <raw_output> <workspace_dir>", file=sys.stderr)
        sys.exit(1)

    raw_file, workspace = sys.argv[1], sys.argv[2]

    with open(raw_file) as f:
        raw = f.read()

    if not raw.strip():
        print("ERROR: Raw output file is empty", file=sys.stderr)
        sys.exit(1)

    # Parse the output
    text, tool_writes = _get_text_and_tool_writes(raw)

    # Merge: tool writes take priority, then text extraction
    files_to_write: dict[str, str] = {}

    if tool_writes:
        files_to_write.update(tool_writes)
        print(f"Found {len(tool_writes)} file(s) from Write tool calls", file=sys.stderr)

    # If we didn't get enough from tool calls, try text extraction
    if len(files_to_write) < 2:
        text_files = _extract_from_text(text)
        for fname, content in text_files.items():
            if fname not in files_to_write:
                files_to_write[fname] = content
        if text_files:
            print(f"Found {len(text_files)} file(s) from text extraction", file=sys.stderr)

    if not files_to_write:
        print("ERROR: No PRD files found in AI output", file=sys.stderr)
        # Debug: show first 500 chars
        preview = text[:500].replace("\n", "\\n")
        print(f"DEBUG: text preview: {preview}", file=sys.stderr)
        sys.exit(1)

    # Write files
    os.makedirs(workspace, exist_ok=True)
    written = 0
    for fname, content in files_to_write.items():
        path = os.path.join(workspace, fname)
        with open(path, "w") as f:
            f.write(content)
            if not content.endswith("\n"):
                f.write("\n")
        written += 1
        print(f"Wrote {fname} ({len(content)} chars)", file=sys.stderr)

    print(f"Total files written: {written}", file=sys.stderr)
    # Output the count for the calling script
    print(written)


if __name__ == "__main__":
    main()
