# CLAUDE.md

Guidance for Claude Code working inside this repository.

## What this repo is

Northstar is a generic plan-orchestration pipeline for Claude Code. The repo ships role subagents (`agents/*.md`), a slash-command-based orchestrator (`commands/*.md`), install scripts (`scripts/`), fixtures, and docs. It is itself a Claude Code project — when you open it in Claude Code you are working on the tool, not running it.

## Repo layout at a glance

```
agents/                # Role subagents (scout, executer, verifier).
commands/              # Slash commands (northstar/ns, ns-init, ns-discover, ns-next). The orchestrator state machine lives in commands/northstar.md.
fixtures/              # Plan files used to exercise Northstar end-to-end.
scripts/               # POSIX + PowerShell installers.
docs/                  # plan-format.md, architecture.md, extending.md, decisions.md.
README.md              # User-facing.
CHANGELOG.md           # SemVer-tagged release notes.
LICENSE                # MIT.
```

## Key architectural facts (do not forget)

- **The orchestrator is a slash command, not a subagent.** It lives in `commands/northstar.md`. Earlier (v0.1.0) it was at `agents/northstar.md`; that did not work because Claude Code subagents cannot spawn nested subagents. The slash command body is injected into the top-level session, which can use the Agent tool to dispatch role subagents. Do not move it back into `agents/`. See `docs/architecture.md` § "Why the orchestrator lives in the slash command".
- **`commands/ns.md` is a thin pointer** that reads `commands/northstar.md` at runtime. Single source of truth for the orchestrator prompt. Do not duplicate the orchestrator body across both files.
- **Subagent IPC is files-only.** The orchestrator passes paths in prompts; subagents read inputs from disk and write outputs to disk. The orchestrator never echoes subagent bodies into the top-level conversation. Preserve this contract — it's why context stays bounded.
- **Subagents must not coordinate directly.** Scout → executer is one-way. The verifier runs independently after the executer.
- **Domain knowledge flows through one channel.** The verifier's audit pass is intentionally generic. Project-specific risks reach it only through `brief.md`'s `Domain risks worth flagging to auditor` section. Do not bake domain rules into the verifier's prompt.

## When making changes

- **Adding/changing a role subagent:** edit `agents/<role>.md`. Each role's contract (Input / Process / Output / Blocker protocol / Don't) is documented inline; preserve those sections.
- **Adding/changing orchestrator behavior:** edit `commands/northstar.md`. The state machine, parsing rules, dispatch shapes, narration discipline, and commit policy are all there.
- **Adding a new role:** see `docs/extending.md` for the recipe — write the agent file, add a state-machine phase in `commands/northstar.md`, bump the version, add a CHANGELOG entry.
- **Changing the plan format:** `docs/plan-format.md` is the spec; `commands/northstar.md` has the parser. Update both.

## Version bumps

`tool_version` appears in three places — keep all three in sync on every release:

1. `commands/northstar.md` — heading (`# /northstar (alias: /ns) — Northstar vX.Y.Z`) and the `tool_version` field inside the state schema block, and the STATUS.md template header.
2. `README.md` — the footer line "Northstar vX.Y.Z. Telemetry: none."
3. `CHANGELOG.md` — new section header `## [X.Y.Z] — YYYY-MM-DD`.

After bumping: `git tag vX.Y.Z` and push.

## Testing changes locally

Northstar is hard to unit-test — it's a prompt pipeline. The practical test is end-to-end against the fixtures.

1. Install the local working copy as the **project** version of itself:
   ```powershell
   .\scripts\install.ps1 -Project <dev-dir>\northstar -Force
   ```
   This places the current `agents/` and `commands/` into `<dev-dir>\northstar\.claude/`, overriding any user-level install when you run inside this directory.
2. Open a fresh Claude Code session in `<dev-dir>\northstar`.
3. Run `/ns fixtures/test_plan.md` and walk it through. Expected behaviors are documented at the top of each fixture file.
4. After each run, clean up:
   ```powershell
   /ns abort       # if still in-flight
   Remove-Item -Recurse -Force .northstar
   Remove-Item -Force .northstar-smoketest.txt   # if it exists
   ```
5. For changes that touch convention discovery (scout) or stack-conventions plumbing, also run against the <private-project> fixture (`<dev-dir>\tot\<private-plan>.md`) since that exercises a real project.

When the smoke test passes against all fixtures, the change is good enough to release.

## Conventions

- All markdown files use LF line endings in the repo (git may complain about CRLF on Windows; that's a warning, not an error — the `.gitattributes` policy is not set explicitly).
- Subagent prompts use Markdown H2 sections for structure (`## Input`, `## Process`, `## Output`, `## Blocker protocol`, `## Don't`). Keep the section names consistent across roles — the orchestrator does not parse them, but humans diff them.
- The orchestrator narrates in **one short sentence per event**. Do not lengthen the narration even for clarity — context discipline is the design.
- Never add telemetry. Never phone home. Never log to a third party. v1 commitment.

## Don't

- Don't run `/ns` from inside `<dev-dir>\northstar` against `fixtures/test_plan.md` and accidentally commit the resulting `.northstar/` or `.northstar-smoketest.txt` — `.gitignore` covers both, keep it that way.
- Don't add a new dependency (npm package, pip module, anything) without strong justification. Northstar is markdown and shell. Keep it that way.
- Don't make role subagents stack-aware. If they need stack context, they should discover it via the scout's `brief.md`.
- Don't change the IPC mechanism (files in `.northstar/parts/<id>/`) without a major version bump and migration plan.

## See also

- `docs/architecture.md` — design rationale.
- `docs/plan-format.md` — plan file contract.
- `docs/extending.md` — how to add roles.
- `docs/decisions.md` — log of major design decisions and why.
- `CONTRIBUTING.md` — how to develop, test, and release.
