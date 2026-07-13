#!/usr/bin/env bash
# read-edges.sh — edge-case fixtures for suhail-read.{sh,ps1}.
#
# Every case is fed to both readers (ps1 when pwsh is on PATH) and must
# produce identical, jq-valid JSON. Verdict cases lock in the fail-closed
# enum contract: only clean/concerns/blockers (case-insensitive, emitted
# lowercase) are accepted; quoted verdicts, prose, and near-misses yield
# null. Remaining cases cover blank line before the verdict, a heading with
# no verdict at all, CRLF blocker frontmatter, and attempt-numbered
# execution artifacts.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
source ./helpers.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkpart() { local d="$WORK/$1"; mkdir -p "$d"; echo "$d"; }

# --- verdict extraction -------------------------------------------------------

d="$(mkpart plain)"
printf '## Verdict\nclean\n' > "$d/review.md"

dq="$(mkpart quoted)"
printf '## Verdict\n"clean"\n' > "$dq/review.md"

dw="$(mkpart twoword)"
printf '## Verdict\nneeds work\n' > "$dw/review.md"

db="$(mkpart blankline)"
printf '## Verdict\n\nclean\n' > "$db/review.md"

dl="$(mkpart lastline)"
printf 'body text\n## Verdict\n' > "$dl/review.md"

dh="$(mkpart nextheading)"
printf '## Verdict\n\n## Notes\nunrelated\n' > "$dh/review.md"

di="$(mkpart indentedheading)"
printf '## Verdict\n\n  ## Notes\nunrelated\n' > "$di/review.md"

# --- fail-closed enum cases ------------------------------------------------------

dap="$(mkpart approved)"
printf '## Verdict\napproved\n' > "$dap/review.md"

dsg="$(mkpart singularblocker)"
printf '## Verdict\nblocker\n' > "$dsg/review.md"

dmc="$(mkpart mixedcaseclean)"
printf '## Verdict\nClean\n' > "$dmc/review.md"

dmb="$(mkpart uppercaseblockers)"
printf '## Verdict\nBLOCKERS\n' > "$dmb/review.md"

dts="$(mkpart trailingspaces)"
printf '## Verdict\nclean   \n' > "$dts/review.md"

dvp="$(mkpart validthenprose)"
printf '## Verdict\nclean\nThis part looks solid overall and needs no follow-up.\n' > "$dvp/review.md"

dpv="$(mkpart prosethenvalid)"
printf '## Verdict\nsome prose\nclean\n' > "$dpv/review.md"

# --- CRLF blocker frontmatter ---------------------------------------------------

dc="$(mkpart crlf)"
printf -- '---\r\nfrom: su-executer\r\nseverity: blocker\r\noptions: ["Retry", "Skip"]\r\n---\r\nBlocked on a thing.\r\n' > "$dc/blocker.md"

# --- attempt-numbered execution artifacts ----------------------------------------

da="$(mkpart attempts)"
printf '## Files changed\n- `a.md`\n' > "$da/execution.md"
printf '## Files changed\n- `a.md`\n- `b.md`\n- `c.md`\n' > "$da/execution-attempt-2.md"

# /su retry renames attempts to *.orig.md — those must NOT be picked up
do_="$(mkpart origfiles)"
printf '## Files changed\n- `fresh.md`\n' > "$do_/execution.md"
printf '## Files changed\n- `stale1.md`\n- `stale2.md`\n' > "$do_/execution-attempt-2.orig.md"

# blocker.md with a missing key must yield nulls, not a reader crash
dm="$(mkpart missingkeys)"
printf -- '---\nfrom: su-scout\noptions: ["Retry"]\n---\nNo severity here.\n' > "$dm/blocker.md"

# single-element options list must stay a JSON array on every host
ds="$(mkpart singleopt)"
printf -- '---\nfrom: orchestrator\nseverity: blocker\noptions: ["Retry"]\n---\nOne option.\n' > "$ds/blocker.md"

