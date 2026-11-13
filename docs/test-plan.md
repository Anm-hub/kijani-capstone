# KijaniKiosk Receipt Chain — One-Page Test Plan

* **Under test:** `main` at `0df1639`
* **Severity Scale:** `Critical` (blocks deployment, exposes secrets, or drops valid payments) · `Major` (degrades observability, breaks documented setup steps, or weakens controls) · `Minor` (documentation typo, formatting, or non-blocking UX polish)
* **GitHub Issue Labels:** `bug`, `documentation`, `security`

## 1. Scope & Execution Model
End-to-end verification of the `kk-payments` Kubernetes service (`POST /payments`), the four-Worker Cloudflare relay chain (`kk-receipts` → `kk-processor` → `kk-notifier` → `kk-analytics`), the Jenkins CI/CD pipeline, and the AI governance artifacts.
* **Credential-Free Reviewer Steps:** Clone repository, run `npm ci && npm test`, test `scripts/secret-scan.sh` against a temporary fake secret, and review `docs/ai-governance-log.md` and `docs/governance-review.md` for credibility.
* **Screen-Shared Host Steps:** Live `kubectl get pods -n kijani`, `POST /payments` (`202` and `422`), `wrangler tail`, and Jenkins build evidence (zero credentials shared).

## 2. Test Matrix

| ID | Area & Scenario | Verification Command / Action | Expected Outcome | Author Result (Date) | Peer Result (Name, Date) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T-01** | **A1–A3, A5 Setup & Hygiene** | Fresh clone; run `npm ci && npm test`; inspect `README.md` and `k8s/` manifest naming | `bash -n` and `secret-scan.sh` exit `0`; all 7 README sections and `{service}-{resource}.yaml` manifests present | Pass (2026-11-12) | pending |
| **T-02** | **Happy-Path Chain (`K8s -> R2 -> Workers`)** | `POST /payments` (`750000` cents, `KES`) via `port-forward`; poll `GET /delivered/<id>` | `202 Accepted`; receipt traverses all 4 buckets and returns enriched JSON within 30s | Pass (2026-11-11) | pending |
| **T-03** | **Invalid Payment Rejection** | `POST /payments` (`ORD-NEG-1`, `-50`); query `GET /delivered/ORD-NEG-1`; `wrangler r2 object get` | `422 Unprocessable Entity`; analytics returns `404`; R2 object fetch fails (`NotFound`) | Pass (2026-11-13) | pending |
| **T-04** | **Poison Receipt Quarantine** | Run `./scripts/poison-test.sh staging` (post-quarantine-key sanitization fix) | Bad payload moved to `quarantine-receipt-ORD-POISON-*.json`; follow-up `ORD-SMOKE-*` passes | Pass (2026-11-13) | pending |
| **T-05** | **A4 Secret-Scanner Fault Gate** | Add temporary 16-char `api_key = "..."` to tracked file and run `./scripts/secret-scan.sh` (plus Jenkins Build `#2`) | Exits `1` printing `file:line` only; Jenkins blocks staging/production and approval gate | Pass (2026-11-11) | pending |
| **T-06** | **Manual Production Gate & Audit** | Inspect Jenkins Build `#1` stage view and `docs/evidence/approval.txt` | Paused at `Production Approval Gate`; archived `approval.txt` records `Anm-hub`, reason, and timestamp | Pass (2026-11-11) | pending |
| **T-07** | **Credential Leakage Audit** | Review `docs/credential-audit.md` (covers git histories + Jenkins Builds `#1`–`#3` via `read -rs` + `grep -cF`) | `0` matches across all 5 secrets in both git histories and Jenkins Builds `#1`–`#3` | Pass (2026-11-12) | pending |
| **T-08** | **A6 AI Governance Credibility** | Reviewer inspects `docs/ai-governance-log.md` (4 eight-field entries) and `docs/governance-review.md` | Reviewer confirms AI defects, human fixes, and 6-control gaps are specific and credible | Pass (2026-11-13) | pending |
