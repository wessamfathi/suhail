# Contributing to Suhail

Thanks for considering a contribution. Suhail is a small project (markdown files, a handful of helper shell scripts, no runtime), so most contributions are short and focused.

## Ground rules

- **Stay generic.** Suhail is domain-agnostic. Do not add language-specific, framework-specific, or stack-specific knowledge to any role subagent's prompt. Project context flows through the scout's discovery, not through hardcoded prompt content.
- **Stay markdown.** No npm packages, no Python modules, no compiled binaries. Suhail is prompts and shell.
- **No telemetry, ever.** v1 commitment. Do not add analytics, error reporting, or any phone-home behavior.
- **Files-as-IPC stays the contract.** Subagents communicate via files in `.suhail/parts/<id>/`. The orchestrator passes paths, not bodies. Changing this is a major-version concern.

## Local setup

You'll need [Claude Code](https://claude.com/claude-code) installed to run the pipeline. Suhail itself has no runtime. The orchestrator and role subagents are plain markdown, so there's no build step.

Clone the repo.

To work on Suhail with Suhail (recommended, you'll catch contract regressions immediately), install your local checkout as a plugin from a local marketplace:

```
/plugin marketplace add /path/to/suhail
/plugin install suhail@suhail
```

The repo doubles as its own marketplace (`.claude-plugin/marketplace.json`), so this installs the working copy — commands, agents, and `scripts/` — into the plugin cache. Because runtime scripts then resolve via `${CLAUDE_PLUGIN_ROOT}/scripts/` (a frozen copy), an in-flight run is never disturbed by edits to your working tree.

After editing any command, agent, or script, refresh the installed copy:

```
/plugin marketplace update suhail
/reload-plugins
```

(Re-install if a refresh doesn't pick up the change.)

## Testing a change

Suhail is a prompt pipeline, so the practical test is end-to-end against fixtures.

1. Run the smoke test:
   ```
   /su fixtures/test_plan.md
   ```
   Walk it through. Expected outcomes are documented at the top of each fixture.
2. For changes that touch dependency handling, multi-Part flow, blocker protocols, or the skip flow, run the additional fixtures (see `fixtures/README.md`).
3. After each run, clean up so the next run starts fresh:
   ```powershell
   /su-abort
   .\scripts\suhail-clean.ps1
   # (POSIX: ./scripts/suhail-clean.sh)
   ```
   Or manually:
   ```powershell
   Remove-Item -Recurse -Force .suhail
   Remove-Item -Force .suhail-*.txt -ErrorAction SilentlyContinue
   # (POSIX: rm -rf .suhail && rm -f .suhail-*.txt)
   ```
4. For changes that affect scout convention-discovery, also try the pipeline against a real project (any repo you have access to with a real plan file is a good integration target, since it exercises stack discovery beyond the fixtures).

When all fixtures behave as documented, the change is shippable.

## Authoring conventions

A few repo conventions aren't obvious from the files themselves; see `CLAUDE.md` for the full list. The load-bearing ones:

- Markdown uses LF line endings.
- Role subagent prompts are structured with the H2 sections `## Input`, `## Process`, `## Output`, `## Blocker protocol`, `## Don't`. Keep the names consistent across roles.
- The orchestrator narrates one short sentence per event. Context discipline is the design, so don't lengthen it.
- Never commit `.suhail/` or `.suhail-smoketest.txt` (both are gitignored).

## Pull request expectations

- One logical change per PR. Keep diffs small and focused.
- Update `CHANGELOG.md` under `## [Unreleased]` with a one-line summary.
- If you changed any role subagent's output schema, update every consumer of that schema (orchestrator parser, dependent subagents, docs). The schema is the contract: changing it is allowed, but the change must be threaded through every consumer, and an incompatible change is a major-version bump (see Releasing).
- If you added a new role, update `docs/extending.md` to reflect the new template.
- If you changed the plan format, update both `docs/plan-format.md` and the parser in `commands/su.md`.
- If you changed user-visible behavior, update `README.md`.

## Releasing

1. Move `## [Unreleased]` notes into a new `## [X.Y.Z] — YYYY-MM-DD` section in `CHANGELOG.md`.
2. Bump the version at its other sync points (see CLAUDE.md § "Version bumps"): two spots in `commands/su.md` (the `# /su — Suhail vX.Y.Z` heading and the `tool_version` state field), the `README.md` footer line, and the `version` field in `.claude-plugin/plugin.json`.
3. Run every fixture one more time.
4. Commit with message `release: vX.Y.Z`.
5. Tag: `git tag vX.Y.Z`.
6. Push: `git push && git push --tags`.
7. Draft release notes on GitHub from the new CHANGELOG section.

Semver applies:
- **Patch** (`0.1.0 → 0.1.1`): bug fixes, prompt tweaks, doc updates. No contract changes.
- **Minor** (`0.1.0 → 0.2.0`): new roles, new commands, new optional fields in state.json. Backward-compatible.
- **Major** (`0.x → 1.0`): IPC contract changes, plan-format changes, removing a role. Migration notes required.

## Decision log

For changes that involve a design decision (not a typo fix), append to `docs/decisions.md` with date, decision, and rationale. This is the durable record of why Suhail is shaped the way it is. The PR description is the conversation; the decision log is the conclusion.

## What's in scope

- New role subagents (e.g. performance-auditor, accessibility-reviewer, doc-writer).
- Better blocker UX (richer option formats, automatic re-resolution).
- Better STATUS.md (interactive HTML version, charts, etc.).
- Better install ergonomics (single-line installer, package manager publication).
- Documentation, examples, fixtures.

## What's out of scope (for now)

- A web UI. Suhail is a CLI/Claude Code tool.
- Hosted state (cloud-synced `.suhail/`). Local-only by design.
- Plugin systems for arbitrary code execution outside the role-subagent model. The current shape is intentional; keep it simple.
- Telemetry of any kind.

## Code of conduct

Be kind. Be specific. Assume good faith. Disagree productively about technical choices; don't make it personal.

## License

By submitting a contribution you agree to license it under the MIT License (see `LICENSE`).
