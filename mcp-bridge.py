#!/usr/bin/env python3
"""
Stdio-to-HTTP bridge for the Memfault MCP server.

Translates between Claude Code's stdio MCP transport and Memfault's
REST-based MCP endpoint at /api/v0/organizations/{org}/projects/{project}/mcp.

Usage:
    MEMFAULT_MCP_URL=http://api.memfault.test:8000/api/v0/organizations/acme-inc/projects/shapemate/mcp \
    MEMFAULT_MCP_TOKEN=oat_... \
    python3 mcp-bridge.py
"""

import json
import os
import sys
import urllib.request

MCP_URL = os.environ["MEMFAULT_MCP_URL"]
MCP_TOKEN = os.environ["MEMFAULT_MCP_TOKEN"]


def send_to_memfault(message: dict) -> dict:
    data = json.dumps(message).encode()
    req = urllib.request.Request(
        MCP_URL,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {MCP_TOKEN}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = message.get("method", "")

        # Handle notifications (no id = no response expected)
        if "id" not in message:
            continue

        try:
            response = send_to_memfault(message)
        except Exception as e:
            response = {
                "jsonrpc": "2.0",
                "id": message.get("id"),
                "error": {"code": -32603, "message": str(e)},
            }

        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
