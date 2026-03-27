# Memfault Proactive Issue Monitor Demo

A Claude Code agent that proactively monitors a Memfault project for new device
issues, diagnoses them with AI, and takes action:

- **Software bugs** -> opens a fix PR on the firmware repo + posts to Slack
- **Hardware/config issues** -> posts a diagnosis with investigation steps to Slack

## How It Works

1. A Claude Code `/loop` runs the agent prompt every 10 minutes
2. The agent calls Memfault MCP tools to check for new issues
3. For each new issue, it gathers traces, device data, and logs
4. It diagnoses the root cause and classifies it
5. If it's a software bug, it reads the firmware source, creates a fix, and opens a PR
6. It posts a detailed alert to Slack

## Prerequisites

- [Claude Code](https://claude.ai/code) with:
  - Memfault MCP server configured (pointing at your Memfault instance)
  - Slack MCP tools connected
- A running Memfault instance (local dev or cloud)
- The firmware repo cloned: [nRFCloud/shapemate-wearable-autofix-demo](https://github.com/nRFCloud/shapemate-wearable-autofix-demo)
- `gh` CLI authenticated with push access

## Quick Start

1. Clone this repo and the firmware repo:
   ```bash
   git clone https://github.com/nRFCloud/memfault-issue-monitor-demo.git
   git clone https://github.com/nRFCloud/shapemate-wearable-autofix-demo.git
   ```

2. Create the state file:
   ```bash
   cd memfault-issue-monitor-demo
   cp state/state.json.template state/state.json
   ```

3. Start the agent in Claude Code:
   ```
   /loop 10m Follow the instructions in ~/github/memfault-issue-monitor-demo/agent-prompt.md exactly.
   ```

4. (Optional) Trigger a new issue for demo:
   ```bash
   MEMFAULT_PROJECT_KEY=<your-key> ./trigger-new-issue.sh
   ```

## Files

| File | Purpose |
|------|---------|
| `agent-prompt.md` | The agent's instructions (used by `/loop`) |
| `trigger-new-issue.sh` | Injects a coredump to create a new issue for demos |
| `state/state.json` | Tracks which issues have been processed (gitignored) |
| `state/state.json.template` | Template for the state file |

## Demo Flow

1. Start local Memfault dev environment with mock data
2. Start the agent loop (step 3 above)
3. Let it process existing issues (first run)
4. Trigger a new issue with `trigger-new-issue.sh`
5. Wait for next loop iteration (~10 min)
6. Show the Slack notification + GitHub PR side by side
