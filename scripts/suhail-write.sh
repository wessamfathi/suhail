#!/usr/bin/env bash
# suhail-write.sh — atomic state writer and STATUS.md renderer for Suhail.
#
# Usage:
#   suhail-write.sh <path/to/state.json>    # JSON payload on stdin
#   suhail-write.sh --help
#
# Exit codes:
#   0  state.json and STATUS.md written successfully
#   1  bad JSON on stdin, missing arg, or jq not found
#   2  write failure (disk error, permission denied)
#
# Output:
#   Writes state.json atomically (via tmp + mv) to the specified path.
#   Writes STATUS.md as a sibling of state.json in the same directory.
#
# Note: if the script crashes between writing state.json and writing STATUS.md,
# the two files may be out of sync. STATUS.md is a view only; state.json is the
# source of truth.

set -euo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

die1() { echo "error: $*" >&2; exit 1; }
die2() { echo "error: $*" >&2; exit 2; }

# Wrapper around jq -r that strips \r to guard against Windows jq CRLF output.
jqr() {
  jq -r "$@" | tr -d '\r'
}

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------

STATE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$STATE_PATH" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        exit 1
      fi
      STATE_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$STATE_PATH" ]]; then
  die1 "usage: suhail-write.sh <path/to/state.json>"
fi

# ---------------------------------------------------------------------------
# jq availability check
# ---------------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  die1 "jq is required but not found on PATH; install jq to use this script"
fi

# ---------------------------------------------------------------------------
# read and validate stdin payload
# ---------------------------------------------------------------------------

payload="$(cat | tr -d '\r')"

if [[ -z "$payload" ]]; then
  die1 "no JSON payload on stdin"
fi

if ! printf '%s' "$payload" | jq empty 2>/dev/null; then
  die1 "stdin payload is not valid JSON"
fi

# ---------------------------------------------------------------------------
# derive directory
# ---------------------------------------------------------------------------

STATE_DIR="$(dirname "$STATE_PATH")"

# ---------------------------------------------------------------------------
# atomic write of state.json
# ---------------------------------------------------------------------------

TMP_STATE="${STATE_PATH}.tmp"
if ! printf '%s' "$payload" > "$TMP_STATE"; then
  die2 "failed to write temporary state file: $TMP_STATE"
fi
if ! mv "$TMP_STATE" "$STATE_PATH"; then
  die2 "failed to atomically replace state file: $STATE_PATH"
fi

# ---------------------------------------------------------------------------
# extract fields from written state
# ---------------------------------------------------------------------------

tool_version="$(jqr '.tool_version // "unknown"' "$STATE_PATH")"
plan_path="$(jqr '.plan_path // ""' "$STATE_PATH")"
updated_at="$(jqr '.updated_at // ""' "$STATE_PATH")"
mode="$(jqr '.mode // "interactive"' "$STATE_PATH")"
run_phase="$(jqr '.run_phase // "unknown"' "$STATE_PATH")"
current_part_id="$(jqr '.current_part_id // "null"' "$STATE_PATH")"
max_retries="$(jqr '.max_retries // 3' "$STATE_PATH")"

plan_filename="$(basename "$plan_path")"

# ---------------------------------------------------------------------------
# emoji mapping
# ---------------------------------------------------------------------------

status_emoji() {
  local s="$1"
  case "$s" in
    completed)  printf '✅' ;;
    executing|scouting|verifying) printf '🔄' ;;
    pending)    printf '⏸' ;;
    skipped)    printf '⏭' ;;
    needs_user) printf '🛑' ;;
    aborted)    printf '❌' ;;
    finished)   printf '🏁' ;;
    *)          printf '⏸' ;;
  esac
}

# ---------------------------------------------------------------------------
# CURRENT_LINE construction
# ---------------------------------------------------------------------------

CURRENT_LINE=""

