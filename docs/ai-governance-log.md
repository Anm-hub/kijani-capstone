# AI Governance Log

**Owner:** Anm-hub · **Project:** KijaniKiosk capstone, Track B (Cloudflare Workers, R2, Queues)  
**Tools covered by this log:** Claude, Gemini

Fields: (1) Date · (2) Tool · (3) Task · (4) Provided to the AI · (5) AI produced · (6) Got right · (7) Got wrong · (8) Changed before applying.

---

## Entry 1: Track and cloud-provider selection

1. **Date:** 2026-11-09
2. **Tool:** Claude
3. **Task:** Evaluate capstone tracks and choose a zero-card free-tier serverless stack after the AWS account became unusable.
4. **Provided:** Capstone guide and rubric, Week 9 and 10 course pages, and the constraint "free tier only, three working days".
5. **Produced:** Recommended Track B on Cloudflare Workers, R2, and Queues deployed with Wrangler instead of AWS and the Serverless Framework.
6. **Got right:** The event-driven chain ran cleanly on Cloudflare's free tier; `provision.sh` created all buckets, queues, and notification rules idempotently, and `deploy.sh` deployed all four Workers.
7. **Got wrong:** (a) Claimed the first deploy "may prompt" to register a `workers.dev` subdomain, whereas `wrangler deploy` failed with API error `10063` until the subdomain was initialized in the dashboard. (b) Could not confirm in advance that R2 had to be enabled in the dashboard first (error `10042`). (c) Quoted free-tier limits from search snippets without rechecking Cloudflare's live pricing page.
8. **Changed:** Enabled R2 and initialized the `workers.dev` subdomain manually in the Cloudflare dashboard before re-running `provision.sh` and `deploy.sh`.

## Entry 2: Day 1 Workers and Wrangler templating refinement

1. **Date:** 2026-11-09
2. **Tool:** Gemini
3. **Task:** Refine my initial four-Worker receipt chain (`receipts`, `processor`, `notifier`, `analytics`) and environment configuration files for `staging` and `production`.
4. **Provided:** My drafted Worker handlers, shared helper module (`workers/shared/lib.js`), and static `wrangler.toml` files.
5. **Produced:** Refinements introducing `wrangler.template.toml` with `__STAGE__` tokens, `scripts/render-config.sh`, deterministic `RCP-` SHA-256 receipt IDs, and `customMetadata` summary tags.
6. **Got right:** Parameterized templates kept `staging` and `production` resources isolated without duplicating TOML files, and `customMetadata` allowed `kk-analytics` to aggregate totals from a single `list()` call.
7. **Got wrong:** Initial template rewrite omitted top-level `name` and `main` fields above `workers_dev`, causing `wrangler deploy --dry-run` to fail, and left R2 single-page `list()` pagination limits undocumented.
8. **Changed:** Restored explicit `name` and `main` headers in all four `wrangler.template.toml` files (commits `8bc365d`, `a70a000`, `4fb7219`) and documented the 1,000-object single-page `list()` limit in `README.md`.

## Entry 3: Day 1 code review and queue consumer fixes

1. **Date:** 2026-11-09 to 2026-11-10
2. **Tool:** Claude
3. **Task:** Audit my Day 1 Worker code and shell scripts (`provision.sh`, `deploy.sh`, `smoke-test.sh`) prior to live deployment.
4. **Provided:** My committed Day 1 Worker handlers, queue consumers, and deployment scripts.
5. **Produced:** A prioritised defect list identifying an infinite queue loop in `kk-processor`, queue consumers parsing the event notification envelope instead of reading the R2 object, and missing DLQ retry handling.
6. **Got right:** Caught that `kk-processor` wrote `processed-*` back into its own trigger bucket, that R2 queue messages carry only the object key (`key`), and that `smoke-test.sh` had a fallback test string `mock-secret-key-12345` **[Control 3]**.
7. **Got wrong:** Speculated from memory that `wrangler r2 object list` might not exist and raised an unverified `pipefail` SIGPIPE concern on `grep -q`.
8. **Changed:** Added `readJson(bucket, key)` in `workers/shared/lib.js` (`cdc6871`), fixed `kk-processor` output bucket bindings (`400ffa0`), removed the hardcoded fallback key in `smoke-test.sh`, and fixed `local` used outside a function in `deploy.sh` after live testing.

## Entry 4: Day 2 Jenkins controller and Kubernetes manifest review

