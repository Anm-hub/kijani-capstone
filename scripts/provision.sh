#!/usr/bin/env bash
# provision.sh - Idempotently configures cloud infrastructure primitives on Cloudflare.
set -euo pipefail

STAGE="${1:-staging}"
echo "==== Starting Cloudflare Resource Provisioning for Stage: ${STAGE} ===="

# 1. Helper function to create R2 buckets safely
create_bucket_idempotent() {
  local name=$1
  echo "Checking R2 bucket: ${name}..."
  if npx wrangler r2 bucket list 2>/dev/null | grep -q "${name}"; then
    echo " -> Bucket '${name}' already exists."
  else
    echo " -> Creating R2 bucket '${name}'..."
    npx wrangler r2 bucket create "${name}"
  fi
}

# 2. Helper function to create Queues safely
create_queue_idempotent() {
  local name=$1
  echo "Checking Cloudflare Queue: ${name}..."
  if npx wrangler queues list 2>/dev/null | grep -q "${name}"; then
    echo " -> Queue '${name}' already exists."
  else
    echo " -> Creating Queue '${name}'..."
    npx wrangler queues create "${name}"
  fi
}

# 3. Create the Dead Letter Queue first
create_queue_idempotent "kijani-dead-letters-${STAGE}"

# 4. Provision required pipeline storage buckets
create_bucket_idempotent "kijani-receipts-${STAGE}"
create_bucket_idempotent "kijani-processed-${STAGE}"
create_bucket_idempotent "kijani-notify-${STAGE}"
create_bucket_idempotent "kijani-delivered-${STAGE}"

# 5. Provision decoupled event-driven queues
create_queue_idempotent "kijani-receipts-events-${STAGE}"
create_queue_idempotent "kijani-processed-events-${STAGE}"
create_queue_idempotent "kijani-notify-events-${STAGE}"
create_queue_idempotent "kijani-delivered-events-${STAGE}"

echo "==== Configuring R2 Bucket Event Notifications to Queues ===="
# Note: These parameters establish event links between buckets and processing queues.
# If these bindings already exist, Wrangler logs the conflict gracefully and stays idempotent.

echo "Linking kijani-receipts-${STAGE} to queue..."
npx wrangler r2 bucket notification create "kijani-receipts-${STAGE}" \
  --event-type object-create \
  --prefix "receipt-" \
  --suffix ".json" \
  --queue "kijani-receipts-events-${STAGE}" || echo " -> Mapping exists or handled."

echo "Linking kijani-processed-${STAGE} to queue..."
npx wrangler r2 bucket notification create "kijani-processed-${STAGE}" \
  --event-type object-create \
  --prefix "processed-" \
  --suffix ".json" \
  --queue "kijani-processed-events-${STAGE}" || echo " -> Mapping exists or handled."

echo "Linking kijani-notify-${STAGE} to queue..."
npx wrangler r2 bucket notification create "kijani-notify-${STAGE}" \
  --event-type object-create \
  --prefix "notify-" \
  --suffix ".json" \
  --queue "kijani-notify-events-${STAGE}" || echo " -> Mapping exists or handled."

echo "Linking kijani-delivered-${STAGE} to queue..."
npx wrangler r2 bucket notification create "kijani-delivered-${STAGE}" \
  --event-type object-create \
  --prefix "delivered-" \
  --suffix ".json" \
  --queue "kijani-delivered-events-${STAGE}" || echo " -> Mapping exists or handled."

echo "==== Cloudflare Infrastructure Provisioning Complete for Stage: ${STAGE} ===="
