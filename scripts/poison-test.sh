#!/usr/bin/env bash
# poison-test.sh - Simulates upstream failure by uploading data straight to R2.
set -euo pipefail

STAGE="${1:-staging}"
echo "==== Initiating Live Fault Injection & Isolation Test [Stage: ${STAGE}] ===="

POISON_ORDER="ORD-POISON-$(date +%s)"
POISON_FILE="receipt-failed-${POISON_ORDER}.json"

echo "Assembling malformed transaction vector data with invalid negative amount..."
cat > "/tmp/${POISON_FILE}" << EOF
{
  "receiptId": "RCP-MALFORMED999",
  "orderId": "${POISON_ORDER}",
  "amount": -550.00,
  "currency": "KES",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "Bypassing public gateway API and injecting poison payload directly into R2 bucket..."
npx wrangler r2 object put "kijani-receipts-${STAGE}/${POISON_FILE}" --file="/tmp/${POISON_FILE}"

echo "Payload injected. Waiting 10 seconds for the decoupling engine consumer logic to evaluate..."
sleep 10

echo "Checking the processing quarantine bucket for isolated data..."
if npx wrangler r2 object list "kijani-processed-${STAGE}" 2>/dev/null | grep -q "quarantine-"; then
  echo " -> Fault Isolated! System successfully detected bad business rules and moved file to quarantine."
  echo " -> Core Pipeline: Stable and resilient against poison records."
  echo "==== Fault Isolation Verification: PASSED ===="
  rm -f "/tmp/${POISON_FILE}"
  exit 0
else
  echo " -> Failure! Poison message was not isolated or quarantined by the worker logic." >&2
  rm -f "/tmp/${POISON_FILE}"
  exit 1
fi
