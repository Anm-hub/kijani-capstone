#!/usr/bin/env bash
# provision.sh - Idempotently configures cloud infrastructure primitives on Cloudflare.
set -euo pipefail

STAGE="${1:-staging}"
echo "==== Starting Cloudflare Resource Provisioning for Stage: ${STAGE} ===="

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

link_bucket_to_queue() {
  local bucket=$1
  local prefix=$2
  local queue=$3
  echo "Evaluating notification rules for bucket: ${bucket}..."
  
  # Check if rule exists to prevent crashing
  if npx wrangler r2 bucket notification list "${bucket}" 2>/dev/null | grep -q "${queue}"; then
    echo " -> Link already exists between bucket '${bucket}' and queue '${queue}'."
  else
    echo " -> Creating notification binding rule..."
    npx wrangler r2 bucket notification create "${bucket}" \
      --event-type object-create \
      --prefix "${prefix}" \
      --suffix ".json" \
      --queue "${queue}"
  fi
}

# 1. Provision Dead Letter Queue
create_queue_idempotent "kijani-dead-letters-${STAGE}"

# 2. Provision Storage Buckets
create_bucket_idempotent "kijani-receipts-${STAGE}"
create_bucket_idempotent "kijani-processed-${STAGE}"
create_bucket_idempotent "kijani-notify-${STAGE}"
create_bucket_idempotent "kijani-delivered-${STAGE}"

# 3. Provision Event Queues
create_queue_idempotent "kijani-receipts-events-${STAGE}"
create_queue_idempotent "kijani-processed-events-${STAGE}"
create_queue_idempotent "kijani-notify-events-${STAGE}"
create_queue_idempotent "kijani-delivered-events-${STAGE}"

# 4. Bind Notification Rules to Storage Primitives
link_bucket_to_queue "kijani-receipts-${STAGE}" "receipt-" "kijani-receipts-events-${STAGE}"
link_bucket_to_queue "kijani-processed-${STAGE}" "processed-" "kijani-processed-events-${STAGE}"
link_bucket_to_queue "kijani-notify-${STAGE}" "notify-" "kijani-notify-events-${STAGE}"
link_bucket_to_queue "kijani-delivered-${STAGE}" "delivered-" "kijani-delivered-events-${STAGE}"

echo "==== Cloudflare Infrastructure Provisioning Complete for Stage: ${STAGE} ===="