for lang in "${LANGS[@]}"; do
  assert_read_field "plain verdict"              "$lang" "$d"  '.review.verdict' '"clean"'
  assert_read_field "quoted verdict -> null (fail closed)" "$lang" "$dq" '.review.verdict' 'null'
  assert_read_field "two-word prose verdict -> null (fail closed)" "$lang" "$dw" '.review.verdict' 'null'
  assert_read_field "blank line then verdict"    "$lang" "$db" '.review.verdict' '"clean"'
  assert_read_field "approved -> null (not in enum)"       "$lang" "$dap" '.review.verdict' 'null'
  assert_read_field "singular blocker -> null (not in enum)" "$lang" "$dsg" '.review.verdict' 'null'
  assert_read_field "Clean normalizes to lowercase"        "$lang" "$dmc" '.review.verdict' '"clean"'
  assert_read_field "BLOCKERS normalizes to lowercase"     "$lang" "$dmb" '.review.verdict' '"blockers"'
  assert_read_field "trailing spaces still accepted"       "$lang" "$dts" '.review.verdict' '"clean"'
  assert_read_field "valid first line then prose accepted" "$lang" "$dvp" '.review.verdict' '"clean"'
  assert_read_field "prose first line -> null even if enum follows" "$lang" "$dpv" '.review.verdict' 'null'
  assert_read_field "heading as last line -> null" "$lang" "$dl" '.review.verdict' 'null'
  assert_read_field "next heading, no verdict -> null" "$lang" "$dh" '.review.verdict' 'null'
  assert_read_field "indented next heading -> null"    "$lang" "$di" '.review.verdict' 'null'
  assert_read_field "absent audit -> null"       "$lang" "$d"  '.audit.verdict' 'null'
  assert_read_field "CRLF blocker: from"         "$lang" "$dc" '.blocker.from' '"su-executer"'
  assert_read_field "CRLF blocker: severity"     "$lang" "$dc" '.blocker.severity' '"blocker"'
  assert_read_field "CRLF blocker: options"      "$lang" "$dc" '.blocker.options' '["Retry","Skip"]'
  assert_read_field "latest attempt file wins"   "$lang" "$da" '.execution.files_changed_count' '3'
  assert_read_field "orig.md renames are ignored" "$lang" "$do_" '.execution.files_changed_count' '1'
  assert_read_field "missing severity key -> null, no crash" "$lang" "$dm" '.blocker.severity' 'null'
  assert_read_field "missing key: from still parsed"         "$lang" "$dm" '.blocker.from' '"su-scout"'
  assert_read_field "single-option list stays an array"      "$lang" "$ds" '.blocker.options' '["Retry"]'
done

# --- parity: both readers byte-agree after jq normalization -----------------------
# Exit codes and non-empty output are asserted first so a case where BOTH
# readers crash can never pass as vacuous ""=="" parity.
if [[ "$HAVE_PWSH" -eq 1 ]]; then
  for dir in "$d" "$dq" "$dw" "$db" "$dl" "$dh" "$di" "$dap" "$dsg" "$dmc" "$dmb" "$dts" "$dvp" "$dpv" "$dc" "$da" "$do_" "$dm" "$ds"; do
    if ! sh_raw="$(bash "$SCRIPTS_DIR/suhail-read.sh" "$dir")"; then
      fail "reader parity: $(basename "$dir")" "sh reader exited non-zero"; continue
    fi
    if ! ps_raw="$(pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-read.ps1" "$dir")"; then
      fail "reader parity: $(basename "$dir")" "ps1 reader exited non-zero"; continue
    fi
    if [[ -z "$sh_raw" || -z "$ps_raw" ]]; then
      fail "reader parity: $(basename "$dir")" "empty reader output"; continue
    fi
    sh_cmp="$(printf '%s' "$sh_raw" | jq -S -c 'del(.part_dir)')"
    ps_cmp="$(printf '%s' "$ps_raw" | jq -S -c 'del(.part_dir)')"
    assert_eq "reader parity: $(basename "$dir")" "$sh_cmp" "$ps_cmp"
  done
fi

summary "read-edges"
