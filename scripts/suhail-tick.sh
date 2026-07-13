#!/usr/bin/env bash
# suhail-tick.sh — read-only state inspector for Suhail.
#
# Usage:
#   suhail-tick.sh <path/to/state.json>
#   suhail-tick.sh --help
#
# Exit codes:
#   0  directive JSON emitted to stdout
#   1  state.json missing, unreadable, unparseable, or lacking a parts
#      array; or jq not found
#   2  unknown run_phase encountered
#   3  unroutable Part status in the current batch (fail-closed guard —
#      an unknown status must never be reported as batch completion)
#
# Output: a single-line JSON object, e.g.:
#   {"action":"dispatch_scout","part_id":"part-1"}
#   {"action":"await_approval","reason":"part_plan_approval","part_id":"part-1"}
#   {"action":"complete"}
#   {"action":"finished"}

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
  die1 "usage: suhail-tick.sh <path/to/state.json>"
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

if ! jq -e '(.parts | type) == "array"' "$STATE_FILE" >/dev/null 2>&1; then
  die1 "state file has no parts array: $STATE_FILE"
fi

run_phase="$(jq -r '.run_phase // "unknown"' "$STATE_FILE")"
current_part_id="$(jq -r '.current_part_id // "null"' "$STATE_FILE")"
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

# ---------------------------------------------------------------------------
# batch helpers (execute/verify cycle for the current level's parts)
# ---------------------------------------------------------------------------

# batch_first <status> [<status> ...] — lowest-numbered part in current_batch
# whose status is one of the given statuses (sorted by the numeric suffix of
# the id, not .parts[] array order). Empty current_batch falls back to all
# parts (defensive).
batch_first() {
  local statuses
  statuses="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  jq -r --argjson sts "$statuses" '
    (.current_batch // []) as $b
    | [ .parts[]
        | select(.status as $s | $sts | index($s))
        | select(($b | length) == 0 or (.id as $id | $b | index($id))) ]
    | sort_by(.id | sub("^part-"; "") | tonumber)
    | (.[0].id // empty)
    ' "$STATE_FILE"
}

# batch_directive — shared routing for the executing and batch_verifying phases.
# Executers run serially; verification is dispatched once the whole batch has
# executed; the batch completes once every part is terminal.
batch_directive() {
  if [[ "$aborted" == "true" ]]; then
    printf '{"action":"aborted"}\n'
    return
  fi

  local p
  p="$(batch_first needs_user)"
  if [[ -n "$p" ]]; then
    printf '{"action":"needs_user","part_id":"%s"}\n' "$p"
    return
  fi

  # Any part still needing execution (or a brief) — dispatch it, serially.
  p="$(batch_first executing pending scouting)"
  if [[ -n "$p" ]]; then
    if brief_exists "$p"; then
      printf '{"action":"dispatch_executer","part_id":"%s"}\n' "$p"
    else
      printf '{"action":"dispatch_scout","part_id":"%s"}\n' "$p"
    fi
    return
  fi

  # Approved-but-ungated Parts: surface the per-Part plan-approval gate.
  # (Distinct reason from the batch master_plan_approval gate so the
  # orchestrator can route it — see su.md's await_approval handlers.)
  p="$(batch_first awaiting_plan_approval)"
  if [[ -n "$p" ]]; then
    printf '{"action":"await_approval","reason":"part_plan_approval","part_id":"%s"}\n' "$p"
    return
  fi

  # Executed parts await verification. A part still marked 'verifying' on a
  # FRESH tick is an orphan (the verifying turn was interrupted) — the batch
  # verify handler re-runs it, adopting completed artifacts when present.
  p="$(batch_first executed verifying)"
  if [[ -n "$p" ]]; then
    printf '{"action":"start_batch_verifying"}\n'
    return
  fi

  # Fail closed: only positively-terminal Parts may complete the batch.
  # Any status the queries above did not route must be an error — a typo or
  # future status addition must never masquerade as batch completion.
  local stray
  stray="$(jq -r '
    (.current_batch // []) as $b
    | .parts[]
    | select(($b | length) == 0 or (.id as $id | $b | index($id)))
    | select(.status != "completed" and .status != "skipped")
    | "\(.id) has unroutable status \(.status)"
    ' "$STATE_FILE" | head -1)"
  if [[ -n "$stray" ]]; then
    echo "error: $stray" >&2
    exit 3
  fi

  # Every batch part is completed or skipped — advance the level.
  printf '{"action":"complete"}\n'
}

# ---------------------------------------------------------------------------
# state-transition logic
# ---------------------------------------------------------------------------

case "$run_phase" in

  init)
    printf '{"action":"start_batch_scouting"}\n'
    ;;

  batch_scouting)
    # Route blockers first — a halted scout must reach the user before any
    # re-dispatch can clobber artifacts or loop on a deterministic failure.
    blocked_part="$(batch_first needs_user)"
    if [[ -n "$blocked_part" ]]; then
      printf '{"action":"needs_user","part_id":"%s"}\n' "$blocked_part"
      exit 0
    fi

    # First part in the CURRENT BATCH still needing a scout/brief. Parts at
    # future levels are pending too — they must not be scouted early.
    pending_part="$(batch_first scouting pending)"

    if [[ -z "$pending_part" ]]; then
      printf '{"action":"await_approval","reason":"master_plan_approval"}\n'
    elif brief_exists "$pending_part"; then
      printf '{"action":"advance_scouting","part_id":"%s"}\n' "$pending_part"
    else
      printf '{"action":"dispatch_scout","part_id":"%s"}\n' "$pending_part"
    fi
    ;;

  master_plan_approval|awaiting_plan_approval)
    printf '{"action":"await_approval","reason":"master_plan_approval"}\n'
    ;;

  executing|batch_verifying)
    # Batched execute/verify cycle over the current level's parts.
    batch_directive
    ;;

  needs_user)
    # JSON null (not the string "null" / "") when no part id is recorded —
    # keeps both script families byte-identical on this defensive path.
    if [[ -z "$current_part_id" || "$current_part_id" == "null" ]]; then
      printf '{"action":"needs_user","part_id":null}\n'
    else
      printf '{"action":"needs_user","part_id":"%s"}\n' "$current_part_id"
    fi
    ;;

  completed|complete)
    printf '{"action":"complete"}\n'
    ;;

  finished)
    # Terminal: the run already completed cleanly. The orchestrator says so
    # in one sentence and ends the turn — no blocker, no re-dispatch.
    printf '{"action":"finished"}\n'
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
