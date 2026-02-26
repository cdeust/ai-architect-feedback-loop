#!/usr/bin/env python3
"""Extract a JSON object from Claude CLI output.

Used by pipeline stages that invoke AI with --output-format json and need to
extract the structured JSON object from the response.

Usage:
    python3 extract_json_from_ai.py <raw_output_file> <dest_json_file>

Exit codes:
    0  — JSON extracted and written successfully
    1  — No valid JSON object found
"""
import json
import re
import sys


def _extract_text_from_claude_output(raw: str) -> str:
    """Unwrap Claude CLI --output-format json envelope to get the AI text."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return raw

    if isinstance(data, dict) and "result" in data:
        return data["result"]

    if isinstance(data, list):
        text = ""
        for msg in data:
            if isinstance(msg, dict) and msg.get("role") == "assistant":
                content = msg.get("content", "")
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text = block.get("text", "")
                elif isinstance(content, str):
                    text = content
        if text:
            return text

    return raw


def _try_parse(candidate: str) -> dict | None:
    """Try to json.loads a string; return dict or None."""
    try:
        obj = json.loads(candidate)
        if isinstance(obj, dict):
            return obj
    except (json.JSONDecodeError, ValueError):
        pass
    return None


def extract_json_object(raw: str) -> dict:
    """Extract the first valid JSON object from raw Claude output.

    Strategy (in order):
    1. Code-fence extraction  — ```json ... ```  or  ``` ... ```
    2. Balanced-brace scan    — walk forward from each '{' counting depth
    3. First-{ / last-}       — legacy fallback
    """
    text = _extract_text_from_claude_output(raw)

    # --- Strategy 1: code-fence extraction ---
    fence_pattern = re.compile(
        r"```(?:json)?\s*\n(.*?)```", re.DOTALL
    )
    for match in fence_pattern.finditer(text):
        candidate = match.group(1).strip()
        obj = _try_parse(candidate)
        if obj is not None:
            return obj

    # --- Strategy 2: balanced-brace scan ---
    for i, ch in enumerate(text):
        if ch == "{":
            depth = 0
            in_string = False
            escape = False
            for j in range(i, len(text)):
                c = text[j]
                if escape:
                    escape = False
                    continue
                if c == "\\":
                    escape = True
                    continue
                if c == '"' and not escape:
                    in_string = not in_string
                    continue
                if in_string:
                    continue
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        candidate = text[i : j + 1]
                        obj = _try_parse(candidate)
                        if obj is not None:
                            return obj
                        break  # this { didn't yield valid JSON, try next {

    # --- Strategy 3: legacy first-{ / last-} ---
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        obj = _try_parse(text[start : end + 1])
        if obj is not None:
            return obj

    raise ValueError("No valid JSON object found in AI output")


def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <raw_file> <output_file>", file=sys.stderr)
        sys.exit(1)

    raw_file, output_file = sys.argv[1], sys.argv[2]

    with open(raw_file) as f:
        raw = f.read()

    try:
        obj = extract_json_object(raw)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        # Log first 500 chars for debugging
        preview = raw[:500].replace("\n", "\\n")
        print(f"DEBUG: raw preview: {preview}", file=sys.stderr)
        sys.exit(1)

    with open(output_file, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
