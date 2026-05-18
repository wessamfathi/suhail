#!/usr/bin/env bash
# northstar-tick.sh — read-only state inspector for Northstar.
#
# Usage:
#   northstar-tick.sh <path/to/state.json>
#   northstar-tick.sh --help
#
# Exit codes:
#   0  directive JSON emitted to stdout
#   1  state.json missing, unreadable, or unparseable; or jq not found
#   2  unknown run_phase encountered
#
# Output: a single-line JSON object, e.g.:
#   {"action":"dispatch_scout","part_id":"part-1"}
#   {"action":"await_approval"}
#   {"action":"complete"}
#   {"action":"noop","reason":"<text>"}

set -euo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

die1() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------

STATE_FILE=""

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
      if [[ -n "$STATE_FILE" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        exit 1
      fi
      STATE_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$STATE_FILE" ]]; then
  die1 "usage: northstar-tick.sh <path/to/state.json>"
fi

if [[ ! -f "$STATE_FILE" ]]; then
  die1 "state file not found: $STATE_FILE"
fi

# ---------------------------------------------------------------------------
# jq availability check
# ---------------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  die1 "jq is required but not found on PATH; install jq to use this script"
fi

# ---------------------------------------------------------------------------
# parse state.json
# ---------------------------------------------------------------------------

if ! jq empty "$STATE_FILE" 2>/dev/null; then
  die1 "state file is not valid JSON: $STATE_FILE"
fi

run_phase="$(jq -r '.run_phase // "unknown"' "$STATE_FILE")"
current_part_id="$(jq -r '.current_part_id // "null"' "$STATE_FILE")"
batch_auto_approve="$(jq -r '.batch_auto_approve // false' "$STATE_FILE")"
aborted="$(jq -r '.aborted // false' "$STATE_FILE")"

# derive the directory containing state.json so artifact paths are relative to it
STATE_DIR="$(dirname "$STATE_FILE")"

# ---------------------------------------------------------------------------
# artifact path helpers
# ---------------------------------------------------------------------------

brief_exists() {
  local part_id="$1"
  [[ -f "$STATE_DIR/parts/$part_id/brief.md" ]]
}

execution_exists() {
  local part_id="$1"
  # accept execution.md or execution-attempt-N.md
  ls "$STATE_DIR/parts/$part_id/execution"*.md 2>/dev/null | grep -q .
}

review_exists() {
  local part_id="$1"
  [[ -f "$STATE_DIR/parts/$part_id/review.md" ]]
}

# ---------------------------------------------------------------------------
# state-transition logic
# ---------------------------------------------------------------------------

case "$run_phase" in

  init)
    printf '{"action":"start_batch_scouting"}\n'
    ;;

  batch_scouting)
    # Find first pending part that lacks a brief
    pending_part="$(jq -r '
      .parts[]
      | select(.status == "scouting" or .status == "pending")
      | .id
      ' "$STATE_FILE" | head -1)"

    if [[ -z "$pending_part" ]]; then
      printf '{"action":"await_approval","reason":"all parts scouted"}\n'
    elif brief_exists "$pending_part"; then
      printf '{"action":"advance_scouting","part_id":"%s"}\n' "$pending_part"
    else
      printf '{"action":"dispatch_scout","part_id":"%s"}\n' "$pending_part"
    fi
    ;;

  master_plan_approval|awaiting_plan_approval)
    printf '{"action":"await_approval","reason":"master_plan_approval"}\n'
    ;;

  executing)
    if [[ "$aborted" == "true" ]]; then
      printf '{"action":"aborted"}\n'
      exit 0
    fi

    if [[ -z "$current_part_id" || "$current_part_id" == "null" ]]; then
      printf '{"action":"noop","reason":"no current_part_id in executing phase"}\n'
      exit 0
    fi

    # Determine current_step from parts array
    current_step="$(jq -r --arg pid "$current_part_id" '
      .parts[] | select(.id == $pid) | .status
      ' "$STATE_FILE")"

    case "$current_step" in
      pending|scouting)
        if brief_exists "$current_part_id"; then
          printf '{"action":"dispatch_executer","part_id":"%s"}\n' "$current_part_id"
        else
          printf '{"action":"dispatch_scout","part_id":"%s"}\n' "$current_part_id"
        fi
        ;;
      executing)
        if execution_exists "$current_part_id"; then
          printf '{"action":"dispatch_verifier","part_id":"%s"}\n' "$current_part_id"
        else
          printf '{"action":"dispatch_executer","part_id":"%s"}\n' "$current_part_id"
        fi
        ;;
      verifying)
        if review_exists "$current_part_id"; then
          printf '{"action":"advance_after_review","part_id":"%s"}\n' "$current_part_id"
        else
          printf '{"action":"dispatch_verifier","part_id":"%s"}\n' "$current_part_id"
        fi
        ;;
      awaiting_plan_approval|awaiting_part_approval)
        printf '{"action":"await_approval","part_id":"%s"}\n' "$current_part_id"
        ;;
      needs_user)
        printf '{"action":"needs_user","part_id":"%s"}\n' "$current_part_id"
        ;;
      completed|skipped)
        # Advance to next part
        next_part="$(jq -r '
          .parts[]
          | select(.status == "pending" or .status == "scouting" or .status == "executing" or .status == "verifying")
          | .id
          ' "$STATE_FILE" | head -1)"
        if [[ -z "$next_part" ]]; then
          printf '{"action":"complete","reason":"all parts terminal"}\n'
        else
          printf '{"action":"advance_to_part","part_id":"%s"}\n' "$next_part"
        fi
        ;;
      *)
        printf '{"action":"noop","reason":"unrecognised part status: %s","part_id":"%s"}\n' "$current_step" "$current_part_id"
        ;;
    esac
    ;;

  verifying)
    # Top-level verifying phase (single-part runs may use this)
    if [[ -z "$current_part_id" || "$current_part_id" == "null" ]]; then
      printf '{"action":"noop","reason":"no current_part_id in verifying phase"}\n'
      exit 0
    fi
    if review_exists "$current_part_id"; then
      printf '{"action":"advance_after_review","part_id":"%s"}\n' "$current_part_id"
    else
      printf '{"action":"dispatch_verifier","part_id":"%s"}\n' "$current_part_id"
    fi
    ;;

  needs_user)
    printf '{"action":"needs_user","part_id":"%s"}\n' "$current_part_id"
    ;;

  completed|complete)
    printf '{"action":"complete"}\n'
    ;;

  aborted)
    printf '{"action":"aborted"}\n'
    ;;

  *)
    echo "error: unknown run_phase: $run_phase" >&2
    exit 2
    ;;

esac

exit 0