1. **Date:** 2026-11-10
2. **Tool:** Claude
3. **Task:** Review my drafted Jenkins controller (`jenkins/Dockerfile`, `run-jenkins.sh`), `Jenkinsfile`, and Kubernetes manifests (`k8s/`).
4. **Provided:** My initial `jenkins/Dockerfile`, `Jenkinsfile`, and five Kubernetes YAML manifests.
5. **Produced:** Targeted fixes for Docker CLI installation inside the Jenkins image, container target port alignment (`3001`), and Kubernetes Secret key naming.
6. **Got right:** Caught wrong Docker apt URLs in `jenkins/Dockerfile`, a port mismatch (`8080` vs `3001`) in `k8s/`, and invalid environment variable characters in Secret keys.
7. **Got wrong:** Stated Jenkins `input` step return behavior and AWS SDK v3 R2 checksum requirements from memory without live verification.
8. **Changed:** Updated `jenkins/Dockerfile` to copy the `docker:cli` binary (`d99d051`) and aligned ports and Secret keys (`1c6f81f`, merged in `7a6b304`).

## Entry 5: Pre-pipeline security hardening and secret scanner extraction

1. **Date:** 2026-11-11
2. **Tool:** Gemini
3. **Task:** Harden my `Jenkinsfile` and `kk-receipts` consumer before running the first live Jenkins build.
4. **Provided:** My merged `Jenkinsfile` and `workers/receipts/index.js`.
5. **Produced:** Extracted the inline `git grep` secret check into standalone `scripts/secret-scan.sh`, removed the host Docker socket mount from the Jenkins build agent **[Control 1]**, and added `isValidOrderId()` sanitization on quarantine keys **[Control 4]**.
6. **Got right:** Printing only `file:line` in `scripts/secret-scan.sh` prevented secret values from ever appearing in console logs (verified when Build `#2` failed cleanly at Stage 2 on a deliberate fake secret), and removing `/var/run/docker.sock` enforced least privilege on the build container.
7. **Got wrong:** Required adjusting `secret-scan.sh` path exclusions later when `k8s/secret.example.yaml` was renamed to `k8s/kk-payments-secret.example.yaml`.
8. **Changed:** Applied the security refinements in PR `#1` (`2810e59`) and confirmed `approval.txt` recorded the real Jenkins submitter (`Anm-hub`), justification, and UTC timestamp in Build `#1`.

## Entry 6: `kk-payments` R2 integration and Kubernetes runtime debugging

1. **Date:** 2026-11-11
2. **Tool:** Gemini
3. **Task:** Debug `502 Bad Gateway` errors when integrating my `POST /payments` endpoint (`kijanikiosk-payments`) with Cloudflare R2 on Minikube.
4. **Provided:** My `src/r2.js`, `src/server.js`, `Dockerfile.production`, `k8s/kk-payments-configmap.yaml`, and `kubectl port-forward` error logs.
5. **Produced:** Fixes adding pruned `node_modules` and `eslint.config.js` to `Dockerfile.production`, configuring `requestChecksumCalculation: "WHEN_REQUIRED"` in `src/r2.js`, and correcting `R2_ENDPOINT` in `k8s/kk-payments-configmap.yaml`.
6. **Got right:** Identified why `Dockerfile.production` failed at runtime after adding `@aws-sdk/client-s3` (`Cannot find module`), why `R2_ENDPOINT` failed DNS lookup without the account-scoped `://cloudflarestorage.com` subdomain, and how AWS SDK v3 checksums interact with R2.
7. **Got wrong:** Initial `Dockerfile.production` draft had left out `eslint.config.js` during the multi-stage copy before `--no-cache` verification caught it.
8. **Changed:** Rebuilt `ghcr.io/anm-hub/kk-payments:1.2.0-aee4e8e` with pruned `node_modules`, pinned the image tag (`8cee584`, `c847d52`), patched `R2_ENDPOINT` (`2d6acec`), and confirmed live `202 Accepted` delivery end-to-end across all four Workers.

## Entry 7: Cloud governance assessment and credential audit verification

1. **Date:** 2026-11-11
2. **Tool:** Gemini
3. **Task:** Verify zero credential leakage across both repositories and Jenkins logs, and assess the deployed stack against the six Track B governance controls.
4. **Provided:** My `git log --all -p` histories, Jenkins console logs (`#1`–`#3`), and live `wrangler tail` telemetry.
5. **Produced:** Blind `read -rs` + fixed-string `grep -cF` audit commands (`docs/credential-audit.md`) and the six-control assessment matrix (`docs/governance-review.md`).
6. **Got right:** Confirmed `0` secret occurrences across all five live credentials and surfaced real architectural gaps—such as Nairobi traffic routing through Cloudflare colos `OTP`/`BUD` due to R2 lacking an Africa jurisdiction hint **[Control 6]** and unrotated terminal API keys **[Control 3]**.
7. **Got wrong:** Initial credential scan covered only 48-character hex keys and Builds `#1` and `#3` until expanded to all five secrets and Build `#2`.
8. **Changed:** Expanded the audit to all five secrets and Builds `#1`–`#3` (`docs/credential-audit.md`) and recorded all six control findings and remediations in `docs/governance-review.md`.
