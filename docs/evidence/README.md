# Verification & CI/CD Evidence Index

All screenshots in this directory were inspected prior to commit to confirm zero raw API tokens, keys, or secrets are visible.

| Artifact File | Description & Criterion Proven |
| :--- | :--- |
| **`approval.txt`** | Archived Jenkins Build `#1` human approval record capturing authorized submitter (`Anm-hub`), release justification, and UTC timestamp (`Wed Nov 11 09:32:02 UTC 2026`). |
| **`01-jenkins-build1-green-stages.png`** | Jenkins Stage View for Build `#1` showing all stages passing end-to-end across `staging` and `production` after manual approval. |
| **`02-jenkins-build2-secret-gate-failed.png`** | Jenkins Stage View and console output for Build `#2` failing at `Static & Secret Checks` on a deliberate fake secret (`file:line` only) with downstream deployment stages blocked. |
| **`03-analytics-tail-orderid.png`** | Live `wrangler tail kk-analytics-staging` output confirming `kk-analytics` logs the matching `ORD-SMOKE-*` `orderId` after processing a delivered receipt. |
| **`04-k8s-pods-and-health.png`** | Kubernetes `kubectl get pods -n kijani` showing `2/2` `1/1 Ready` pods alongside `GET /health` returning `{"status":"ok","version":"1.2.0"}`. |
| **`05-jenkins-approval-prompt.png`** | Interactive Jenkins `Production Approval Gate` prompt paused awaiting authorized submitter input (`APPROVAL_REASON`) prior to production promotion. |
