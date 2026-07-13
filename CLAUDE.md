# CLAUDE.md

Guidance for Claude Code working inside this repository.

## What this repo is

Suhail is a generic plan-orchestration pipeline for Claude Code. The repo ships role subagents (`agents/*.md`), a slash-command-based orchestrator (`commands/*.md`), helper runtime scripts (`scripts/`), plugin manifests (`.claude-plugin/`), fixtures, and docs. It is itself a Claude Code project — when you open it in Claude Code you are working on the tool, not running it.

## Repo layout at a glance

```
agents/                # Six role subagents: su-scout, su-executer, su-verifier, su-indexer, su-discover-scout, su-discover-planner.
commands/              # Eight slash commands: su, su-init, su-discover, su-next, su-auto, su-skip, su-status, su-abort. The orchestrator state machine lives in commands/su.md.
scripts/               # Runtime helper scripts, bash + PowerShell pairs (suhail-tick, suhail-read, suhail-write, suhail-clean).
tests/                 # Regression harness: tick matrix, reader/writer edge cases, payload validation. Run ./tests/run-all.sh.
fixtures/              # Plan files used to exercise Suhail end-to-end.
docs/                  # plan-format.md, architecture.md, extending.md, decisions.md.
.github/               # CI workflow, issue form, PR template.
README.md              # User-facing.
CHANGELOG.md           # SemVer release notes.
LICENSE                # MIT.
```

## Key architectural facts (do not forget)

- **The orchestrator is a slash command, not a subagent.** It lives in `commands/su.md`. Earlier (v0.1.0) it was at `agents/suhail.md`; at the time that could not work because Claude Code subagents could not spawn nested subagents. Nested subagents have existed since Claude Code v2.1.172 (depth-limited), but the binding constraint today is a different one: `AskUserQuestion` — and interactive gates generally — is unavailable to subagents, and the orchestrator is built around interactive gates. The slash command body is injected into the top-level session, which can use the Agent tool to dispatch role subagents and can ask the user questions. Do not move it back into `agents/`. See `docs/architecture.md` § "Why the orchestrator lives in the slash command".
- **Subagent IPC is files-only.** The orchestrator passes paths in prompts; subagents read inputs from disk and write outputs to disk. The orchestrator never echoes subagent bodies into the top-level conversation. Preserve this contract — it's why context stays bounded.
- **Subagents must not coordinate directly.** Su-scout → su-executer is one-way. The su-verifier runs independently after the su-executer.
- **Domain knowledge flows through one channel.** The su-verifier's audit pass is intentionally generic. Project-specific risks reach it only through `brief.md`'s `Domain risks worth flagging to auditor` section. Do not bake domain rules into the su-verifier's prompt.

## When making changes

- **Adding/changing a role subagent:** edit `agents/<role>.md`. Each role's contract (Input / Process / Output / Blocker protocol / Don't) is documented inline; preserve those sections.
- **Adding/changing orchestrator behavior:** edit `commands/su.md` AND keep `scripts/suhail-tick.{sh,ps1}` in sync — the tick scripts route every state deterministically and fail closed on anything they don't recognize. Add matrix cases to `tests/tick-matrix.sh` for any new state or directive.
- **Adding a new role:** see `docs/extending.md` for the recipe — write the agent file, wire the state machine in both homes (`commands/su.md` + both tick scripts), add harness cases, bump the version, add a CHANGELOG entry.
- **Changing the plan format:** `docs/plan-format.md` is the spec; `commands/su.md` has the parser. Update both.
- **Command headings carry no private versions.** Only `commands/su.md`'s heading carries the tool version; the other command files' H1s are unversioned.

## Version bumps

`tool_version` appears in two places inside `commands/su.md` plus three other files — keep all in sync on every release:

1. `commands/su.md` — heading (`# /su — Suhail vX.Y.Z`) and the `tool_version` field inside the state schema block. These are the only two sync points in `commands/su.md`. The write scripts (`scripts/suhail-write.{ps1,sh}`) render `tool_version` from `state.tool_version` at runtime and do not hardcode a version string — no separate edit needed there.
2. `README.md` — the footer line "Suhail vX.Y.Z. Telemetry: none."
3. `CHANGELOG.md` — new section header `## [X.Y.Z] — YYYY-MM-DD`.
4. `.claude-plugin/plugin.json` — the `version` field. This is the version the plugin marketplace reports; keep it identical to the others.

