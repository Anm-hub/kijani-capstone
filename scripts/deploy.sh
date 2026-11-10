#!/usr/bin/env bash
# deploy.sh - Iterates through each directory and provisions workers using generated targets.
set -euo pipefail

STAGE="${1:-staging}"
ENV_FILE=".env.${STAGE}"

if [ -z "${API_KEY:-}" ]; then
  echo "Error: API_KEY environment parameter must be explicitly set before running deployments." >&2
  exit 1
fi

echo "==== Compiling Configuration Formats ===="
./scripts/render-config.sh "${STAGE}"

echo "==== Starting Cloudflare Workers Deployment Phase [Stage: ${STAGE}] ===="

for worker in processor notifier receipts analytics; do
  echo "Deploying worker module: kk-${worker}-${STAGE}..."
  cd "workers/${worker}"
  
  # Tee configuration updates live to screen
  npx wrangler deploy --config wrangler.generated.toml | tee /tmp/wrangler-deploy.log
  
  # Ingress Interface Secret Seeding via Stdin
  if [ "$worker" = "receipts" ] || [ "$worker" = "analytics" ]; then
    echo "Seeding API_KEY authentication rules..."
    echo -n "${API_KEY}" | npx wrangler secret put API_KEY --config wrangler.generated.toml
  fi
  cd ../..
done

# Extract public routing addresses
RECEIPTS_URL="https://kk-receipts-${STAGE}.anastaciamwangi12.workers.dev"
ANALYTICS_URL="https://kk-analytics-${STAGE}.anastaciamwangi12.workers.dev"

cat > "${ENV_FILE}" << EOF
# Cloudflare Exposed Domain Ingress Pointers [Stage: ${STAGE}]
KK_RECEIPTS_URL="${RECEIPTS_URL}"
KK_ANALYTICS_URL="${ANALYTICS_URL}"
EOF

echo "==== Workers Deployment Phase Finalized successfully ===="

