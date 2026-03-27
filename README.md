# Memfault Proactive Issue Monitor Demo

A Claude Code agent that proactively monitors a Memfault project for new device
issues, diagnoses them with AI, and takes action:

- **Software bugs** — opens a fix PR on the firmware repo + posts to Slack
- **Hardware/config issues** — posts a diagnosis with investigation steps to Slack

## How It Works

```
  Memfault Instance                    Claude Code Agent                     GitHub / Slack
  ┌──────────────┐                    ┌─────────────────┐                   ┌─────────────┐
  │              │  issue.list         │                 │  git push/PR      │  Firmware    │
  │  Issues      │◄────────────────── │  /loop 10m      │ ────────────────► │  Repo PRs    │
  │  Traces      │  issue.get         │                 │                   │             │
  │  Devices     │  trace.get         │  Diagnose &     │  slack_send       │  Slack       │
  │              │  device.get        │  Classify       │ ────────────────► │  Alerts      │
  └──────────────┘                    └─────────────────┘                   └─────────────┘
         ▲                                    │
         │                                    ▼
    MCP Bridge                         state/state.json
    (stdio ↔ HTTP)                     (tracks seen IDs)
```

1. A Claude Code `/loop` runs the agent prompt every 10 minutes
2. The agent calls Memfault MCP tools to check for new issues (sorted by `-first_seen`)
3. New issue IDs are compared against `state/state.json` to avoid re-alerting
4. For each new issue, it gathers traces, device data, and logs via MCP
5. It diagnoses the root cause and classifies it (software bug / hardware / config)
6. If it's a software bug, it reads the firmware source, creates a fix, and opens a PR
7. It posts a detailed alert to Slack with the diagnosis and PR link

## Architecture

This demo has three components:

