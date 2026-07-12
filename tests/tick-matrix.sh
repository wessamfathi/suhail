#!/usr/bin/env bash
# tick-matrix.sh — deterministic state/action matrix for suhail-tick.{sh,ps1}.
#
# Builds synthetic state.json fixtures covering every run_phase and Part
# status, runs the tick script(s), and asserts the exact directive JSON and
# exit code. The PowerShell script is exercised with identical cases when
# pwsh is on PATH (always true in CI); otherwise those cases are skipped
# with a notice.
#
# Scenario coverage (mirrors the public-release review matrix): init entry,
# batch-scoped scouting, per-Part and master approval gates, serial executer
# dispatch, retry re-dispatch, batch verification, in-flight verifiers,
# skips, blockers (needs_user), finished re-entry, aborts, fail-closed
# unknown statuses/phases, and missing-parts preflight. Autorun / run-to /
# no-commit are orchestrator-prompt behaviors with no tick-script surface;
# their state routing is identical to the interactive cases above.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
source ./helpers.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# mkstate <run_phase> <current_part_id|null> <aborted> <current_batch-json> <parts-json>
mkstate() {
  local dir="$WORK/$RANDOM$RANDOM"
  mkdir -p "$dir/parts"
  jq -n --arg rp "$1" --arg cpid "$2" --argjson ab "$3" --argjson batch "$4" --argjson parts "$5" '
    { version: 1, tool_version: "test", run_phase: $rp,
      current_part_id: (if $cpid == "null" then null else $cpid end),
      aborted: $ab, current_batch: $batch, batch_auto_approve: false,
      parts: $parts }' > "$dir/state.json"
  echo "$dir"
}

part() { # part <n> <status> <level>
  jq -n --arg id "part-$1" --arg st "$2" --argjson lv "$3" \
    '{id: $id, title: ("Part " + $id), group: null, depends_on: [], level: $lv, trivial: false, status: $st, attempts: 0, files_changed: [], artifacts: {}}'
}

give_brief() { mkdir -p "$1/parts/part-$2"; printf '# brief\n' > "$1/parts/part-$2/brief.md"; }

P1_PENDING="$(part 1 pending 0)"
P1_EXEC="$(part 1 executing 0)"
P1_GATE="$(part 1 awaiting_plan_approval 0)"
P1_EXECD="$(part 1 executed 0)"
P1_VERIF="$(part 1 verifying 0)"
P1_DONE="$(part 1 completed 0)"
P1_NEEDS="$(part 1 needs_user 0)"
P1_BOGUS="$(part 1 zzz 0)"
P2_PENDING_L1="$(part 2 pending 1)"
P2_EXEC="$(part 2 executing 0)"
P2_EXECD="$(part 2 executed 0)"
P2_SKIP="$(part 2 skipped 0)"
P2_DONE="$(part 2 completed 0)"

