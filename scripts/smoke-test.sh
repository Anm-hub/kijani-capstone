#!/usr/bin/env bash
# smoke-test.sh - Dispatches transactional frames and polls endpoints for telemetry validation.
set -euo pipefail

STAGE="${1:-staging}"
ENV_FILE=".env.${STAGE}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: Configuration file '${ENV_FILE}' missing. Please run deployment sequence first." >&2
  exit 1
fi

if [ -z "${API_KEY:-}" ]; then
  echo "Error: API_KEY must be provided explicitly as an environment variable parameter." >&2
  exit 1
fi

# Load variables
# shellcheck disable=SC1090
source "${ENV_FILE}"

UNIQUE_ORDER="ORD-SMOKE-$(date +%s)"
echo "==== Initiating E2E Validation Phase [Stage: ${STAGE}] ===="

echo "Sending mock order transaction [ID: ${UNIQUE_ORDER}]..."
INGEST_RES=$(curl -s -w "\n%{http_code}" -X POST "${KK_RECEIPTS_URL}/receipts" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d "{\"orderId\":\"${UNIQUE_ORDER}\",\"amount\":4500.50,\"currency\":\"KES\"}" || echo -e "\n000")

HTTP_STATUS=$(echo "${INGEST_RES}" | tail -n 1)
if [ "${HTTP_STATUS}" -ne 202 ]; then
  echo "Ingestion request dropped! HTTP Status Code: ${HTTP_STATUS}" >&2
  exit 1
fi
echo "Transaction acknowledged cleanly."


# 2. Polling loop targeting explicit delivery endpoint
MAX_ATTEMPTS=12
ATTEMPT=1
SUCCESS=0

while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
  echo "Polling GET /delivered/${UNIQUE_ORDER} (Attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "x-api-key: ${API_KEY}" "${KK_ANALYTICS_URL}/delivered/${UNIQUE_ORDER}")
  
  if [ "${STATUS_CODE}" -eq 200 ]; then
    echo "Telemetry cleared! Target record successfully processed across entire cloud loop."
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

