#!/usr/bin/env bash
# Northstar installer (POSIX).
#
# Usage:
#   ./scripts/install.sh                 # user-level install to ~/.claude/
#   ./scripts/install.sh --project PATH  # install into PATH/.claude/ instead
#   ./scripts/install.sh --gitignore     # with --project, also append .northstar/ to PATH/.gitignore
#   ./scripts/install.sh --force         # overwrite existing files (default refuses and prints diff)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_AGENTS="$REPO_ROOT/agents"
SRC_COMMANDS="$REPO_ROOT/commands"

FORCE=0
GITIGNORE=0
PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --gitignore) GITIGNORE=1; shift ;;
    --project)
      if [[ $# -lt 2 ]]; then
        echo "error: --project requires a path argument" >&2
        exit 2
      fi
      PROJECT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$PROJECT" ]]; then
  if [[ ! -d "$PROJECT" ]]; then
    echo "error: project path does not exist: $PROJECT" >&2
    exit 2
  fi
  DEST_BASE="$PROJECT/.claude"
  SCOPE="project ($PROJECT)"
else
  DEST_BASE="$HOME/.claude"
  SCOPE="user (~/.claude)"
  if [[ $GITIGNORE -eq 1 ]]; then
    echo "warning: --gitignore is only meaningful with --project; ignoring" >&2
    GITIGNORE=0
  fi
fi

DEST_AGENTS="$DEST_BASE/agents"
DEST_COMMANDS="$DEST_BASE/commands"
DEST_COMMANDS_SCRIPTS="$DEST_COMMANDS/scripts"

echo "Northstar installer"
echo "  scope: $SCOPE"
echo "  destination: $DEST_BASE"
echo ""

mkdir -p "$DEST_AGENTS" "$DEST_COMMANDS" "$DEST_COMMANDS_SCRIPTS"

install_file() {
  local src="$1" dest="$2"
  if [[ -f "$dest" && $FORCE -eq 0 ]]; then
    if ! cmp -s "$src" "$dest"; then
      echo "refusing to overwrite (use --force): $dest"
      echo "  diff:"
      diff -u "$dest" "$src" | sed 's/^/    /' || true
      return 1
    else
      echo "unchanged: $dest"
      return 0
    fi
  fi
  cp "$src" "$dest"
  echo "installed: $dest"
}

STATUS=0

# Cleanup: in v0.1.0 the orchestrator was shipped as agents/northstar.md.
# As of v0.1.1 the orchestrator lives in the slash command body (Claude Code
# subagents cannot spawn nested subagents). Remove the stale file if present.
STALE_ORCHESTRATOR="$DEST_AGENTS/northstar.md"
if [[ -f "$STALE_ORCHESTRATOR" ]]; then
  rm -f "$STALE_ORCHESTRATOR"
  echo "removed stale (pre-0.1.1) orchestrator subagent: $STALE_ORCHESTRATOR"
fi

for f in "$SRC_AGENTS"/*.md; do
  [[ -f "$f" ]] || continue
  install_file "$f" "$DEST_AGENTS/$(basename "$f")" || STATUS=1
done

for f in "$SRC_COMMANDS"/*.md; do
  [[ -f "$f" ]] || continue
  install_file "$f" "$DEST_COMMANDS/$(basename "$f")" || STATUS=1
done

for f in northstar-tick.ps1 northstar-tick.sh; do
  src="$REPO_ROOT/scripts/$f"
  [[ -f "$src" ]] || continue
  install_file "$src" "$DEST_COMMANDS_SCRIPTS/$f" || STATUS=1
done

if [[ $GITIGNORE -eq 1 ]]; then
  GITIGNORE_PATH="$PROJECT/.gitignore"
  if grep -qxF ".northstar/" "$GITIGNORE_PATH" 2>/dev/null; then
    echo "gitignore: .northstar/ already present in $GITIGNORE_PATH"
  else
    echo ".northstar/" >> "$GITIGNORE_PATH"
    echo "gitignore: appended .northstar/ to $GITIGNORE_PATH"
  fi
fi

echo ""
if [[ $STATUS -eq 0 ]]; then
  echo "Northstar installed. Try: /ns fixtures/test_plan.md"
else
  echo "Some files were skipped (already exist with different contents)."
  echo "Re-run with --force to overwrite."
fi
exit $STATUS
