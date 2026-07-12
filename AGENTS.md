# AGENTS.md

Instructions for AI coding agents working inside this repository. `CLAUDE.md` is the authoritative, more detailed version of this guidance — read it if your tool loads it; this file summarizes the same rules for tools that read `AGENTS.md`.

## What this repo is

Suhail is a **Claude Code plugin**: a plan-orchestration pipeline built from markdown prompt files (`commands/`, `agents/`), bash + PowerShell helper scripts (`scripts/`), a test harness (`tests/`), fixtures, and docs. It targets Claude Code's plugin system, slash commands, and subagent (Agent tool) model exclusively — it is not a Codex/other-runtime plugin, and porting it would be a real project, not a rename.

Working in this repo means working **on the tool**, not running it. There is no build step and no package manifest; the deliverables are prompt files and shell scripts.

## Load-bearing rules

- The orchestrator state machine lives in TWO places that must stay in sync: `commands/su.md` (handlers) and `scripts/suhail-tick.{sh,ps1}` (deterministic routing, fail-closed). Any state/directive change touches both, plus `tests/tick-matrix.sh`.
- `.sh` and `.ps1` script pairs must stay behaviorally identical; normal-case output is byte-identical.
- Subagent IPC is files-only (paths in prompts, artifacts on disk under `.suhail/parts/<id>/`). Never relay artifact bodies through conversation context.
- Never add runtime dependencies (`jq` is the single recorded exception). Never add telemetry.
- LF line endings everywhere (enforced by `.gitattributes`); no BOMs.
- Versions sync across five points: `commands/su.md` heading + `tool_version`, README footer, `.claude-plugin/plugin.json`, and the latest `CHANGELOG.md` section header. CI fails if they disagree.

## Verifying changes

Run `./tests/run-all.sh` (bash + jq required; PowerShell suites run when `pwsh` is available). For behavior changes, the practical end-to-end test is walking `fixtures/*.md` through an installed copy inside Claude Code — see `CONTRIBUTING.md` § Testing a change.
