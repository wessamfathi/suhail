#!/usr/bin/env bash
# write-checks.sh — encoding and rendering checks for suhail-write.{sh,ps1}.
#
# Asserts: state.json is written WITHOUT a UTF-8 BOM (the review caught the
# ps1 writer emitting one), STATUS.md escapes '|' in Part titles/groups so
# the Progress table cannot gain columns, and both outputs use LF only.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

STATE_JSON='{"version":1,"tool_version":"test","plan_path":"plan.md","updated_at":"2026-01-01T00:00:00Z","mode":"interactive","run_phase":"executing","current_part_id":"part-1","max_retries":3,"current_batch":["part-1"],"parts":[{"id":"part-1","title":"a | b","group":"g | h","depends_on":[],"level":0,"status":"executing","attempts":0}],"global_decisions":[],"blockers":[]}'

for lang in "${LANGS[@]}"; do
  dir="$WORK/$lang"; mkdir -p "$dir"
  state="$dir/state.json"
  if [[ "$lang" == "sh" ]]; then
    printf '%s' "$STATE_JSON" | bash "$SCRIPTS_DIR/suhail-write.sh" "$state" || { fail "writer runs [$lang]" "exit $?"; continue; }
  else
    printf '%s' "$STATE_JSON" | pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-write.ps1" "$state" || { fail "writer runs [$lang]" "exit $?"; continue; }
  fi
  pass "writer runs [$lang]"

  # no BOM on either output
  for f in "$state" "$dir/STATUS.md"; do
    if has_bom "$f"; then fail "no BOM: $(basename "$f") [$lang]" "found UTF-8 BOM"; else pass "no BOM: $(basename "$f") [$lang]"; fi
  done

  # LF only
  if grep -q $'\r' "$dir/STATUS.md"; then fail "LF only: STATUS.md [$lang]" "found CR"; else pass "LF only: STATUS.md [$lang]"; fi

  # pipe-escape: the 'a | b' title renders one row with exactly 5 columns
  row="$(grep -F 'a \| b' "$dir/STATUS.md" || true)"
  if [[ -z "$row" ]]; then
    fail "pipe-escaped title in Progress table [$lang]" "no escaped title row in STATUS.md"
  else
    cols="$(printf '%s' "$row" | sed 's/\\|//g' | awk -F'|' '{print NF-2}')"
    assert_eq "escaped title row has 5 columns [$lang]" "5" "$cols"
  fi

  # state.json round-trips
  if jq -e . "$state" >/dev/null 2>&1; then pass "state.json is valid JSON [$lang]"; else fail "state.json is valid JSON [$lang]" "jq parse failed"; fi
done

summary "write-checks"
