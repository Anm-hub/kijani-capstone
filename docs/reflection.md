# Capstone Reflection — KijaniKiosk Track B Delivery

**Author:** Anm-hub · **Project:** KijaniKiosk End-to-End Serverless Receipt Chain (Cloudflare Workers, R2, Queues, Kubernetes & Jenkins)

## 1. What Did You Get Wrong?
Early in the build, I made two technical decisions that caused avoidable friction and narrowed least-privilege boundaries:
1. **Using a single shared `API_KEY` per environment (`kk-api-key-staging` and `kk-api-key-production`):** Instead of issuing separate credentials per role, I reused one 48-hex key for both write ingestion (`POST /receipts` on `kk-receipts`) and read reporting (`GET /summary` and `GET /delivered/<orderId>` on `kk-analytics`). While simple to wire into `deploy.sh` and Jenkins, it meant any client or script capable of querying analytics summaries could also inject receipts into the pipeline. Separating `INGEST_API_KEY` and `ANALYTICS_READ_KEY` from the start would have enforced true service-level least privilege without extra infrastructure cost.
2. **Hardcoding initial Wrangler and R2 endpoint assumptions before running dry-run checks:** On Day 1, I initially wrote static `wrangler.toml` files without top-level `name` and `main` fields and configured `R2_ENDPOINT` in `k8s/kk-payments-configmap.yaml` without the account-specific subdomain (`<account-id>.r2.cloudflarestorage.com`) or AWS SDK v3 `WHEN_REQUIRED` checksum flags. Generating parameterized `wrangler.template.toml` files (`scripts/render-config.sh`) and validating `npx wrangler deploy --dry-run` in CI immediately caught configuration drift before deployment.

## 2. What Is the Most Important Thing You Learned?
The most important concept I learned was **asynchronous event-driven decoupling and idempotent queue consumption**, introduced in **Weeks 9 and 10** when breaking synchronous receipt generation out of `kk-payments`.

Before this project, I thought of serverless functions primarily as lightweight HTTP endpoints that execute and return a response immediately. Building the four-stage Cloudflare R2-to-Queues chain (`kk-receipts` → `kk-processor` → `kk-notifier` → `kk-analytics`) changed how I design distributed pipelines:
* **Queue messages are pointers, not payloads:** R2 event notifications pass only the object key (`key`), so consumers must fetch the object body (`readJson`), validate schema rules (`isValidOrderId`), and isolate bad payloads under `quarantine-receipt-*` so one poison message never stalls healthy orders or exhausts retry quotas into the dead-letter queue.
* **Idempotency is mandatory when retries happen:** Because Cloudflare Queues guarantee at-least-once delivery (`max_retries = 3`), generating deterministic SHA-256 receipt IDs (`RCP-<hash>`) and overwriting deterministic R2 keys (`processed-<orderId>.json`, `delivered-<orderId>.json`) ensures duplicate deliveries never corrupt analytics totals.

## 3. What Would You Change on a Second Pass?
If I built a second pass of this system, I would make four concrete component-level changes:
1. **Add cursor pagination in `workers/analytics/index.js`:** Replace the single `DELIVERED_BUCKET.list()` call in `GET /summary` with a `do ... while (listed.truncated)` loop using `listed.cursor` so revenue and receipt counts remain accurate beyond 1,000 delivered objects.
2. **Split stage API keys by role in `scripts/deploy.sh` and `Jenkinsfile`:** Replace the shared `API_KEY` secret with distinct `INGEST_API_KEY` (`kk-receipts`) and `READ_API_KEY` (`kk-analytics`) bindings so read-only analytics consumers cannot post receipts.
3. **Add a DLQ alerting consumer and Kubernetes `NetworkPolicy`:** Attach a lightweight alert Worker to `kijani-receipts-dlq-<stage>` to log/notify whenever failed messages land in the dead-letter queue, and add `k8s/kk-payments-networkpolicy.yaml` to restrict pod ingress on port `3001`.
4. **Filter documentation-only commits in `Jenkinsfile`:** Update the SCM trigger or add a `when { not { changeset "docs/**" } }` condition so merging Markdown documentation PRs into `main` does not trigger unnecessary staging deployments that pause at `Production Approval Gate`.
