#!/usr/bin/env bash
# suhail-git.sh — deterministic git plumbing helper for Suhail's per-Part patch isolation.
#
# Every subcommand works through a temporary index file (GIT_INDEX_FILE).
# The user's working tree is never touched, and user-authored index state is
# never clobbered: after a commit, pristine real-index entries for the
# committed paths are synced to the new HEAD so git status stays clean, while
# any entry the user staged themselves is left exactly as it was. Commits are
# created via plumbing (commit-tree + update-ref), so commit hooks
# (pre-commit, commit-msg, post-commit) do NOT run — a documented
# orchestrator-level trade-off.
#
# Usage:
#   suhail-git.sh snapshot
#       Print a tree id capturing the current working tree state: tracked
#       changes AND untracked files, respecting .gitignore.
#   suhail-git.sh patch <tree_a> <tree_b> <out_file>
#       Write the binary diff between the two trees to <out_file>, excluding
#       .suhail (Suhail's own artifacts never belong in Part patches), and
#       print the changed paths one per line to stdout. An empty diff yields
#       an empty <out_file> and no stdout.
#   suhail-git.sh commit <patch_file> <msg_file>
#       Commit EXACTLY the patch on top of HEAD via a temporary index and
#       print the new commit id. Requires an existing HEAD commit.
#   suhail-git.sh --help
#
# Exit codes:
#   0  success
#   1  environment error: not inside a git work tree, invalid tree id,
#      unborn HEAD, missing input file, or unwritable out file
#   2  usage error: unknown subcommand or wrong argument count
#   3  patch does not apply cleanly to HEAD
#   4  nothing to commit: empty patch file, or patch produces the HEAD tree

set -euo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

die1() { echo "error: $*" >&2; exit 1; }

usage() {
  {
    echo "usage: suhail-git.sh snapshot"
    echo "       suhail-git.sh patch <tree_a> <tree_b> <out_file>"
    echo "       suhail-git.sh commit <patch_file> <msg_file>"
  } >&2
  exit 2
}

TMP_INDEX=""
cleanup() {
  if [[ -n "$TMP_INDEX" ]]; then
    rm -f "$TMP_INDEX" "$TMP_INDEX.lock"
  fi
}
trap cleanup EXIT

require_work_tree() {
  if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    die1 "not inside a git work tree"
  fi
}

head_exists() {
  git rev-parse -q --verify 'HEAD^{commit}' >/dev/null
}

# ---------------------------------------------------------------------------
# snapshot — tree id of the current working tree (tracked + untracked)
# ---------------------------------------------------------------------------

cmd_snapshot() {
  require_work_tree
  TMP_INDEX="$(mktemp)"
  export GIT_INDEX_FILE="$TMP_INDEX"
  if head_exists; then
    git read-tree HEAD || die1 "read-tree HEAD failed"
  else
    git read-tree --empty || die1 "read-tree --empty failed"
  fi
  git add -A || die1 "add -A failed"
  git write-tree || die1 "write-tree failed"
}

# ---------------------------------------------------------------------------
# patch — exact diff between two snapshot trees, .suhail excluded
# ---------------------------------------------------------------------------

