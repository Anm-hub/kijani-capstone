#!/usr/bin/env bash
# deploy.sh - Iterates through each directory and provisions workers to the active stage.
set -euo pipefail

STAGE="${1:-staging}"
ENV_FILE=".env.${STAGE}"

echo "==== Starting Cloudflare Workers Deployment Phase [Stage: ${STAGE}] ===="

# Deploy non-HTTP background consumers first
for worker in processor notifier; do
  echo "Deploying background worker: kk-${worker}..."
  (cd "workers/${worker}" && npx wrangler deploy --env "${STAGE}")
done

# Deploy HTTP edge interfaces and capture their live routing parameters
echo "Deploying edge API worker: kk-receipts..."
RECEIPTS_OUT=$(cd workers/receipts && npx wrangler deploy --env "${STAGE}")
RECEIPTS_URL=$(echo "${RECEIPTS_OUT}" | grep -oE "https://[^ ]+\.workers\.dev" | head -n 1 || echo "PENDING_REGISTRATION")

echo "Deploying analytics worker: kk-analytics..."
ANALYTICS_OUT=$(cd workers/analytics && npx wrangler deploy --env "${STAGE}")
ANALYTICS_URL=$(echo "${ANALYTICS_OUT}" | grep -oE "https://[^ ]+\.workers\.dev" | head -n 1 || echo "PENDING_REGISTRATION")

# Save outputs locally to a gitignored state location for downstream pipelines
cat > "${ENV_FILE}" << EOF
# Cloudflare Exposed Domain Ingress Pointers [Stage: ${STAGE}]
KK_RECEIPTS_URL="${RECEIPTS_URL}"
KK_ANALYTICS_URL="${ANALYTICS_URL}"
EOF

echo "==== Workers Deployment Phase Finalized successfully ===="
echo "Exposed Ingress vectors mapped to: ${ENV_FILE}"