| Component | Description |
|-----------|-------------|
| **This repo** | Agent prompt, MCP bridge, trigger script, state tracking |
| **[shapemate-wearable-autofix-demo](https://github.com/nRFCloud/shapemate-wearable-autofix-demo)** | Demo firmware repo the agent opens fix PRs against |
| **Memfault instance** | Local dev instance with mock device data and issues |

### MCP Bridge

Memfault's MCP server exposes a REST endpoint (`POST /api/v0/organizations/{org}/projects/{project}/mcp`)
rather than a standard stdio/SSE transport. The `mcp-bridge.py` script translates between
Claude Code's stdio MCP protocol and Memfault's HTTP API, allowing Claude Code to use
Memfault MCP tools natively.

## Prerequisites

- **[Claude Code](https://claude.ai/code)** with Slack MCP tools connected (via Anthropic connector)
- **Local Memfault dev environment** running with mock data:
  ```bash
  cd ~/memfault
  inv dc.svc --detach --no-pull && inv dev.wait-for-services-ready
  inv dev --daemonize && inv dev.wait-for-dev-server
  inv mock --grant-elevated-privileges --lite --password "testpassword123"
  ```
- **[gh CLI](https://cli.github.com/)** authenticated with push access to nRFCloud org
- **Auth token** in local Memfault DB (see [Local Setup](#local-setup) below)

## Local Setup

### 1. Clone repos

```bash
cd ~/github
git clone https://github.com/nRFCloud/memfault-issue-monitor-demo.git
git clone https://github.com/nRFCloud/shapemate-wearable-autofix-demo.git
```

### 2. Create the state file

```bash
cd ~/github/memfault-issue-monitor-demo
cp state/state.json.template state/state.json
```

### 3. Create a Memfault API token

The MCP bridge authenticates to the local Memfault instance using an Organization
Auth Token. Create one in the local DB:

```sql
-- Run via: docker exec memfault-db-1 psql -U memfault

-- Create an actor for the token
INSERT INTO actors (id, type)
VALUES ('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 'ORG_AUTH_TOKEN');

-- Create the token (org_id 4 = acme-inc mock org)
INSERT INTO auth_tokens (type, actor_id, token, description,
  permission_list_type, permission_list, created_date, updated_date,
  organization_id)
VALUES ('OrganizationAuthToken', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  'oat_localMcpDemoToken1234567890ab', 'MCP Demo', 'DENYLIST', '{}',
  NOW(), NOW(), 4);
```

### 4. Configure MCP bridge

The `.mcp.json` in this repo is pre-configured for local dev. If your setup
differs, update the URL and token:

```json
{
  "mcpServers": {
    "memfault": {
      "command": "python3",
      "args": ["<path-to>/mcp-bridge.py"],
      "env": {
        "MEMFAULT_MCP_URL": "http://api.memfault.test:8000/api/v0/organizations/acme-inc/projects/shapemate/mcp",
        "MEMFAULT_MCP_TOKEN": "oat_localMcpDemoToken1234567890ab"
      }
    }
  }
}
```

### 5. Find your project key (for the trigger script)

```bash
docker exec memfault-db-1 psql -U memfault -c \
  "SELECT api_key, slug, organization_slug FROM ingress_projects WHERE slug = 'shapemate';"
```

Use the key for the `acme-inc` org.

## Running the Agent

### Start the loop

Open Claude Code in this repo's directory (so it picks up `.mcp.json`):

```bash
cd ~/github/memfault-issue-monitor-demo
claude
```

Then start the monitoring loop:

```
/loop 10m Follow the instructions in ~/github/memfault-issue-monitor-demo/agent-prompt.md exactly.
```

The first run will process all existing mock issues. Subsequent runs will only
alert on new issues.

### Trigger a new issue (for demos)

In a separate terminal:

```bash
MEMFAULT_PROJECT_KEY=<your-key> ./trigger-new-issue.sh
```

The script randomly picks from 4 crash scenarios (Hard Fault in flash_fs_write,
Assert in prepare_for_sync, Stack Overflow in menu_handler, Bus Fault in
gatt_service_init). Each run creates a new synthetic trace via the
`/api/v0/upload/trace-import` endpoint.

Wait for the next loop iteration (~10 min) and watch Slack + GitHub for the
diagnosis and fix PR.

## Demo Presentation Flow

1. Show the Memfault web UI with existing issues at `http://app.memfault.test:8000`
2. Show the agent loop running in Claude Code
3. Run `trigger-new-issue.sh` to inject a new crash
4. Wait for the agent to detect and process it
5. Show three things side by side:
   - The new issue in Memfault's web UI
   - The Slack notification with AI diagnosis
   - The GitHub PR with the proposed code fix

## Files

| File | Purpose |
|------|---------|
| `agent-prompt.md` | The agent's full instructions — poll, diagnose, fix, alert |
| `mcp-bridge.py` | Stdio-to-HTTP bridge for Memfault's REST MCP endpoint |
| `.mcp.json` | Claude Code MCP server configuration |
| `trigger-new-issue.sh` | Injects synthetic traces to create new issues on demand |
| `state/state.json` | Runtime state tracking processed issue IDs (gitignored) |
| `state/state.json.template` | Template for initializing the state file |

## Resetting for a Fresh Demo

```bash
# Reset state (agent will re-process all issues on next run)
cp state/state.json.template state/state.json

# Clean up autofix branches and PRs
cd ~/github/shapemate-wearable-autofix-demo
git checkout main
for branch in $(git branch | grep autofix/); do
  git branch -D "$branch"
done
gh pr list --repo nRFCloud/shapemate-wearable-autofix-demo --state open \
  --json number --jq '.[].number' | while read pr; do
  gh pr close "$pr" --repo nRFCloud/shapemate-wearable-autofix-demo
done
```

## Limitations

- **Proof of concept** — not production-ready
- **Local dev only** — configured for `app.memfault.test:8000`, not cloud instances
- **No re-checking** — issues are processed once; escalating issues aren't revisited
- **Firmware repo mismatch** — the mock data crash signatures may not perfectly match
  the demo firmware source code, since the mock data is generated independently
- **Requires Claude Code session** — the `/loop` runs within an active terminal session
