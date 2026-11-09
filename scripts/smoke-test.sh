#!/usr/bin/env bash
# smoke-test.sh - Dispatches transactional frames and polls endpoints for telemetry validation.
set -euo pipefail

STAGE="${1:-staging}"
ENV_FILE=".env.${STAGE}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: Configuration file '${ENV_FILE}' missing. Please run deployment sequence first." >&2
  exit 1
fi

# Load variables
# shellcheck disable=SC1090
source "${ENV_FILE}"

# Retrieve target API key parameter from local environment variables or dummy profile fallback
API_KEY="${API_KEY:-mock-secret-key-12345}"
UNIQUE_ORDER="ORD-SMOKE-$(date +%s)"

echo "==== Initiating E2E Validation Phase [Stage: ${STAGE}] ===="
echo "Targeting Receipts Edge: ${KK_RECEIPTS_URL}"

# 1. Dispatch an authenticated payment request to the Ingestion Layer
echo "Sending mock order transaction [ID: ${UNIQUE_ORDER}]..."
INGEST_RES=$(curl -s -w "\n%{http_code}" -X POST "${KK_RECEIPTS_URL}/receipts" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d "{\"orderId\":\"${UNIQUE_ORDER}\",\"amount\":4500.50,\"currency\":\"KES\"}")

HTTP_STATUS=$(echo "${INGEST_RES}" | tail -n 1)
RESPONSE_BODY=$(echo "${INGEST_RES}" | sed '$d')

if [ "${HTTP_STATUS}" -ne 202 ]; then
  echo "Ingestion request dropped! HTTP Status Code: ${HTTP_STATUS}" >&2
  echo "Body: ${RESPONSE_BODY}" >&2
  exit 1
fi

echo "Transaction acknowledged cleanly. Receipt Ingestion Node Accepted."

# 2. Asynchronous Polling Phase: Give Cloudflare Queues time to propagate events
echo "Waiting for transaction to propagate down to analytics engine..."
MAX_ATTEMPTS=6
ATTEMPT=1
SUCCESS=0

while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
  echo "Polling Summary Telemetry Endpoint (Attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
  
  SUMMARY_RES=$(curl -s -H "x-api-key: ${API_KEY}" "${KK_ANALYTICS_URL}/summary" || echo "{}")
  RECORD_COUNT=$(echo "${SUMMARY_RES}" | grep -oE '"count":[0-9]+' | cut -d: -f2 || echo "0")
  
  if [ "${RECORD_COUNT}" -gt 0 ]; then
    echo "Telemetry cleared! Core summary metrics registered active records."
    echo "Current System Status Summary Matrix: ${SUMMARY_RES}"
    SUCCESS=1
    break
  fi
  
  sleep 10
  ATTEMPT=$((ATTEMPT + 1))
done

if [ "${SUCCESS}" -eq 1 ]; then
  echo "==== E2E Smoke Test Validation Complete: PASSED ===="
  exit 0
else
  echo "==== E2E Smoke Test Validation Timeout: FAILED ====" >&2
  exit 1
fi
