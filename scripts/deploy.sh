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

declare -A DEPLOYED_URLS

for worker in processor notifier receipts analytics; do
  echo "Deploying worker module: kk-${worker}-${STAGE}..."
  cd "workers/${worker}"
  
  local log_file="/tmp/wrangler-deploy-${worker}.log"
  npx wrangler deploy --config wrangler.generated.toml | tee "${log_file}"
  
  if [ "$worker" = "receipts" ] || [ "$worker" = "analytics" ]; then
    echo "Seeding API_KEY authentication rules..."
    echo -n "${API_KEY}" | npx wrangler secret put API_KEY --config wrangler.generated.toml
    
    # Parse deployed production edge URL directly from log
    local parsed_url
    parsed_url=$(grep -oE "https://[^ ]+\.workers\.dev" "${log_file}" | head -n 1 || echo "")
    if [ -z "${parsed_url}" ]; then
      echo "Error: Failed to parse exposed route point path for kk-${worker}-${STAGE} from log." >&2
      exit 1
    fi
    DEPLOYED_URLS["${worker}"]="${parsed_url}"
  fi
  cd ../..
done

cat > "${ENV_FILE}" << EOF
# Cloudflare Exposed Domain Ingress Pointers [Stage: ${STAGE}]
KK_RECEIPTS_URL="${DEPLOYED_URLS[receipts]}"
KK_ANALYTICS_URL="${DEPLOYED_URLS[analytics]}"
EOF

echo "==== Workers Deployment Phase Finalized successfully ===="

