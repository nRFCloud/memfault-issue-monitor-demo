#!/bin/bash
# Trigger a new issue in local Memfault by sending a synthetic trace
# Usage: MEMFAULT_PROJECT_KEY=<key> ./trigger-new-issue.sh
#
# Prerequisites:
# - Local Memfault dev instance running (inv dc.svc && inv dev)
# - Mock data populated (inv mock)

set -euo pipefail

PROJECT_KEY="${MEMFAULT_PROJECT_KEY:?Set MEMFAULT_PROJECT_KEY env var}"
API_URL="${MEMFAULT_API_URL:-http://api.memfault.test:8000}"
DEVICE_SERIAL="demo-device-$(date +%s)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

# Pick a random crash scenario for variety
SCENARIOS=(
  '{"reason":"Hard Fault","title":"Hard Fault at flash_fs_write","frames":[{"index":0,"function":"flash_fs_write","file":"src/storage/flash_fs.c","lineno":33},{"index":1,"function":"save_fitness_data","file":"src/fitness/fitness_data_manager.c","lineno":28},{"index":2,"function":"app_tick","file":"src/app/main.c","lineno":15}]}'
  '{"reason":"Assert","title":"Assert at prepare_for_sync","frames":[{"index":0,"function":"prepare_for_sync","file":"src/ble/sync_prep.c","lineno":22},{"index":1,"function":"sync_to_companion","file":"src/sync/sync_with_companion.c","lineno":18},{"index":2,"function":"main","file":"src/main.c","lineno":100}]}'
  '{"reason":"Stack Overflow","title":"Stack Overflow in menu_handler","frames":[{"index":0,"function":"check_shortcut","file":"src/interface/menu.c","lineno":38},{"index":1,"function":"menu_button_handler","file":"src/interface/menu.c","lineno":55},{"index":2,"function":"main","file":"src/main.c","lineno":92}]}'
  '{"reason":"Bus Fault","title":"Bus Fault at gatt_service_init","frames":[{"index":0,"function":"gatt_service_init","file":"src/ble/gatt_service.c","lineno":47},{"index":1,"function":"main","file":"src/main.c","lineno":75}]}'
)

IDX=$(( RANDOM % ${#SCENARIOS[@]} ))
SCENARIO="${SCENARIOS[$IDX]}"
REASON=$(echo "$SCENARIO" | python3 -c "import sys,json; print(json.load(sys.stdin)['reason'])")
FRAMES=$(echo "$SCENARIO" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['frames']))")

echo "Triggering new issue as device $DEVICE_SERIAL..."
echo "Crash type: $REASON"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "$API_URL/api/v0/upload/trace-import" \
  -H "Memfault-Project-Key: $PROJECT_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"captured_date\": \"$NOW\",
    \"reason\": \"$REASON\",
    \"device\": {
      \"device_serial\": \"$DEVICE_SERIAL\",
      \"hardware_version\": \"evt\",
      \"software_version\": \"1.2.0\",
      \"software_type\": \"shapemate-fw\"
    },
    \"processes\": [{
      \"name\": \"main\",
      \"threads\": [{
        \"name\": \"main\",
        \"state\": \"crashed\",
        \"crashed\": true,
        \"stacktrace\": $FRAMES
      }]
    }]
  }")

if [ "$HTTP_CODE" = "202" ]; then
  echo "Done! Trace accepted (HTTP 202). New issue should appear within ~5 seconds."
else
  echo "Error: HTTP $HTTP_CODE. Check that the local dev environment is running."
  exit 1
fi
