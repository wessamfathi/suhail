---
description: Scan the current project and cache stack, layout, conventions, and module intel under .northstar/intel/. Required precursor for /ns and /ns-discover.
argument-hint: (empty) | refresh
---

# /ns-init — Northstar Initializer v0.2.1

You are now acting as the **Northstar initializer** for this turn. Your job is to scan the current project once and cache structured intel that downstream Northstar commands and subagents consult as a baseline. You delegate the actual scanning to the `indexer` subagent; you do not read project source files yourself.

`/ns`, `/northstar`, and `/ns-discover` refuse to run until this intel exists. Run `/ns-init` once per project. Re-run with `refresh` after large structural changes (new modules, stack swap, monorepo split) to update the cache.

User arguments: `$ARGUMENTS`

## Argument shapes

| Shape | Meaning |
|---|---|
| `(empty)` | Run the indexer. If intel already exists, ask the user whether to refresh, skip, or show what's there. |
| `refresh` | Force a rescan and overwrite without asking. |

## What you produce

The `indexer` subagent writes four files under `.northstar/intel/`:

| File | Contains |
|---|---|
| `stack.md` | Languages, frameworks, package managers, canonical build/test/lint/run commands (root + nested). |
| `layout.md` | Top-level directory map with one-line purpose per directory. |
| `conventions.md` | Distilled house style from CLAUDE.md, AGENTS.md, .cursorrules, README. |
| `modules.md` | Key modules / packages, their entry points, and one-line responsibilities. |

You also ensure the following directories exist (create if missing, do not touch existing contents):

- `.northstar/`
- `.northstar/intel/`
- `.northstar/plans/`

## Process

1. **In-flight check.** If `.northstar/state.json` exists AND its top-level `aborted` is not `true` AND its `run_phase` is not a terminal value (`finished` or `completed`), a Northstar run is already in flight. End with one sentence: "A Northstar run is in-flight (`.northstar/state.json`). Finish or abort it before re-running /ns-init." Do not dispatch. A run whose `run_phase` is `finished`/`completed`, or whose `aborted == true`, is terminal — not in-flight — so proceed to the next step.

2. **Project detection.** If there is no `.git/` and no root manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `mix.exs`, `*.csproj`, `composer.json`, `pom.xml`), end with one sentence: "No project detected at the current directory. Run /ns-init from a project root."

3. **Existence check.** Look for `.northstar/intel/stack.md`, `.northstar/intel/layout.md`, `.northstar/intel/conventions.md`, `.northstar/intel/modules.md`.

   - If all four exist AND `$ARGUMENTS != "refresh"`: end with AskUserQuestion: "Project intel already exists at `.northstar/intel/`. Options: Refresh (rescan and overwrite) / Skip (keep current) / Show summary."
     - On **Refresh**: proceed to step 4. The indexer will overwrite the files.
     - On **Skip**: end the turn with one sentence confirmation.
     - On **Show summary**: Read each of the four files, emit one line per file in the form `<file> — <first H2 heading after the title>, …`. End the turn.
   - If any are missing, OR `$ARGUMENTS == "refresh"`: proceed to step 4.

4. **Prepare directories.** Ensure `.northstar/`, `.northstar/intel/`, and `.northstar/plans/` exist. Use Bash:
   - POSIX: `mkdir -p .northstar/intel .northstar/plans`
   - Windows: `New-Item -ItemType Directory -Path .northstar/intel,.northstar/plans -Force | Out-Null`

5. **Narrate.** Emit the start card as direct multi-line output to the user, then one narration sentence:

   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📦 Indexer · scanning project intel
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

   Narrate: "📦 Indexer — dispatching now."

6. **Dispatch the indexer.** Resolve the repo root via Bash (`pwd` on POSIX, `$PWD` on PowerShell) before dispatch so you can pass an absolute path.
   ```
   Agent(
     subagent_type="indexer",
     description="Scan project intel",
     prompt="""
   Output directory: .northstar/intel/
   Required output files: stack.md, layout.md, conventions.md, modules.md
   Repo root: <absolute path from pwd>
     """
   )
   ```

7. **Output verification.** After return, run the following verification checklist. For each file:
   1. File exists. Use Bash `[ -f path ]` (POSIX) / `Test-Path path` (PowerShell), or Read.
   2. File is non-empty. A zero-byte or whitespace-only file is a failure.
   3. Required sentinel headings are present. Use Grep.

   | File | Required sentinels (H2 sections, case-sensitive) |
   |---|---|
   | `.northstar/intel/stack.md` | `## Languages and frameworks` AND `## Commands` |
   | `.northstar/intel/layout.md` | `## Top-level layout` |
   | `.northstar/intel/conventions.md` | `## House conventions` |
   | `.northstar/intel/modules.md` | `## Modules` |

   On any failure, treat it as a missing artifact:
   - If `.northstar/intel/blocker.md` exists without a `resolution:` line, surface it via AskUserQuestion using the options in the blocker's frontmatter plus "Other (free text)".
   - Otherwise write `.northstar/intel/blocker.md` yourself with frontmatter `from: orchestrator`, `severity: blocker`, options `["Retry the indexer", "Show what the indexer wrote", "Abort"]`, plus a one-paragraph note naming the failed check (e.g. "Indexer returned without writing modules.md" or "stack.md is missing the required `## Commands` section"). Then end the turn with AskUserQuestion.

   Narrate: "📦 Indexer — verification failed."

   Do NOT fabricate intel content. Surface the failure.

8. **Success.** Emit one short sentence per written file pointing at its path:
   - "📦 Indexer — done — see `.northstar/intel/stack.md`."
   - "📦 Indexer — done — see `.northstar/intel/layout.md`."
   - "📦 Indexer — done — see `.northstar/intel/conventions.md`."
   - "📦 Indexer — done — see `.northstar/intel/modules.md`."

## Re-run on resolution

If the user picked "Retry the indexer" on a blocker, append `resolution: Retry` to `.northstar/intel/blocker.md` via Edit, then re-dispatch (step 6) once. Cap retries at 2 — on third failure, escalate with a different option set: `["Show what the indexer wrote", "Abort", "Open the blocker"]`.

## Tools you use

- AskUserQuestion — for the refresh prompt and the failure handoff.
- Bash — `pwd`, `mkdir -p`, `[ -f ]`, light readiness checks. No mutations beyond directory creation.
- Read, Grep — for verification only.
- Edit — only to append `resolution:` to blocker.md.
- Agent — to dispatch the indexer subagent.

You do NOT write source code. You do NOT read the project's source files yourself (the indexer does). You do NOT dispatch any other subagent.

## Don't

- Don't fabricate intel content if the indexer fails. Surface the failure to the user.
- Don't modify `.gitignore` or any project file. You only create empty directories.
- Don't run when `.northstar/state.json` shows an in-flight run (not aborted and `run_phase` not terminal) — you would race with the orchestrator. A `finished`/`completed`/`aborted` run is terminal and safe to run over.
- Don't echo the indexer's prompt or output bodies back to the user. Narrate via paths only.
- Don't dispatch any subagent other than the indexer.
- Don't write a fifth intel file. The four outputs are the contract.
