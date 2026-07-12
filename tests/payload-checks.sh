#!/usr/bin/env bash
# payload-checks.sh — plugin payload and repo-invariant validation.
#
# Checks: YAML frontmatter parses for every command/agent file, plugin
# manifests are valid JSON with matching names, the version sync points
# agree, every tick-script directive has an orchestrator handler and every
# run_phase enum value is routed by both tick scripts, tracked files are
# LF-only with no BOM, scripts are executable, and forbidden internal
# artifacts are absent from the tree.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh
cd "$REPO_ROOT"

# --- frontmatter YAML ×14 -------------------------------------------------------
if python3 -c 'import yaml' 2>/dev/null; then
  bad="$(python3 - <<'EOF'
import re, glob, yaml
bad = []
for f in sorted(glob.glob('agents/*.md') + glob.glob('commands/*.md')):
    text = open(f, encoding='utf-8').read()
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    if not m:
        bad.append(f + ' (no frontmatter)')
        continue
    try:
        yaml.safe_load(m.group(1))
    except Exception as e:
        bad.append(f + ' (' + str(e).splitlines()[0] + ')')
print('\n'.join(bad))
EOF
)"
  if [[ -z "$bad" ]]; then pass "frontmatter YAML parses for all command/agent files"; else fail "frontmatter YAML parses" "$bad"; fi
else
  echo "NOTE: python3+PyYAML not found — frontmatter check skipped (CI runs it)"
fi

# --- manifests --------------------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  if jq -e . "$f" >/dev/null 2>&1; then pass "valid JSON: $f"; else fail "valid JSON: $f" "jq parse failed"; fi
done
assert_eq "plugin name matches marketplace entry" \
  "$(jq -r .name .claude-plugin/plugin.json)" \
  "$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)"

# --- version sync (su.md heading, su.md tool_version, README footer, plugin.json, CHANGELOG) ---
v_head="$(grep -m1 -oP '^# /su — Suhail v\K[0-9.]+' commands/su.md)"
v_tool="$(grep -m1 -oP '"tool_version": "\K[0-9.]+' commands/su.md)"
v_readme="$(grep -m1 -oP '^Suhail v\K[0-9]+\.[0-9]+\.[0-9]+' README.md)"
v_plugin="$(jq -r .version .claude-plugin/plugin.json)"
v_chlog="$(grep -m1 -oP '^## \[\K[0-9.]+' CHANGELOG.md)"
assert_eq "version sync: su.md heading vs tool_version" "$v_head" "$v_tool"
assert_eq "version sync: su.md vs README footer"        "$v_head" "$v_readme"
assert_eq "version sync: su.md vs plugin.json"          "$v_head" "$v_plugin"
assert_eq "version sync: su.md vs latest CHANGELOG"     "$v_head" "$v_chlog"

# --- directive <-> handler reachability ---------------------------------------------
directives=(start_batch_scouting dispatch_scout advance_scouting await_approval
            dispatch_executer start_batch_verifying complete finished needs_user
            aborted noop)
for a in "${directives[@]}"; do
  if grep -q "\"action\":\"$a\"" scripts/suhail-tick.sh && grep -q "\"action\`\":\`\"$a" scripts/suhail-tick.ps1; then
    pass "directive emitted by both tick scripts: $a"
  elif grep -q "\"action\":\"$a\"" scripts/suhail-tick.sh && grep -qF "\"action\":\"$a\"" scripts/suhail-tick.ps1; then
    pass "directive emitted by both tick scripts: $a"
  else
    fail "directive emitted by both tick scripts: $a" "missing from one script"
  fi
  if grep -qE "^### .?\`?$a\`?" commands/su.md; then
    pass "handler exists in su.md: $a"
  else
    fail "handler exists in su.md: $a" "no ### handler heading"
  fi
done

# no directive emitted without a handler, no dead handler without an emitter
handlers="$(grep -oP '^### `\K[a-z_]+' commands/su.md | sort -u)"
for h in $handlers; do
  if printf '%s\n' "${directives[@]}" | grep -qx "$h"; then
    pass "handler is reachable from tick scripts: $h"
  else
    fail "handler is reachable from tick scripts: $h" "no tick script emits it"
  fi
done

# every run_phase enum value in su.md's schema is routed by both tick scripts
phases="$(grep -m1 -oP '`run_phase` values: \K[^.]+' commands/su.md | tr -d '\` ' | tr '|' ' ')"
for p in $phases; do
  if grep -qE "^  $p\)|\|$p\)|  $p\|" scripts/suhail-tick.sh || grep -qE "\b$p\)" scripts/suhail-tick.sh || grep -q "$p" <(grep -oP '^\s+\K[a-z_|]+(?=\))' scripts/suhail-tick.sh | tr '|' '\n'); then
    pass "run_phase routed in tick.sh: $p"
  else
    fail "run_phase routed in tick.sh: $p" "no case arm"
  fi
  if grep -q "\"$p\"" scripts/suhail-tick.ps1; then
    pass "run_phase routed in tick.ps1: $p"
  else
    fail "run_phase routed in tick.ps1: $p" "no switch arm"
  fi
done

# --- tree hygiene ---------------------------------------------------------------------
bom_files=""
crlf_files=""
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  has_bom "$f" && bom_files="$bom_files $f"
  case "$f" in *.md|*.sh|*.ps1|*.json|*.yml|*.gitignore|*.gitattributes)
    grep -q $'\r' "$f" && crlf_files="$crlf_files $f" ;;
  esac
done < <(git ls-files)
if [[ -z "$bom_files" ]]; then pass "no BOM in tracked files"; else fail "no BOM in tracked files" "$bom_files"; fi
if [[ -z "$crlf_files" ]]; then pass "LF-only tracked text files"; else fail "LF-only tracked text files" "$crlf_files"; fi

for s in scripts/*.sh tests/*.sh; do
  mode="$(git ls-files -s "$s" | awk '{print $1}')"
  assert_eq "executable bit: $s" "100755" "$mode"
done

# forbidden internal artifacts must not ship
for f in MEMORY.md northstar_project_quality_report.pdf public-release-review.md \
         public-release-hardening.md public-readiness-fixes.md; do
  if [[ -e "$f" ]]; then fail "forbidden artifact absent: $f" "present in tree"; else pass "forbidden artifact absent: $f"; fi
done
if compgen -G "*.pdf" >/dev/null; then fail "no PDFs at repo root" "$(ls -- *.pdf)"; else pass "no PDFs at repo root"; fi
for d in .suhail .claude; do
  if git ls-files "$d" | grep -q .; then fail "no tracked files under $d/" "$(git ls-files "$d" | head -3)"; else pass "no tracked files under $d/"; fi
done

# every relative markdown link resolves
broken=""
while IFS= read -r f; do
  while IFS= read -r target; do
    t="${target%%#*}"
    [[ -z "$t" ]] && continue
    case "$t" in http*|mailto:*) continue ;; esac
    if [[ ! -e "$(dirname "$f")/$t" && ! -e "$t" ]]; then broken="$broken $f->$t"; fi
  done < <(grep -oP '\]\(\K[^)]+' "$f" 2>/dev/null || true)
done < <(git ls-files '*.md')
if [[ -z "$broken" ]]; then pass "all relative markdown links resolve"; else fail "all relative markdown links resolve" "$broken"; fi

summary "payload-checks"
