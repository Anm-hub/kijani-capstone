#!/usr/bin/env bash
# render-config.sh - Dynamically interpolates target environment variable configurations.
set -euo pipefail

STAGE="${1:-staging}"
echo "Rendering configuration profiles for environment tier: ${STAGE}..."

for w in receipts processor notifier analytics; do
  sed "s/__STAGE__/${STAGE}/g" "workers/${w}/wrangler.template.toml" > "workers/${w}/wrangler.generated.toml"
  echo " -> Compiled workers/${w}/wrangler.generated.toml"
done