cmd_patch() {
  local tree_a="$1" tree_b="$2" out_file="$3"
  require_work_tree
  git rev-parse -q --verify "${tree_a}^{tree}" >/dev/null || die1 "invalid tree id: $tree_a"
  git rev-parse -q --verify "${tree_b}^{tree}" >/dev/null || die1 "invalid tree id: $tree_b"

  # Absolutize so --output lands exactly where the caller said, regardless of
  # how git resolves relative paths internally. Pre-create/truncate it so an
  # empty diff still leaves an empty file and unwritable paths fail as exit 1.
  case "$out_file" in
    /*) ;;
    *) out_file="$PWD/$out_file" ;;
  esac
  : > "$out_file" 2>/dev/null || die1 "cannot write out file: $out_file"

  git diff --binary --full-index --output="$out_file" "$tree_a" "$tree_b" -- . ':(exclude).suhail' \
    || die1 "diff failed"
  git diff --name-only "$tree_a" "$tree_b" -- . ':(exclude).suhail' \
    || die1 "diff --name-only failed"
}

# ---------------------------------------------------------------------------
# commit — land exactly one patch on HEAD via a temporary index
# ---------------------------------------------------------------------------

cmd_commit() {
  local patch_file="$1" msg_file="$2"
  require_work_tree
  [[ -f "$patch_file" ]] || die1 "patch file not found: $patch_file"
  [[ -f "$msg_file" ]] || die1 "message file not found: $msg_file"
  head_exists || die1 "HEAD does not exist (unborn branch) — create an initial commit first"

  if [[ ! -s "$patch_file" ]]; then
    echo "error: nothing to commit: patch file is empty" >&2
    exit 4
  fi

  TMP_INDEX="$(mktemp)"
  export GIT_INDEX_FILE="$TMP_INDEX"
  git read-tree HEAD || die1 "read-tree HEAD failed"

  # --check validates against HEAD content (the temp index), not the user's
  # working tree; git's own diagnostics pass through on stderr.
  if ! git apply --cached --check "$patch_file"; then
    echo "error: patch does not apply to HEAD" >&2
    exit 3
  fi
  git apply --cached "$patch_file" || die1 "apply --cached failed after a clean check"

  local tree head_tree new_commit
  tree="$(git write-tree)" || die1 "write-tree failed"
  head_tree="$(git rev-parse 'HEAD^{tree}')" || die1 "rev-parse HEAD^{tree} failed"
  if [[ "$tree" == "$head_tree" ]]; then
    echo "error: nothing to commit: patch produces the HEAD tree" >&2
    exit 4
  fi

  # commit-tree is plumbing and ignores commit.gpgsign — honor it explicitly
  # so Suhail Part commits sign (and verify on forges) like porcelain commits.
  local sign_opt=""
  if [[ "$(git config --get --type=bool commit.gpgsign 2>/dev/null || true)" == "true" ]]; then
    sign_opt="yes"
  fi
  new_commit="$(git commit-tree ${sign_opt:+-S} "$tree" -p HEAD -F "$msg_file")" || die1 "commit-tree failed"
  git update-ref HEAD "$new_commit" || die1 "update-ref failed"

  # Reconcile the REAL index. Without this, every committed path whose real
  # index entry still holds the pre-commit blob would show in git status as a
  # staged reversion of the Part's change — and a subsequent bare `git commit`
  # by the user would actually commit that reversion. Only pristine entries
  # are synced (index blob equal to the old-HEAD blob, or absent on both
  # sides); anything the user staged themselves is left alone.
  # GIT_INDEX_FILE must be unset first so these operations hit the real index.
  unset GIT_INDEX_FILE
  local committed_paths path idx_blob h0_blob
  committed_paths="$(git -c core.quotepath=false diff --name-only "$head_tree" "$tree")"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    idx_blob="$(git rev-parse -q --verify ":0:$path" 2>/dev/null || true)"
    h0_blob="$(git rev-parse -q --verify "${head_tree}:${path}" 2>/dev/null || true)"
    if [[ "$idx_blob" == "$h0_blob" ]]; then
      # Mixed reset syncs the index entry to the new HEAD without touching
      # the working tree; it also creates entries for new files and drops
      # them for deletions.
      git reset -q -- ":(top,literal)$path" || die1 "index reconcile failed for: $path"
    fi
  done <<< "$committed_paths"

  printf '%s\n' "$new_commit"
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

[[ $# -ge 1 ]] || usage

case "$1" in
  -h|--help)
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  snapshot)
    [[ $# -eq 1 ]] || usage
    cmd_snapshot
    ;;
  patch)
    [[ $# -eq 4 ]] || usage
    cmd_patch "$2" "$3" "$4"
    ;;
  commit)
    [[ $# -eq 3 ]] || usage
    cmd_commit "$2" "$3"
    ;;
  *)
    usage
    ;;
esac

exit 0
