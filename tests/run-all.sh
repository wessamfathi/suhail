#!/usr/bin/env bash
# run-all.sh — run the full Suhail test harness.
#
# Usage: ./tests/run-all.sh
# Exit 0 iff every suite passes. Requires bash + jq; exercises the
# PowerShell implementations too when pwsh is on PATH (always in CI).

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

overall=0
for suite in tick-matrix.sh read-edges.sh write-checks.sh payload-checks.sh git-isolation.sh; do
  printf '\n=== %s ===\n' "$suite"
  bash "$suite" || overall=1
done

printf '\n'
if [[ "$overall" -eq 0 ]]; then
  echo "ALL SUITES PASSED"
else
  echo "SUITE FAILURES — see above"
fi
exit "$overall"
