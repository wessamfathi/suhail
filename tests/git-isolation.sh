#!/usr/bin/env bash
# git-isolation.sh — behavior checks for suhail-git.{sh,ps1}.
#
# Builds throwaway git repos and asserts the plumbing contract: snapshot
# captures tracked + untracked state without touching the real index, patch
# isolates exactly one Part's changes (excluding .suhail), and commit lands
# exactly the patch on HEAD while unrelated staged/dirty user state survives.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
source ./helpers.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# run_git <lang> <workdir> <args...> — sets GIT_OUT, GIT_ERR, GIT_CODE
run_git() {
  local lang="$1" dir="$2"
  shift 2
  local errf
  errf="$(mktemp)"
  if [[ "$lang" == "sh" ]]; then
    GIT_OUT="$( (cd "$dir" && bash "$SCRIPTS_DIR/suhail-git.sh" "$@") 2>"$errf" )" && GIT_CODE=0 || GIT_CODE=$?
  else
    GIT_OUT="$( (cd "$dir" && pwsh -NoProfile -File "$SCRIPTS_DIR/suhail-git.ps1" "$@") 2>"$errf" )" && GIT_CODE=0 || GIT_CODE=$?
  fi
  GIT_ERR="$(cat "$errf")"
  rm -f "$errf"
}

# make_repo <dir> — init a repo with a base commit:
# base.txt, other.txt, target.txt, and a .gitignore ignoring ignored.txt
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q 2>/dev/null
  git -C "$dir" config user.name "Suhail Test"
  git -C "$dir" config user.email "suhail@test.invalid"
  git -C "$dir" config commit.gpgsign false
  printf 'line1\n' >"$dir/base.txt"
  printf 'other\n' >"$dir/other.txt"
  printf 'target v0\n' >"$dir/target.txt"
  printf 'ignored.txt\n' >"$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "base"
}

# assert_tree_id <name> <value>
assert_tree_id() {
  if [[ "$2" =~ ^[0-9a-f]{40,64}$ ]]; then pass "$1"; else fail "$1" "not a tree id: $2"; fi
}

