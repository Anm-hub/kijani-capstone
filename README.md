# KijaniKiosk End-to-End Serverless Receipt Chain (Track B)

## 1. What It Is
This repository implements an event-driven, serverless receipt-processing pipeline for **KijaniKiosk** on Cloudflare (Workers, R2 Object Storage, and Queues), integrated with a containerized `kk-payments` microservice on Kubernetes and automated through a multi-stage Jenkins CI/CD pipeline. When a payment is submitted to `kk-payments`, a receipt object lands in R2, triggering a four-Worker relay chain (`kk-receipts` → `kk-processor` → `kk-notifier` → `kk-analytics`) that validates, enriches, dispatches, and aggregates transaction telemetry at the edge with zero egress fees.

> **Repository Structure Mapping Note:** In this repository, `workers/` (`receipts`, `processor`, `notifier`, `analytics`, and `shared`) corresponds to the guide's `handlers/` directory, and the parameterized `workers/*/wrangler.template.toml` files (compiled per environment via `scripts/render-config.sh`) correspond to `serverless.yml`.

## 2. Architecture
The system decouples the Kubernetes payment runtime from the asynchronous serverless edge layer via S3-compatible R2 object storage:

```text
[kk-payments (Minikube Pod :3001)]
       │  Writes receipt-<orderId>.json (AWS S3 SDK)
       ▼
[(R2: kijani-receipts-<stage>)] ──(Object Create Event)──▶ [Queue: receipts-events]
                                                                  │
       ┌──────────────────────────────────────────────────────────┘
       ▼
[Worker: kk-receipts] ──(Invalid)──▶ [(R2: kijani-processed-<stage> / quarantine-*)]
       │ (Valid: writes processed-<orderId>.json)
       ▼
[(R2: kijani-processed-<stage>)] ──(Event)──▶ [Queue: processed-events] ──▶ [Worker: kk-processor]
                                                                                   │ (Writes notify-<orderId>.json)
                                                                                   ▼
[Worker: kk-analytics] ◀── [Queue: delivered-events] ◀── [(R2: kijani-delivered-<stage>)] ◀── [Worker: kk-notifier]
  ├── GET /summary (Auth)
  └── GET /delivered/<id> (Auth)
```

* **`kk-receipts`:** Public API (`POST /receipts`, `GET /health`) and queue consumer. Validates order structure, generates deterministic receipt IDs (`RCP-` + 12-char SHA-256 prefix), and quarantines malformed payloads.
* **`kk-processor`:** Background consumer. Enriches valid receipts with `processedAt` timestamps and idempotent SHA-256 checksums.
* **`kk-notifier`:** Background consumer. Logs dispatch events and writes final records with `customMetadata` (`orderId`, `amount`, `currency`, `deliveredAt`) for fast single-list aggregation.
* **`kk-analytics`:** Background consumer and authenticated HTTP reporting API (`GET /summary`, `GET /delivered/<orderId>`). Aggregates transaction counts, currency totals, and delivery windows.

## 3. Prerequisites
Ensure the following accounts, services, and tools are configured before setup:
* **Cloudflare Account:** Free tier with **Workers**, **R2**, and **Queues** enabled, plus a **`workers.dev` subdomain** initialized in the Cloudflare dashboard (**Workers & Pages → Account Details**).
* **Node.js & Wrangler:** `Node.js v22.22.1+` and `npm v9.2.0+` (Wrangler `v4.158.0+` installs locally via `npm ci`).
* **Docker:** Docker Engine (`v24+`) with your user added to the `docker` group.
* **Minikube & `kubectl`:** Local Kubernetes cluster (`minikube` + `kubectl`) for running the `kk-payments` microservice.
* **Jenkins:** Containerized Jenkins controller (`jenkins/Dockerfile` + `jenkins/run-jenkins.sh`).
* **Standard CLI utilities:** `bash`, `curl`, `openssl`, `git`.

## 4. Setup

### A. Cloudflare Serverless Chain (`staging`)
Run the following commands from the root of this repository:

```bash
# 1. Install dependencies
npm ci

# 2. Authenticate Wrangler with your Cloudflare account
npx wrangler login

# 3. Provision R2 buckets, Queues, DLQ, and bucket-to-queue notifications (idempotent)
./scripts/provision.sh staging

# 4. Generate a 48-hex API key and deploy all four Workers with secrets injected via stdin
export API_KEY=$(openssl rand -hex 24)
./scripts/deploy.sh staging
```

