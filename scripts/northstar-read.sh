#!/usr/bin/env bash
# northstar-read.sh — read-only artifact reader for Northstar.
#
# Usage:
#   northstar-read.sh <path/to/parts/part-N>
#   northstar-read.sh --help
#
# Exit codes:
#   0  summary JSON emitted to stdout (even if some artifact files are absent)
#   1  part directory missing or unreadable; or jq not found
#
# Output: a single-line JSON object, e.g.:
#   {"part_dir":"...","review":{"verdict":"clean"},"audit":{"verdict":"blockers"},"execution":{"files_changed_count":3},"blocker":{"present":false,"from":null,"severity":null,"options":null}}

set -euo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

die1() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------

PART_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$PART_DIR" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        exit 1
      fi
      PART_DIR="$1"
      shift
      ;;
  esac
done

if [[ -z "$PART_DIR" ]]; then
  die1 "usage: northstar-read.sh <path/to/parts/part-N>"
fi

if [[ ! -d "$PART_DIR" ]]; then
  die1 "part directory not found: $PART_DIR"
fi

# ---------------------------------------------------------------------------
# jq availability check
# ---------------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  die1 "jq is required but not found on PATH; install jq to use this script"
fi

# ---------------------------------------------------------------------------
# extraction helpers
# ---------------------------------------------------------------------------

# Extract ## Verdict value from review.md or audit.md.
# Prints "null" (JSON null literal) if file absent; else the verdict word.
extract_verdict() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "null"
    return
  fi
  local verdict
  verdict="$(grep -A1 '^## Verdict' "$file" | tail -1 | tr -d '[:space:]')"
  if [[ -z "$verdict" ]]; then
    echo "null"
  else
    printf '"%s"' "$verdict"
  fi
}

# Count lines matching ^- ` under ## Files changed heading up to next ## heading.
# Prints "null" (JSON null) if file absent; else an integer.
extract_files_changed_count() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "null"
    return
  fi
  local count
  count="$(awk '
    /^## Files changed/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^- `/ { count++ }
    END { print (count+0) }
  ' "$file")"
  echo "$count"
}

# Extract blocker.md frontmatter fields.
# Sets globals: BLOCKER_PRESENT, BLOCKER_FROM, BLOCKER_SEVERITY, BLOCKER_OPTIONS
extract_blocker() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    BLOCKER_PRESENT="false"
    BLOCKER_FROM="null"
    BLOCKER_SEVERITY="null"
    BLOCKER_OPTIONS="null"
    return
  fi
  BLOCKER_PRESENT="true"

  # Extract lines between first pair of --- delimiters
  local frontmatter
  frontmatter="$(awk 'NR>1 && /^---$/ { exit } NR>1 { print }' "$file")"

  local from_raw severity_raw options_raw

  from_raw="$(echo "$frontmatter" | grep '^from:' | head -1 | sed 's/^from:[[:space:]]*//' | tr -d '[:space:]')"
  severity_raw="$(echo "$frontmatter" | grep '^severity:' | head -1 | sed 's/^severity:[[:space:]]*//' | tr -d '[:space:]')"
  options_raw="$(echo "$frontmatter" | grep '^options:' | head -1 | sed 's/^options:[[:space:]]*//')"

  if [[ -z "$from_raw" ]]; then
    BLOCKER_FROM="null"
  else
    BLOCKER_FROM="$(printf '%s' "$from_raw" | jq -Rs '.')"
  fi

  if [[ -z "$severity_raw" ]]; then
    BLOCKER_SEVERITY="null"
  else
    BLOCKER_SEVERITY="$(printf '%s' "$severity_raw" | jq -Rs '.')"
  fi

  if [[ -z "$options_raw" ]]; then
    BLOCKER_OPTIONS="null"
  else
    # options_raw is a YAML inline list like ["a","b","c"] — parse via jq
    BLOCKER_OPTIONS="$(printf '%s' "$options_raw" | jq -c '.'  2>/dev/null || echo "null")"
  fi
}

# ---------------------------------------------------------------------------
# main logic
# ---------------------------------------------------------------------------

REVIEW_FILE="$PART_DIR/review.md"
AUDIT_FILE="$PART_DIR/audit.md"
EXECUTION_FILE="$PART_DIR/execution.md"
BLOCKER_FILE="$PART_DIR/blocker.md"

review_verdict="$(extract_verdict "$REVIEW_FILE")"
audit_verdict="$(extract_verdict "$AUDIT_FILE")"
files_changed_count="$(extract_files_changed_count "$EXECUTION_FILE")"

BLOCKER_PRESENT=""
BLOCKER_FROM=""
BLOCKER_SEVERITY=""
BLOCKER_OPTIONS=""
extract_blocker "$BLOCKER_FILE"

# Encode part_dir as a JSON string safely
part_dir_json="$(printf '%s' "$PART_DIR" | jq -Rs '.')"

# Build review/audit sub-objects (verdict may be JSON null or a quoted string)
review_json="{\"verdict\":${review_verdict}}"
audit_json="{\"verdict\":${audit_verdict}}"

# Build execution sub-object (files_changed_count is integer or null)
execution_json="{\"files_changed_count\":${files_changed_count}}"

# Build blocker sub-object
blocker_json="{\"present\":${BLOCKER_PRESENT},\"from\":${BLOCKER_FROM},\"severity\":${BLOCKER_SEVERITY},\"options\":${BLOCKER_OPTIONS}}"

printf '%s\n' "{\"part_dir\":${part_dir_json},\"review\":${review_json},\"audit\":${audit_json},\"execution\":${execution_json},\"blocker\":${blocker_json}}"

exit 0
