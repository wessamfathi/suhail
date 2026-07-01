#!/usr/bin/env bash
# northstar-clean.sh — remove Northstar run artefacts from the current directory.
#
# Usage:
#   northstar-clean.sh
#   northstar-clean.sh --help
#
# Exit codes:
#   0  cleanup complete (idempotent — no error if nothing to remove)
#   1  unknown flag passed
#
# Output:
#   Removes .northstar/ directory and any .northstar-*.txt marker files
#   found in the current working directory. Safe to run multiple times.

set -euo pipefail

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
    *)
      echo "error: unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------

rm -rf .northstar
rm -f .northstar-*.txt

exit 0