### B. Kubernetes `kk-payments` Seam (Minikube)
The `kk-payments` microservice lives in the companion repository [Anm-hub/kijanikiosk-payments](https://github.com). **Note:** The container image is built locally and loaded directly into Minikube (`imagePullPolicy: IfNotPresent`); it is not pushed to GHCR.

1. **Build and load the container image from commit `aee4e8e`:**
   ```bash
   git clone https://github.com.git
   cd kijanikiosk-payments
   git checkout aee4e8e
   docker build --no-cache -f Dockerfile.production -t ghcr.io/anm-hub/kk-payments:1.2.0-aee4e8e .
   minikube start
   minikube image load ghcr.io/anm-hub/kk-payments:1.2.0-aee4e8e
   cd ../kijani-capstone
   ```
2. **Update your Cloudflare Account ID:** Edit `k8s/configmap.yaml` and replace the account ID in `R2_ENDPOINT` (`https://<your-account-id>.r2.cloudflarestorage.com`) with your own Cloudflare Account ID (`npx wrangler whoami`).
3. **Create a bucket-scoped R2 token & Kubernetes Secret:**
   * In the Cloudflare dashboard (**R2 → Manage R2 API Tokens → Create Account API Token**), create a token with **Object Read & Write** permissions scoped **exclusively to `kijani-receipts-staging`**.
   * Apply the manifests and inject the credentials imperatively using `read -rs` so nothing lands in shell history or Git:
   ```bash
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/configmap.yaml

   (
     read -rs -p "Paste R2 Access Key ID: " R2_KEY; echo ""
     read -rs -p "Paste R2 Secret Access Key: " R2_SEC; echo ""
     kubectl create secret generic cloudflare-r2-credentials \
       --namespace=kijani \
       --from-literal=R2_ACCESS_KEY_ID="$R2_KEY" \
       --from-literal=R2_SECRET_ACCESS_KEY="$R2_SEC" \
       --dry-run=client -o yaml | kubectl apply -f -
   )

   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   kubectl rollout status deployment/kk-payments -n kijani
   ```
4. **Expose the service locally via `port-forward`:**
   ```bash
   kubectl port-forward -n kijani svc/kk-payments-service 3001:3001
   ```

## 5. How to Run the Pipeline
The declarative CI/CD pipeline is defined in `Jenkinsfile` and runs on a containerized Jenkins controller:

```bash
# Start the custom Jenkins controller on http://localhost:8090
./jenkins/run-jenkins.sh
```

1. **Configure Credentials:** In Jenkins (**Manage Jenkins → Credentials → System → Global credentials**), create four **Secret text** credentials with these exact IDs:
   * `cloudflare-api-token` (custom token scoped to `Workers Scripts: Edit`, `Workers R2 Storage: Edit`, `Queues: Edit`, and `Account Settings: Read`)
   * `cloudflare-account-id` (your Cloudflare Account ID)
   * `kk-api-key-staging` (48-hex API key for staging)
   * `kk-api-key-production` (48-hex API key for production)
2. **Create Pipeline Job:** Create a **Pipeline** job configured with **Pipeline script from SCM** (`Git`), pointing to `https://github.com` with **Branch Specifier** set to `*/main` and **Script Path** set to `Jenkinsfile`.
3. **Trigger & Approval Warning:** `Jenkinsfile` includes a `pollSCM('H/2 * * * *')` trigger—**every merge to `main` automatically starts a new build** that runs static checks, deploys to staging, runs smoke tests, and **pauses at the `Production Approval Gate`**. An authorized submitter (`Anm-hub`) must supply a non-empty `APPROVAL_REASON` to archive `approval.txt` and promote to `production`.

## 6. How to Verify It Works
Run one command per acceptance criterion:

* **Criterion 1 — Live Worker Log Streaming (All 4 Workers):**
  ```bash
  ./scripts/tail-all.sh staging
  ```
* **Criterion 2 — Kubernetes `2/2 Ready` Pods & Health Check (`/health`):**
  ```bash
  kubectl get pods -n kijani && curl -s http://localhost:3001/health
  ```
* **Criterion 3 — Invalid Payment Rejected (`422`) Before Reaching R2:**
  ```bash
  curl -i -s -X POST http://localhost:3001/payments -H "Content-Type: application/json" -d '{"orderId":"bad!","amountCents":-50,"currency":"KES"}'
  ```
* **Criterion 4 — End-to-End Payment Ingestion (`K8s -> R2 -> 4 Workers`):**
  ```bash
  curl -i -s -X POST http://localhost:3001/payments -H "Content-Type: application/json" -d '{"orderId":"ORD-VERIFY-1001","amountCents":750000,"currency":"KES"}'
  ```
* **Criterion 5 — Automated Staging Smoke Test (`POST /receipts` → `GET /delivered/<id>`):**
  ```bash
  ./scripts/smoke-test.sh staging
  ```
* **Criterion 6 — Fault Isolation & Quarantine Recovery (`poison-test.sh`):**
  ```bash
  ./scripts/poison-test.sh staging
  ```
* **Criterion 7 — Static Secret Leakage Scan:**
  ```bash
  ./scripts/secret-scan.sh
  ```

## 7. Known Limitations
* **Cloudflare Wrangler Instead of Serverless Framework:** Rather than using the `serverless` CLI (`serverless.yml`) with AWS-style wrappers, this project uses native Cloudflare Wrangler templates (`wrangler.template.toml`) compiled per environment via `scripts/render-config.sh`. This avoids paid AWS dependencies and stays 100% compatible with Cloudflare's zero-card free tier for Workers, R2, and Queues.
* **Registry Pull Not Used:** `k8s/deployment.yaml` sets `imagePullPolicy: IfNotPresent` with the `kk-payments` image built locally and loaded directly into Minikube (`minikube image load`). In a multi-node production cluster, images would be pushed to GitHub Container Registry (`ghcr.io`) and pulled via an `imagePullSecret`.
* **Single-Page Analytics Listing:** `kk-analytics` aggregates revenue and receipt counts using a single `DELIVERED_BUCKET.list()` call, which returns at most 1,000 objects per page. Supporting high-volume production stores requires paginating with `list.cursor` in a loop until `list.truncated` is `false`.
* **Data Residency & Config Restarts:** Free-tier R2 buckets use automatic regional placement (`AWS_REGION: "auto"`) rather than strict geographic jurisdiction pinning. Additionally, because Kubernetes injects `R2_BUCKET` via `envFrom` at container startup, switching `kk-payments` between `staging` and `production` requires updating `k8s/configmap.yaml` and running `kubectl rollout restart deployment/kk-payments -n kijani`.
* **SCM Poll Trigger Pauses at Approval:** Because `Jenkinsfile` polls `*/main` every two minutes (`pollSCM('H/2 * * * *')`), any commit or documentation PR merged into `main` automatically triggers a pipeline run that deploys to staging and sits paused at the `Production Approval Gate` (up to the 30-minute timeout) until a human manually approves or aborts it.

