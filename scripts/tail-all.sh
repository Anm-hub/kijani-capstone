#!/usr/bin/env bash
# tail-all.sh - Aggregates and prefixes background workers streams for real-time presentation monitoring.
set -euo pipefail

STAGE="${1:-staging}"

echo "==== Launching Consolidated Edge Logging Mesh [Stage: ${STAGE}] ===="
echo "Press Ctrl+C to terminate all worker tailing subprocesses."
echo "---------------------------------------------------------"

trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Launch simultaneous async logs subscriptions
npx wrangler tail "kk-receipts-${STAGE}" | sed "s/^/[kk-receipts] /" &
npx wrangler tail "kk-processor-${STAGE}" | sed "s/^/[kk-processor] /" &
npx wrangler tail "kk-notifier-${STAGE}" | sed "s/^/[kk-notifier] /" &
npx wrangler tail "kk-analytics-${STAGE}" | sed "s/^/[kk-analytics] /" &

# Wait for active interrupt to clean up all background jobs safely
wait