After bumping: `git tag vX.Y.Z` and push.

## Plugin distribution

Suhail ships as a Claude Code **plugin** whose own repo doubles as the marketplace catalog:

- `.claude-plugin/plugin.json` — plugin manifest (name, version, metadata). `version` is a release sync point (see above).
- `.claude-plugin/marketplace.json` — marketplace catalog; lists the single `suhail` plugin with `source: "./"` (plugin files live at repo root).

Users install with `/plugin marketplace add wessamfathi/suhail` then `/plugin install suhail@suhail`. The plugin bundles `commands/`, `agents/`, and `scripts/` as-is — no file moves. At runtime, plugin-installed commands resolve helper scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/`, which the plugin system substitutes inline before a command file is read; in a non-plugin context that token stays literal and the script lookup falls through to the project/user/dev-repo paths. Distribution is plugin-only; there are no copy-install scripts.

## Testing changes locally

Suhail is hard to unit-test — it's a prompt pipeline. The practical test is end-to-end against the fixtures.

1. Install the local working copy as a plugin from a local marketplace (the repo is its own marketplace):
   ```
   /plugin marketplace add /path/to/suhail
   /plugin install suhail@suhail
   ```
   This loads the current `agents/`, `commands/`, and `scripts/` from the working copy into the plugin cache. After editing, `/plugin marketplace update suhail` then `/reload-plugins` to refresh.
2. Open a fresh Claude Code session in the repo root.
3. Run `/suhail:su fixtures/test_plan.md` and walk it through (plugin-installed commands are namespaced; the unqualified `/su` forms apply only when the files are loaded as project/user commands). Expected behaviors are documented at the top of each fixture file.
4. After each run, clean up:
   ```powershell
   /suhail:su-abort       # if still in-flight
   Remove-Item -Recurse -Force .suhail
   Remove-Item -Force .suhail-*.txt -ErrorAction SilentlyContinue
   ```
5. For changes that touch convention discovery (su-scout) or stack-conventions plumbing, also run against a real project's plan file (any repo you have access to with a multi-Part plan) since that exercises stack discovery against a non-fixture codebase.

When the smoke test passes against all fixtures, the change is good enough to release.

## Conventions

- All files use LF line endings, enforced explicitly by `.gitattributes` (`* text=auto eol=lf`, plus per-type rules) — Windows editors cannot silently reintroduce CRLF into the working tree. CI's LF-policy check fails on any CR or BOM in tracked files.
- Subagent prompts use Markdown H2 sections for structure (`## Input`, `## Process`, `## Output`, `## Blocker protocol`, `## Don't`). Keep the section names consistent across roles — the orchestrator does not parse them, but humans diff them.
- The orchestrator narrates in **one short sentence per event**. Do not lengthen the narration even for clarity — context discipline is the design.
- Never add telemetry. Never phone home. Never log to a third party. v1 commitment.

## Don't

- Don't run `/su` from inside the Suhail repo against `fixtures/test_plan.md` and accidentally commit the resulting `.suhail/` or `.suhail-smoketest.txt` — `.gitignore` covers both, keep it that way.
- Don't add a new dependency (npm package, pip module, anything) without strong justification. Suhail is markdown and shell; `jq` is the single recorded runtime exception, and python3+PyYAML is dev-only test tooling that self-skips when absent (both recorded in docs/decisions.md 2026-07-12). Keep it that way.
- Don't make role subagents stack-aware. If they need stack context, they should discover it via the su-scout's `brief.md`.
- Don't change the IPC mechanism (files in `.suhail/parts/<id>/`) without a major version bump and migration plan.

## See also

- `docs/architecture.md` — design rationale.
- `docs/plan-format.md` — plan file contract.
- `docs/extending.md` — how to add roles.
- `docs/decisions.md` — log of major design decisions and why.
- `CONTRIBUTING.md` — how to develop, test, and release.
