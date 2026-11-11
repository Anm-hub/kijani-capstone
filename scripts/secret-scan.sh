#!/usr/bin/env bash
# secret-scan.sh - High-precision credential leakage identification tool
set -euo pipefail

echo "==== Starting High-Precision Secret Leakage Scan ===="
FOUND_SECRETS=0

# Scan for assignments containing key, token, secret, or password
# Matches = or : followed by a quoted string of 12+ characters that doesn't start with $
# Excludes package-lock.json and k8s/secret.example.yaml
while IFS= read -r line; do
  # Extract file and line number only, obscuring the sensitive string value
  file_line=$(echo "$line" | cut -d: -f1,2)
  echo "CRITICAL: Hardcoded credential match found at ${file_line}"
  FOUND_SECRETS=$((FOUND_SECRETS + 1))
done < <(git grep -nIiE "(key|token|secret|password)" -- . ":(exclude)package-lock.json" ":(exclude)k8s/secret.example.yaml" | grep -E "(=|:)\s*[\"\'][^\$][A-Za-z0-9_-]{11,}[\"\']" || true)

if [ "${FOUND_SECRETS}" -gt 0 ]; then
  echo "==== Secret Leakage Scan: FAILED (${FOUND_SECRETS} matches found) ====" >&2
  exit 1
fi

echo "==== Secret Leakage Scan: PASSED ===="
exit 0
