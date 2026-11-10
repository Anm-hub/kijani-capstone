#!/usr/bin/env bash
# poison-test.sh - Simulates upstream failure by uploading data straight to R2.
set -euo pipefail

STAGE="${1:-staging}"
echo "==== Initiating Live Fault Injection & Isolation Test [Stage: ${STAGE}] ===="

if [ -z "${API_KEY:-}" ]; then
  echo "Error: API_KEY must be provided explicitly as an environment variable parameter." >&2
  exit 1
fi

POISON_ORDER="ORD-POISON-$(date +%s)"
POISON_FILE="receipt-${POISON_ORDER}.json"

cat > "/tmp/${POISON_FILE}" << EOF
{
  "orderId": "${POISON_ORDER}",
  "amount": -550.00,
  "currency": "KES"
}
EOF

echo "Bypassing public gateway API and injecting poison payload directly into R2 bucket..."
npx wrangler r2 object put "kijani-receipts-${STAGE}/${POISON_FILE}" --file="/tmp/${POISON_FILE}" --remote

MAX_ATTEMPTS=9
ATTEMPT=1
SUCCESS=0

while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
  echo "Checking for quarantine artifact (Attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
  if npx wrangler r2 object get "kijani-processed-${STAGE}/quarantine-receipt-${POISON_ORDER}.json" --file=/tmp/q.json --remote 2>/dev/null; then
    echo " -> Fault Isolated! System successfully detected bad business rules and moved file to quarantine."
    SUCCESS=1
    break
  fi
  sleep 10
  ATTEMPT=$((ATTEMPT + 1))
done

rm -f "/tmp/${POISON_FILE}" "/tmp/q.json"

if [ "${SUCCESS}" -eq 1 ]; then
  echo "Poison test step isolated. Invoking baseline smoke test to verify pipeline health..."
  ./scripts/smoke-test.sh "${STAGE}"
  echo "==== Fault Isolation Verification: PASSED ===="
  exit 0
else
  echo " -> Failure! Poison message was not isolated or quarantined." >&2
  exit 1
fi

