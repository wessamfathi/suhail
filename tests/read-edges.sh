#!/usr/bin/env bash
# read-edges.sh — edge-case fixtures for suhail-read.{sh,ps1}.
#
# Every case is fed to both readers (ps1 when pwsh is on PATH) and must
# produce identical, jq-valid JSON. Cases reproduce the public-release
# review findings: quoted verdicts (JSON-escaping), multi-word verdicts
# (space preservation), blank line before the verdict, a heading with no
# verdict at all, CRLF blocker frontmatter, and attempt-numbered execution
# artifacts.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
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

for lang in "${LANGS[@]}"; do
  assert_read_field "plain verdict"              "$lang" "$d"  '.review.verdict' '"clean"'
  assert_read_field "quoted verdict escapes"     "$lang" "$dq" '.review.verdict' '"\"clean\""'
  assert_read_field "two-word verdict keeps space" "$lang" "$dw" '.review.verdict' '"needs work"'
  assert_read_field "blank line then verdict"    "$lang" "$db" '.review.verdict' '"clean"'
  assert_read_field "heading as last line -> null" "$lang" "$dl" '.review.verdict' 'null'
  assert_read_field "next heading, no verdict -> null" "$lang" "$dh" '.review.verdict' 'null'
  assert_read_field "indented next heading -> null"    "$lang" "$di" '.review.verdict' 'null'
  assert_read_field "absent audit -> null"       "$lang" "$d"  '.audit.verdict' 'null'
  assert_read_field "CRLF blocker: from"         "$lang" "$dc" '.blocker.from' '"su-executer"'
  assert_read_field "CRLF blocker: severity"     "$lang" "$dc" '.blocker.severity' '"blocker"'
  assert_read_field "CRLF blocker: options"      "$lang" "$dc" '.blocker.options' '["Retry","Skip"]'
  assert_read_field "latest attempt file wins"   "$lang" "$da" '.execution.files_changed_count' '3'
  assert_read_field "orig.md renames are ignored" "$lang" "$do_" '.execution.files_changed_count' '1'
done

# --- parity: both readers byte-agree after jq normalization -----------------------
if [[ "$HAVE_PWSH" -eq 1 ]]; then
  for dir in "$d" "$dq" "$dw" "$db" "$dl" "$dh" "$di" "$dc" "$da" "$do_"; do
    sh_out="$(bash "$SCRIPTS_DIR/suhail-read.sh" "$dir" | jq -S -c .)"
    ps_out="$(pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-read.ps1" "$dir" | jq -S -c 'del(.part_dir)')"
    sh_cmp="$(printf '%s' "$sh_out" | jq -S -c 'del(.part_dir)')"
    assert_eq "reader parity: $(basename "$dir")" "$sh_cmp" "$ps_out"
  done
fi

summary "read-edges"