for lang in "${LANGS[@]}"; do
  base="$WORK/$lang"

  # --- 1. snapshot → edit → snapshot → patch --------------------------------
  r="$base/case1/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot
  assert_eq "1: snapshot A exits 0 [$lang]" "0" "$GIT_CODE"
  A="$GIT_OUT"
  assert_tree_id "1: snapshot A prints a tree id [$lang]" "$A"
  printf 'line2\n' >>"$r/base.txt"
  run_git "$lang" "$r" snapshot
  assert_eq "1: snapshot B exits 0 [$lang]" "0" "$GIT_CODE"
  B="$GIT_OUT"
  p="$base/case1/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  assert_eq "1: patch exits 0 [$lang]" "0" "$GIT_CODE"
  assert_eq "1: name list is exactly base.txt [$lang]" "base.txt" "$GIT_OUT"
  assert_contains "1: patch file contains the edit [$lang]" "+line2" "$(cat "$p")"
  run_git "$lang" "$r" patch "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$B" "$base/case1/bad.patch"
  assert_eq "1: bad tree id exits 1 [$lang]" "1" "$GIT_CODE"
  assert_contains "1: bad tree id message [$lang]" "invalid tree id" "$GIT_ERR"

  # --- 2. untracked file appears; .gitignore'd file does not ----------------
  r="$base/case2/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  printf 'new\n' >"$r/new.txt"
  printf 'secret\n' >"$r/ignored.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case2/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  assert_eq "2: patch exits 0 [$lang]" "0" "$GIT_CODE"
  assert_contains "2: untracked file in name list [$lang]" "new.txt" "$GIT_OUT"
  if [[ "$GIT_OUT" == *"ignored.txt"* ]]; then
    fail "2: ignored file absent from name list [$lang]" "found ignored.txt in: $GIT_OUT"
  else
    pass "2: ignored file absent from name list [$lang]"
  fi
  assert_eq "2: real index untouched by snapshot [$lang]" "" "$(git -C "$r" diff --cached --name-only)"

  # --- 3. .suhail paths excluded from patch and name list -------------------
  r="$base/case3/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  mkdir -p "$r/.suhail/parts/part-1"
  printf 'state\n' >"$r/.suhail/state.json"
  printf 'brief\n' >"$r/.suhail/parts/part-1/brief.md"
  printf 'real\n' >"$r/real.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case3/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  assert_eq "3: name list is exactly real.txt [$lang]" "real.txt" "$GIT_OUT"
  if grep -q '\.suhail' "$p"; then
    fail "3: patch file has no .suhail paths [$lang]" "$(grep '\.suhail' "$p" | head -3)"
  else
    pass "3: patch file has no .suhail paths [$lang]"
  fi

  # --- 4. commit lands exactly the patch; user index/worktree survive -------
  r="$base/case4/repo"; make_repo "$r"
  head0="$(git -C "$r" rev-parse HEAD)"
  printf 'staged\n' >"$r/staged.txt"
  git -C "$r" add staged.txt
  printf 'dirty\n' >>"$r/other.txt"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  printf 'target v1\n' >"$r/target.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case4/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  assert_eq "4: patch isolates the part edit [$lang]" "target.txt" "$GIT_OUT"
  msg="$base/case4/msg.txt"
  printf 'part-1: change target\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "4: commit exits 0 [$lang]" "0" "$GIT_CODE"
  new="$GIT_OUT"
  assert_eq "4: HEAD advanced to printed commit [$lang]" "$new" "$(git -C "$r" rev-parse HEAD)"
  assert_eq "4: parent is old HEAD [$lang]" "$head0" "$(git -C "$r" rev-parse HEAD^)"
  assert_eq "4: commit contains exactly target.txt [$lang]" "target.txt" \
    "$(git -C "$r" diff-tree --no-commit-id --name-only -r HEAD)"
  assert_contains "4: commit contains the edit [$lang]" "+target v1" "$(git -C "$r" show HEAD)"
  assert_contains "4: commit message from msg file [$lang]" "part-1: change target" \
    "$(git -C "$r" log -1 --pretty=%B)"
  assert_eq "4: unrelated staged file stays staged [$lang]" "staged.txt" \
    "$(git -C "$r" diff --cached --name-only -- staged.txt)"
  assert_eq "4: unrelated dirty file stays dirty [$lang]" "other.txt" \
    "$(git -C "$r" diff --name-only -- other.txt)"
  assert_eq "4: no phantom staged reversion for committed path [$lang]" "" \
    "$(git -C "$r" status --porcelain -- target.txt)"
  assert_eq "4: staged file content intact in index [$lang]" "staged" \
    "$(git -C "$r" show :0:staged.txt)"

  # --- 5. user edit conflicting with the patch → exit 3, HEAD unmoved -------
  r="$base/case5/repo"; make_repo "$r"
  head0="$(git -C "$r" rev-parse HEAD)"
  printf 'user version\n' >"$r/target.txt"   # uncommitted user edit
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  printf 'part version\n' >"$r/target.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case5/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  msg="$base/case5/msg.txt"
  printf 'part-1: conflicting change\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "5: conflicting patch exits 3 [$lang]" "3" "$GIT_CODE"
  assert_contains "5: does-not-apply message [$lang]" "patch does not apply to HEAD" "$GIT_ERR"
  assert_eq "5: HEAD unmoved [$lang]" "$head0" "$(git -C "$r" rev-parse HEAD)"

  # --- 6. sibling parts: two patches, two commits, each isolated ------------
  r="$base/case6/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot; SA="$GIT_OUT"
  printf 'part1\n' >>"$r/target.txt"
  run_git "$lang" "$r" snapshot; SB="$GIT_OUT"
  printf 'part2\n' >>"$r/target.txt"
  run_git "$lang" "$r" snapshot; SC="$GIT_OUT"
  p1="$base/case6/p1.patch"; p2="$base/case6/p2.patch"
  run_git "$lang" "$r" patch "$SA" "$SB" "$p1"
  run_git "$lang" "$r" patch "$SB" "$SC" "$p2"
  msg="$base/case6/msg.txt"
  printf 'part commit\n' >"$msg"
  run_git "$lang" "$r" commit "$p1" "$msg"
  assert_eq "6: part-1 commit exits 0 [$lang]" "0" "$GIT_CODE"
  c1="$GIT_OUT"
  run_git "$lang" "$r" commit "$p2" "$msg"
  assert_eq "6: part-2 commit exits 0 [$lang]" "0" "$GIT_CODE"
  c2="$GIT_OUT"
  assert_eq "6: HEAD is part-2 commit [$lang]" "$c2" "$(git -C "$r" rev-parse HEAD)"
  assert_eq "6: part-2 parent is part-1 [$lang]" "$c1" "$(git -C "$r" rev-parse HEAD^)"
  c1show="$(git -C "$r" show "$c1")"
  c2show="$(git -C "$r" show "$c2")"
  if printf '%s' "$c1show" | grep -q '^+part1$'; then
    pass "6: first commit adds part1 [$lang]"
  else
    fail "6: first commit adds part1 [$lang]" "no +part1 in git show $c1"
  fi
  if printf '%s' "$c1show" | grep -q '^+part2$'; then
    fail "6: first commit excludes part2 [$lang]" "found +part2 in git show $c1"
  else
    pass "6: first commit excludes part2 [$lang]"
  fi
  if printf '%s' "$c2show" | grep -q '^+part2$'; then
    pass "6: second commit adds part2 [$lang]"
  else
    fail "6: second commit adds part2 [$lang]" "no +part2 in git show $c2"
  fi
  if printf '%s' "$c2show" | grep -q '^+part1$'; then
    fail "6: second commit excludes part1 [$lang]" "found +part1 in git show $c2"
  else
    pass "6: second commit excludes part1 [$lang]"
  fi

  # --- 7. empty patch → exit 4, HEAD unmoved --------------------------------
  r="$base/case7/repo"; make_repo "$r"
  head0="$(git -C "$r" rev-parse HEAD)"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  p="$base/case7/p.patch"
  run_git "$lang" "$r" patch "$A" "$A" "$p"
  assert_eq "7: identical trees diff exits 0 [$lang]" "0" "$GIT_CODE"
  assert_eq "7: no names on stdout [$lang]" "" "$GIT_OUT"
  if [[ -f "$p" && ! -s "$p" ]]; then
    pass "7: out file exists and is empty [$lang]"
  else
    fail "7: out file exists and is empty [$lang]" "$(ls -l "$p" 2>&1)"
  fi
  msg="$base/case7/msg.txt"
  printf 'empty part\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "7: empty patch commit exits 4 [$lang]" "4" "$GIT_CODE"
  assert_contains "7: nothing-to-commit message [$lang]" "nothing to commit" "$GIT_ERR"
  assert_eq "7: HEAD unmoved [$lang]" "$head0" "$(git -C "$r" rev-parse HEAD)"

  # --- 8. deletion captured in patch and committed ---------------------------
  r="$base/case8/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  rm "$r/other.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case8/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  assert_eq "8: name list has deleted file [$lang]" "other.txt" "$GIT_OUT"
  assert_contains "8: patch records the deletion [$lang]" "deleted file" "$(cat "$p")"
  msg="$base/case8/msg.txt"
  printf 'part-1: delete other.txt\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "8: deletion commit exits 0 [$lang]" "0" "$GIT_CODE"
  if git -C "$r" ls-tree -r --name-only HEAD | grep -qx "other.txt"; then
    fail "8: file gone from HEAD tree [$lang]" "other.txt still in ls-tree HEAD"
  else
    pass "8: file gone from HEAD tree [$lang]"
  fi
  assert_eq "8: index entry gone after deletion commit [$lang]" "" \
    "$(git -C "$r" ls-files -- other.txt)"
  assert_eq "8: status clean for deleted path [$lang]" "" \
    "$(git -C "$r" status --porcelain -- other.txt)"

  # --- 10. new-file patch: no staged-deletion phantom after commit -----------
  r="$base/case10/repo"; make_repo "$r"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  printf 'brand new\n' >"$r/newfile.txt"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case10/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  msg="$base/case10/msg.txt"
  printf 'part-1: add newfile\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "10: new-file commit exits 0 [$lang]" "0" "$GIT_CODE"
  assert_eq "10: no staged-deletion phantom for new file [$lang]" "" \
    "$(git -C "$r" status --porcelain -- newfile.txt)"

  # --- 11. user-staged edit in another hunk of the same file survives --------
  r="$base/case11/repo"; make_repo "$r"
  big="$r/big.txt"
  for i in $(seq 1 30); do echo "line $i"; done >"$big"
  git -C "$r" add big.txt
  git -C "$r" commit -q -m "add big"
  # user edits line 2 and stages it
  awk 'NR==2{print "line 2 USER"; next} {print}' "$big" >"$big.tmp" && mv "$big.tmp" "$big"
  git -C "$r" add big.txt
  idx_before="$(git -C "$r" rev-parse :0:big.txt)"
  run_git "$lang" "$r" snapshot; A="$GIT_OUT"
  # the part edits line 28 — far enough away that the hunks cannot overlap
  awk 'NR==28{print "line 28 PART"; next} {print}' "$big" >"$big.tmp" && mv "$big.tmp" "$big"
  run_git "$lang" "$r" snapshot; B="$GIT_OUT"
  p="$base/case11/p.patch"
  run_git "$lang" "$r" patch "$A" "$B" "$p"
  msg="$base/case11/msg.txt"
  printf 'part-1: edit line 28\n' >"$msg"
  run_git "$lang" "$r" commit "$p" "$msg"
  assert_eq "11: non-conflicting same-file commit exits 0 [$lang]" "0" "$GIT_CODE"
  head_show="$(git -C "$r" show HEAD)"
  assert_contains "11: commit has the part hunk [$lang]" "+line 28 PART" "$head_show"
  if printf '%s' "$head_show" | grep -q '^+line 2 USER$'; then
    fail "11: commit excludes the user's staged hunk [$lang]" "found +line 2 USER"
  else
    pass "11: commit excludes the user's staged hunk [$lang]"
  fi
  assert_eq "11: user-staged index blob untouched [$lang]" "$idx_before" \
    "$(git -C "$r" rev-parse :0:big.txt)"

  # --- 9. not a repo → snapshot exits 1 --------------------------------------
  d="$base/case9"; mkdir -p "$d"
  run_git "$lang" "$d" snapshot
  assert_eq "9: snapshot outside a repo exits 1 [$lang]" "1" "$GIT_CODE"
  assert_contains "9: work-tree message on stderr [$lang]" "not inside a git work tree" "$GIT_ERR"

  # --- usage errors → exit 2 --------------------------------------------------
  run_git "$lang" "$d" bogus
  assert_eq "usage: unknown subcommand exits 2 [$lang]" "2" "$GIT_CODE"
  assert_contains "usage: message on stderr [$lang]" "usage:" "$GIT_ERR"
  run_git "$lang" "$d" snapshot extra
  assert_eq "usage: snapshot with extra arg exits 2 [$lang]" "2" "$GIT_CODE"
  run_git "$lang" "$d" patch onlyone
  assert_eq "usage: patch with wrong arg count exits 2 [$lang]" "2" "$GIT_CODE"
  run_git "$lang" "$d" commit onlyone
  assert_eq "usage: commit with wrong arg count exits 2 [$lang]" "2" "$GIT_CODE"
done

summary "git-isolation"
