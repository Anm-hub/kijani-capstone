# Peer Review Feedback Log

* **Reviewer:** `@salyani123` (GitHub)
* **Session Date:** 2026-11-13
* **Repository Reviewed:** `Anm-hub/kijani-capstone` (checked out at `b9cc7a3`)
* **Reciprocal Review:** Completed by `@Anm-hub` on `salyani123/kijanikiosk-devops-foundation`

## Feedback & Resolution Matrix

| Entry | Issue & GitHub Reference | Severity | Resolution | Evidence |
| :--- | :--- | :---: | :--- | :--- |
| **1** | **Truncated companion repository clone URL in `README.md`** ([Issue #1](https://github.com/Anm-hub/kijani-capstone/issues/16)): Section 4B Step 1 read `git clone https://github.com.git` instead of pointing to `kijanikiosk-payments` (and Section 5 Step 2 had `https://github.com` for the Jenkins SCM URL). | `Major` | Updated `README.md` Section 4B Step 1 to `git clone https://github.com` and Section 5 Step 2 to `https://github.com`. | Closed via PR on branch `fix/peer-review-issues` (`Closes #1`) |
| **2** | **Stale target commit reference in `docs/test-plan.md`** ([Issue #2](https://github.com/Anm-hub/kijani-capstone/issues/17)): Line 3 listed `main at 0df1639` instead of reflecting the latest `main` state reviewed (`b9cc7a3`). | `Minor` | Updated `Under test` in `docs/test-plan.md` to `latest main (reviewed at b9cc7a3)` and populated all `Peer Result` cells with `@salyani123`'s verification results. | Closed via PR on branch `fix/peer-review-issues` (`Closes #2`) |
| **3** | **Stale AI governance log entry count in `docs/test-plan.md` (`T-08`)** ([Issue #3](https://github.com/Anm-hub/kijani-capstone/issues/18)): Row `T-08` stated `4 eight-field entries`, whereas `docs/ai-governance-log.md` contains `7` entries. | `Minor` | Updated `T-08` in `docs/test-plan.md` to `7 eight-field entries` to match `docs/ai-governance-log.md`. | Closed via PR on branch `fix/peer-review-issues` (`Closes #3`) |
| **4** | **Unrotated staging and production API keys noted in `docs/governance-review.md` (`Control 3`)**: Reviewer flagged that two API keys displayed in a local terminal during initial setup still await rotation. | `Major` | **Deferred post-grading:** Live `kk-api-key-staging` and `kk-api-key-production` credentials are preserved intact so Jenkins and Cloudflare endpoints remain live for capstone evaluation; scheduled for rotation via `openssl rand -hex 24` immediately after grading. | Documented in `docs/governance-review.md` (Control 3) and `docs/credential-audit.md` (`0` matches in Git/logs) |
