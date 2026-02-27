#!/usr/bin/env python3
"""
Refresh Claude Code OAuth token from macOS Keychain.

Reads the full credentials JSON from Keychain, refreshes the access token
via platform.claude.com, and outputs the updated credentials JSON to stdout.

Used by the Makefile to provide fresh tokens to Docker containers.
Falls back to the original Keychain token if refresh fails.
"""

import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request

KEYCHAIN_SERVICE = "Claude Code-credentials"
TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
SCOPES = "user:profile user:inference user:sessions:claude_code user:mcp_servers"


def get_keychain_creds() -> dict:
    """Read credentials JSON from macOS Keychain."""
    result = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError("Failed to read from Keychain")
    return json.loads(result.stdout.strip())


def refresh_token(creds: dict) -> dict:
    """Refresh the OAuth access token via platform.claude.com."""
    oauth = creds.get("claudeAiOauth", {})
    refresh_tok = oauth.get("refreshToken", "")
    if not refresh_tok:
        return creds  # No refresh token, return as-is

    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": CLIENT_ID,
        "refresh_token": refresh_tok,
        "scope": SCOPES,
    }).encode()

    req = urllib.request.Request(
        TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())

    oauth["accessToken"] = result["access_token"]
    if "refresh_token" in result:
        oauth["refreshToken"] = result["refresh_token"]
    if "expires_in" in result:
        oauth["expiresAt"] = int(time.time() * 1000) + result["expires_in"] * 1000
    if "scope" in result:
        oauth["scopes"] = result["scope"]

    creds["claudeAiOauth"] = oauth
    return creds


def main():
    try:
        creds = get_keychain_creds()
        creds = refresh_token(creds)
        # Output refreshed credentials JSON to stdout
        print(json.dumps(creds))
    except Exception:
        # Refresh failed — fall back to raw Keychain value
        try:
            creds = get_keychain_creds()
            print(json.dumps(creds))
        except Exception:
            sys.exit(1)


if __name__ == "__main__":
    main()