for lang in "${LANGS[@]}"; do
  # --- init routes to the parallel batch-scout handler -----------------------
  d="$(mkstate init null false '[]' "[$P1_PENDING]")"
  assert_directive "init -> start_batch_scouting" "$lang" "$d/state.json" \
    '{"action":"start_batch_scouting"}'

  # --- batch_scouting: scoped to current_batch -------------------------------
  d="$(mkstate batch_scouting null false '["part-1"]' "[$P1_PENDING, $P2_PENDING_L1]")"
  assert_directive "batch_scouting: pending in batch, no brief -> dispatch_scout" "$lang" "$d/state.json" \
    '{"action":"dispatch_scout","part_id":"part-1"}'

  give_brief "$d" 1
  assert_directive "batch_scouting: pending in batch, brief exists -> advance_scouting" "$lang" "$d/state.json" \
    '{"action":"advance_scouting","part_id":"part-1"}'

  # part-2 (level 1) is pending but OUTSIDE current_batch — must NOT be scouted
  d="$(mkstate batch_scouting null false '["part-1"]' "[$P1_GATE, $P2_PENDING_L1]")"
  assert_directive "batch_scouting: only out-of-batch parts pending -> master approval" "$lang" "$d/state.json" \
    '{"action":"await_approval","reason":"master_plan_approval"}'

  # a scout-blocked Part must reach the user before any re-dispatch
  d="$(mkstate batch_scouting null false '["part-1","part-2"]' "[$P1_NEEDS, $P2_PENDING_L1]")"
  assert_directive "batch_scouting: needs_user routes before scouting" "$lang" "$d/state.json" \
    '{"action":"needs_user","part_id":"part-1"}'

  # --- master plan approval ---------------------------------------------------
  d="$(mkstate master_plan_approval null false '["part-1"]' "[$P1_GATE]")"
  assert_directive "master_plan_approval -> await_approval" "$lang" "$d/state.json" \
    '{"action":"await_approval","reason":"master_plan_approval"}'

  # --- executing: per-Part approval gate (the review's top finding) -----------
  d="$(mkstate executing part-1 false '["part-1","part-2"]' "[$P1_GATE, $P2_DONE]")"
  assert_directive "executing: awaiting_plan_approval -> part_plan_approval gate" "$lang" "$d/state.json" \
    '{"action":"await_approval","reason":"part_plan_approval","part_id":"part-1"}'

  # approved work executes before the next gate is surfaced
  d="$(mkstate executing part-2 false '["part-1","part-2"]' "[$P1_GATE, $P2_EXEC]")"
  give_brief "$d" 2
  assert_directive "executing: approved part dispatches before pending gate" "$lang" "$d/state.json" \
    '{"action":"dispatch_executer","part_id":"part-2"}'

  # --- executing: serial dispatch + retry path --------------------------------
  d="$(mkstate executing part-1 false '["part-1"]' "[$P1_EXEC]")"
  assert_directive "executing: no brief -> dispatch_scout" "$lang" "$d/state.json" \
    '{"action":"dispatch_scout","part_id":"part-1"}'
  give_brief "$d" 1
  assert_directive "executing: brief exists -> dispatch_executer (also the retry path)" "$lang" "$d/state.json" \
    '{"action":"dispatch_executer","part_id":"part-1"}'

  # same-level batch: one executed, one still executing -> serial dispatch
  d="$(mkstate executing part-2 false '["part-1","part-2"]' "[$P1_EXECD, $P2_EXEC]")"
  give_brief "$d" 2
  assert_directive "executing: sibling executed, current executing -> dispatch_executer" "$lang" "$d/state.json" \
    '{"action":"dispatch_executer","part_id":"part-2"}'

  # --- all executed -> batch verification -------------------------------------
  d="$(mkstate executing part-2 false '["part-1","part-2"]' "[$P1_EXECD, $P2_EXECD]")"
  assert_directive "executing: all executed -> start_batch_verifying" "$lang" "$d/state.json" \
    '{"action":"start_batch_verifying"}'

  # --- orphaned verifying status (interrupted session) resumes verification ------
  d="$(mkstate batch_verifying part-1 false '["part-1"]' "[$P1_VERIF]")"
  assert_directive "batch_verifying: orphaned verifying -> start_batch_verifying" "$lang" "$d/state.json" \
    '{"action":"start_batch_verifying"}'

  # --- blockers route first ----------------------------------------------------
  d="$(mkstate executing part-1 false '["part-1","part-2"]' "[$P1_NEEDS, $P2_EXEC]")"
  assert_directive "executing: needs_user routes before dispatch" "$lang" "$d/state.json" \
    '{"action":"needs_user","part_id":"part-1"}'

  # --- completed/skipped batch -> complete -------------------------------------
  d="$(mkstate executing part-2 false '["part-1","part-2"]' "[$P1_DONE, $P2_SKIP]")"
  assert_directive "executing: completed+skipped batch -> complete" "$lang" "$d/state.json" \
    '{"action":"complete"}'

  # --- fail-closed: unknown Part status must never read as completion ----------
  d="$(mkstate executing part-1 false '["part-1"]' "[$P1_BOGUS]")"
  assert_tick_error "executing: unknown part status fails closed (exit 3)" "$lang" "$d/state.json" 3 "zzz"

  # --- finished is terminal and calm --------------------------------------------
  d="$(mkstate finished null false '[]' "[$P1_DONE]")"
  assert_directive "finished -> {\"action\":\"finished\"} exit 0" "$lang" "$d/state.json" \
    '{"action":"finished"}'

  # --- needs_user phase ----------------------------------------------------------
  d="$(mkstate needs_user part-2 false '[]' "[$P1_DONE, $P2_EXEC]")"
  assert_directive "needs_user phase -> needs_user directive" "$lang" "$d/state.json" \
    '{"action":"needs_user","part_id":"part-2"}'

  # defensive path: no recorded part id -> JSON null, identical in both languages
  d="$(mkstate needs_user null false '[]' "[$P1_DONE]")"
  assert_directive "needs_user phase, null part id -> JSON null part_id" "$lang" "$d/state.json" \
    '{"action":"needs_user","part_id":null}'

  # --- aborts ---------------------------------------------------------------------
  d="$(mkstate executing part-1 true '["part-1"]' "[$P1_EXEC]")"
  assert_directive "executing + aborted flag -> aborted" "$lang" "$d/state.json" \
    '{"action":"aborted"}'
  d="$(mkstate aborted part-1 false '[]' "[$P1_EXEC]")"
  assert_directive "aborted phase -> aborted" "$lang" "$d/state.json" \
    '{"action":"aborted"}'

  # --- completed phase --------------------------------------------------------------
  d="$(mkstate completed part-1 false '[]' "[$P1_DONE]")"
  assert_directive "completed phase -> complete" "$lang" "$d/state.json" \
    '{"action":"complete"}'

  # --- unknown run_phase fails closed -------------------------------------------------
  d="$(mkstate wibble null false '[]' "[$P1_PENDING]")"
  assert_tick_error "unknown run_phase -> exit 2" "$lang" "$d/state.json" 2 "wibble"

  # --- missing parts array: clear preflight error, not a raw jq crash ----------------
  d="$WORK/noparts-$lang"; mkdir -p "$d"
  printf '{"run_phase":"executing","current_batch":[]}' > "$d/state.json"
  assert_tick_error "missing parts array -> clear exit-1 error" "$lang" "$d/state.json" 1 "parts"
done

summary "tick-matrix"