case "$run_phase" in
  batch_scouting)
    batch_ids="$(jqr '.current_batch // [] | join(", ")' "$STATE_PATH")"
    batch_level="$(jqr '
      if (.current_batch // [] | length) > 0 then
        .current_batch[0] as $id |
        (.parts // [] | map(select(.id == $id)) | .[0].level // 0)
      else 0 end
    ' "$STATE_PATH")"
    CURRENT_LINE="scouting batch [${batch_ids}] (level ${batch_level})"
    ;;
  master_plan_approval)
    batch_ids="$(jqr '.current_batch // [] | join(", ")' "$STATE_PATH")"
    batch_level="$(jqr '
      if (.current_batch // [] | length) > 0 then
        .current_batch[0] as $id |
        (.parts // [] | map(select(.id == $id)) | .[0].level // 0)
      else 0 end
    ' "$STATE_PATH")"
    CURRENT_LINE="awaiting master plan approval for [${batch_ids}] (level ${batch_level})"
    ;;
  batch_verifying)
    batch_ids="$(jqr '.current_batch // [] | join(", ")' "$STATE_PATH")"
    batch_level="$(jqr '
      if (.current_batch // [] | length) > 0 then
        .current_batch[0] as $id |
        (.parts // [] | map(select(.id == $id)) | .[0].level // 0)
      else 0 end
    ' "$STATE_PATH")"
    CURRENT_LINE="verifying batch [${batch_ids}] (level ${batch_level})"
    ;;
  finished)
    CURRENT_LINE="run complete (all Parts done)"
    ;;
  *)
    if [[ -n "$current_part_id" && "$current_part_id" != "null" ]]; then
      part_status="$(jqr --arg pid "$current_part_id" \
        '.parts // [] | map(select(.id == $pid)) | .[0].status // "unknown"' "$STATE_PATH")"
      part_attempts="$(jqr --arg pid "$current_part_id" \
        '.parts // [] | map(select(.id == $pid)) | .[0].attempts // 0' "$STATE_PATH")"
      CURRENT_LINE="Part ${current_part_id} (${part_status}, attempt ${part_attempts}/${max_retries})"
    else
      CURRENT_LINE="(none)"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# Progress table rows
# ---------------------------------------------------------------------------

progress_rows=""
part_count=0
while IFS= read -r row; do
  row="$(printf '%s' "$row" | tr -d '\r')"
  [[ -z "$row" ]] && continue
  part_count=$((part_count + 1))
  p_id="$(printf '%s' "$row" | jqr '.id // ""')"
  p_level="$(printf '%s' "$row" | jqr '.level // 0')"
  p_group="$(printf '%s' "$row" | jqr '.group // ""')"
  p_title="$(printf '%s' "$row" | jqr '.title // ""')"
  p_status="$(printf '%s' "$row" | jqr '.status // "pending"')"
  # escape '|' so a title/group can never add columns to the table
  p_group="${p_group//|/\\|}"
  p_title="${p_title//|/\\|}"
  p_emoji="$(status_emoji "$p_status")"
  progress_rows="${progress_rows}| ${part_count} | ${p_level} | ${p_group} | ${p_title} | ${p_emoji} ${p_status} |
"
done < <(jq -c '.parts // [] | .[]' "$STATE_PATH" | tr -d '\r')

# ---------------------------------------------------------------------------
# Recent decisions
# ---------------------------------------------------------------------------

decisions_text=""
decision_count=0
while IFS= read -r dec; do
  dec="$(printf '%s' "$dec" | tr -d '\r')"
  [[ -z "$dec" ]] && continue
  decision_count=$((decision_count + 1))
  if printf '%s' "$dec" | jq -e 'type == "string"' >/dev/null 2>&1; then
    dec_text="$(printf '%s' "$dec" | jqr '.')"
    decisions_text="${decisions_text}- ${dec_text}
"
  else
    dec_date="$(printf '%s' "$dec" | jqr '.date // ""')"
    dec_text="$(printf '%s' "$dec" | jqr '.text // ""')"
    if [[ -n "$dec_date" ]]; then
      decisions_text="${decisions_text}- ${dec_date} — ${dec_text}
"
    else
      decisions_text="${decisions_text}- ${dec_text}
"
    fi
  fi
done < <(jq -c '.global_decisions // [] | .[]' "$STATE_PATH" | tr -d '\r')

if [[ $decision_count -eq 0 ]]; then
  # trailing newline so the rendered section keeps the same blank-line
  # separator the PowerShell writer emits (byte parity)
  decisions_text="None.
"
fi

# ---------------------------------------------------------------------------
# Outstanding questions (blockers)
# ---------------------------------------------------------------------------

blockers_text=""
blocker_count=0
while IFS= read -r blk; do
  blk="$(printf '%s' "$blk" | tr -d '\r')"
  [[ -z "$blk" ]] && continue
  blocker_count=$((blocker_count + 1))
  blk_id="$(printf '%s' "$blk" | jqr '.part_id // ""')"
  blk_msg="$(printf '%s' "$blk" | jqr '.message // ""')"
  blockers_text="${blockers_text}- ${blk_id}: ${blk_msg}
"
done < <(jq -c '.blockers // [] | .[]' "$STATE_PATH" | tr -d '\r')

if [[ $blocker_count -eq 0 ]]; then
  blockers_text="None.
"
fi

# ---------------------------------------------------------------------------
# Artifacts list
# ---------------------------------------------------------------------------

artifacts_text=""
artifact_count=0
while IFS= read -r p_id; do
  p_id="$(printf '%s' "$p_id" | tr -d '\r')"
  [[ -z "$p_id" ]] && continue
  artifact_count=$((artifact_count + 1))
  p_num="$(printf '%s' "$p_id" | sed 's/^part-//')"
  artifacts_text="${artifacts_text}- Part ${p_num} → \`.suhail/parts/${p_id}/\`
"
done < <(jq -r '.parts // [] | .[].id' "$STATE_PATH" | tr -d '\r')

if [[ $artifact_count -eq 0 ]]; then
  artifacts_text="None.
"
fi

# ---------------------------------------------------------------------------
# render STATUS.md with LF line endings
# ---------------------------------------------------------------------------

STATUS_PATH="${STATE_DIR}/STATUS.md"

{
  printf '# Suhail \xe2\x80\x94 %s\n' "$plan_filename"
  printf '\n'
  printf 'Suhail v%s \xc2\xb7 Last tick: %s \xc2\xb7 Mode: %s \xc2\xb7 Current: %s\n' \
    "$tool_version" "$updated_at" "$mode" "$CURRENT_LINE"
  printf '\n'
  printf '## Progress\n'
  printf '\n'
  printf '| # | Level | Group | Part | Status |\n'
  printf '|---|-------|-------|------|--------|\n'
  printf '%s' "$progress_rows"
  printf '\n'
  printf '## Current focus\n'
  printf '%s\n' "$CURRENT_LINE"
  printf '\n'
  printf '## Recent decisions\n'
  printf '%s\n' "$decisions_text"
  printf '## Outstanding questions\n'
  printf '%s\n' "$blockers_text"
  printf '## Artifacts\n'
  printf '%s' "$artifacts_text"
} > "$STATUS_PATH"

exit 0
