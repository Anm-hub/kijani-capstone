# Credential Leakage Audit

* **Audit Date:** 2026-11-12
* **Method:** Read all five live secrets via `read -rs` (without shell echo or history) and ran fixed-string counts (`grep -cF`) against `git log --all -p` across both repositories and all saved Jenkins build logs.
* **Scope:** Covers the entire Git commit history of `kijani-capstone` and `kijanikiosk-payments`, plus Jenkins console logs for **Builds `#1`, `#2`, and `#3` only**. Subsequent documentation-triggered builds after `#3` were aborted at the approval gate and were not included in this log scan.

## 1. Git History Audit (All Branches & Commits)

| Secret Checked | `kijani-capstone` Matches | `kijanikiosk-payments` Matches |
| :--- | :---: | :---: |
| Cloudflare API Token | 0 | 0 |
| R2 Access Key ID | 0 | 0 |
| R2 Secret Access Key | 0 | 0 |
| Staging API Key | 0 | 0 |
| Production API Key | 0 | 0 |

## 2. Jenkins Build Logs Audit (Builds #1 – #3)
### Build #1 (`#1.txt` — Full Staging & Production Promotion)
* Cloudflare API Token: 0
* R2 Access Key ID: 0
* R2 Secret Access Key: 0
* Staging API Key: 0
* Production API Key: 0

### Build #2 (`#2.txt` — Static Secret Scan Fault Gate)
* Cloudflare API Token: 0
* R2 Access Key ID: 0
* R2 Secret Access Key: 0
* Staging API Key: 0
* Production API Key: 0

### Build #3 (`#3.txt` — Post-Fault Recovery Run)
* Cloudflare API Token: 0
* R2 Access Key ID: 0
* R2 Secret Access Key: 0
* Staging API Key: 0
* Production API Key: 0
