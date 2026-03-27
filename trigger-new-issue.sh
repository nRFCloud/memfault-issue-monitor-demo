#!/bin/bash
# Trigger a new issue in local Memfault by sending a coredump
# Usage: MEMFAULT_PROJECT_KEY=<key> ./trigger-new-issue.sh [coredump-path]
#
# Prerequisites:
# - Local Memfault dev instance running (inv dc.svc && inv dev)
# - Mock data populated (inv mock)

set -euo pipefail

PROJECT_KEY="${MEMFAULT_PROJECT_KEY:?Set MEMFAULT_PROJECT_KEY env var}"
DEVICE_SERIAL="demo-device-$(date +%s)"
INGRESS_URL="${MEMFAULT_INGRESS_URL:-http://chunks.memfault.test:8002}"
COREDUMP_PATH="${1:-$HOME/memfault/tools/tests/fixtures/binaries/coredumps/esp32-demo-app-assert.bin}"

if [ ! -f "$COREDUMP_PATH" ]; then
  echo "Error: Coredump not found at $COREDUMP_PATH"
  exit 1
fi

echo "Sending coredump as device $DEVICE_SERIAL..."
echo "Using coredump: $COREDUMP_PATH"

python3 "$HOME/memfault/packages/memfault-chunks-ingress/tools/device-chunk-sim.py" \
  -b "$INGRESS_URL" \
  -p "$PROJECT_KEY" \
  --coredump "$COREDUMP_PATH" \
  -d 1

echo "Done. A new issue should appear in Memfault within ~30 seconds."
