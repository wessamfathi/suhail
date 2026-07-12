#!/usr/bin/env bash
# helpers.sh — shared assertions for the Suhail test harness.
#
# Sourced by the tests/*.sh suites. Tracks pass/fail counts and provides
# directive-level assertions that run a tick/read script and compare
# JSON output (normalized via jq -S) and exit codes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

PASS=0
FAIL=0

HAVE_PWSH=0
if command -v pwsh >/dev/null 2>&1; then
  HAVE_PWSH=1
fi

pass() { PASS=$((PASS + 1)); printf '  ok  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2 | actual: $3"; fi
}

# assert_contains <name> <needle> <haystack>
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "expected to contain: $2 | actual: $3"; fi
}

# run_tick <lang:sh|ps1> <state-file>
# Sets: TICK_OUT (stdout), TICK_ERR (stderr), TICK_CODE (exit code)
run_tick() {
  local lang="$1" state="$2" errf
  errf="$(mktemp)"
  if [[ "$lang" == "sh" ]]; then
    TICK_OUT="$(bash "$SCRIPTS_DIR/suhail-tick.sh" "$state" 2>"$errf")" && TICK_CODE=0 || TICK_CODE=$?
  else
    TICK_OUT="$(pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-tick.ps1" "$state" 2>"$errf")" && TICK_CODE=0 || TICK_CODE=$?
  fi
  TICK_ERR="$(cat "$errf")"; rm -f "$errf"
}

# assert_directive <name> <lang> <state-file> <expected-json>
# Compares jq -S normalized JSON and expects exit 0.
assert_directive() {
  local name="$1" lang="$2" state="$3" expected="$4"
  run_tick "$lang" "$state"
  if [[ "$TICK_CODE" -ne 0 ]]; then
    fail "$name [$lang]" "exit $TICK_CODE (stderr: $TICK_ERR)"
    return
  fi
  local got want
  got="$(printf '%s' "$TICK_OUT" | jq -S -c . 2>/dev/null)" || { fail "$name [$lang]" "stdout not JSON: $TICK_OUT"; return; }
  want="$(printf '%s' "$expected" | jq -S -c .)"
  if [[ "$got" == "$want" ]]; then pass "$name [$lang]"; else fail "$name [$lang]" "expected: $want | actual: $got"; fi
}

# assert_tick_error <name> <lang> <state-file> <expected-exit> <stderr-substring>
assert_tick_error() {
  local name="$1" lang="$2" state="$3" code="$4" needle="$5"
  run_tick "$lang" "$state"
  if [[ "$TICK_CODE" -ne "$code" ]]; then
    fail "$name [$lang]" "expected exit $code, got $TICK_CODE (stdout: $TICK_OUT | stderr: $TICK_ERR)"
    return
  fi
  if [[ "$TICK_ERR" == *"$needle"* ]]; then pass "$name [$lang]"; else fail "$name [$lang]" "stderr missing '$needle': $TICK_ERR"; fi
}

# run_read <lang> <part-dir> — sets READ_OUT, READ_CODE
run_read() {
  local lang="$1" dir="$2"
  if [[ "$lang" == "sh" ]]; then
    READ_OUT="$(bash "$SCRIPTS_DIR/suhail-read.sh" "$dir" 2>/dev/null)" && READ_CODE=0 || READ_CODE=$?
  else
    READ_OUT="$(pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-read.ps1" "$dir" 2>/dev/null)" && READ_CODE=0 || READ_CODE=$?
  fi
}

# assert_read_field <name> <lang> <part-dir> <jq-filter> <expected>
assert_read_field() {
  local name="$1" lang="$2" dir="$3" filter="$4" expected="$5"
  run_read "$lang" "$dir"
  if [[ "$READ_CODE" -ne 0 ]]; then fail "$name [$lang]" "exit $READ_CODE"; return; fi
  if ! printf '%s' "$READ_OUT" | jq -e . >/dev/null 2>&1; then
    fail "$name [$lang]" "output is not valid JSON: $READ_OUT"; return
  fi
  local got
  got="$(printf '%s' "$READ_OUT" | jq -c "$filter")"
  if [[ "$got" == "$expected" ]]; then pass "$name [$lang]"; else fail "$name [$lang]" "filter $filter expected $expected, got $got"; fi
}

summary() {
  printf '\n%s: %d passed, %d failed\n' "$1" "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
