# Suhail

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/wessamfathi/suhail)](https://github.com/wessamfathi/suhail/releases)
[![CI](https://github.com/wessamfathi/suhail/actions/workflows/ci.yml/badge.svg)](https://github.com/wessamfathi/suhail/actions/workflows/ci.yml)

A generic, distributable plan-orchestration pipeline for [Claude Code](https://claude.com/claude-code).

Suhail walks any structured plan file (markdown with `### Part N — Title` headings) to completion by dispatching specialized subagents (su-scout, su-executer, su-verifier) through each Part. State persists across sessions, the orchestrator narrates its progress, and blockers come back to you as multiple-choice questions.

Suhail itself is domain-agnostic. It does not assume a language, framework, or stack. The su-scout discovers conventions (CLAUDE.md / AGENTS.md / README / manifests) and surfaces them in `brief.md` so the rest of the pipeline can stay generic.

## Why Suhail (vs. just pasting the plan into a chat)

- **Bounded context on long plans.** Subagents communicate through files, never through the conversation — a 30-Part plan costs the orchestrator the same context as a 3-Part one.
- **Runs survive sessions.** State lives in `.suhail/state.json`; close the session mid-run and `/suhail:su` picks up exactly where it stopped.
- **Independent review + security audit per Part.** Every non-empty diff gets a reviewer pass and a security-audit pass from a separate agent that didn't write the code.
- **One atomic commit per Part.** Each verified Part lands as its own commit, so you can review, push, or revert work Part-by-Part.

What a run looks like (abridged):

```
> /suhail:su .suhail/plans/search-filters.md

🧭 Orchestrator — initialized with 4 Parts across 2 levels — scouting level 0 (3 Parts) in parallel.
🗺️ Scout — briefs ready for level 0.
  ▸ Approve all and start executing
⚙️ Executer — starting Part 1
⚙️ Executer — execution complete for Part 1.
🧭 Orchestrator — verifying level 0 — dispatching 3 verifiers in parallel: Part 1, Part 2, Part 3
🔎 Reviewer — verdict: clean ✓
🔒 Auditor — verdict: clean ✓
🧭 Orchestrator — committed Part 1 (3 files).
┌───────────────────────────────────────────────┐
│ ✅ Part 1 complete — Add filter state model    │
│ Reviewer: 🟢 clean   Auditor: 🟢 clean          │
│ ▶ Next: Part 2 — Wire filter UI                │
└───────────────────────────────────────────────┘
  ▸ Level 0 complete (Parts 1–3). Continue to level 1 (Part 4)?
```

In the default interactive mode, Suhail stops at every approval gate — the master plan approval for each dependency level and the level-boundary checkpoint after it completes — and every Part gets its own transition card and commit. For linear plans (each Part depending on the previous one), that means a pause after every Part. `/suhail:su autorun` and `/suhail:su run-to` advance without pausing.

## Requirements

- **Claude Code 2.1.207 or later** (the minimum version Suhail is tested against) — plugin install is the only distribution channel.
- **POSIX (macOS/Linux):** `bash` and [`jq`](https://jqlang.org/) on PATH (`brew install jq` / `apt install jq`). The helper scripts refuse to run without jq.
- **Windows:** PowerShell — `pwsh` (7+) if you have it, otherwise the preinstalled Windows PowerShell 5.1 works.
- **git** — required for diff capture and per-Part commits (runs in non-git directories with those features disabled).

## Security model

**A plan file is code-equivalent — run only plans you trust, the same way you would treat a shell script.** The su-executer implements Parts with full Edit/Write/Bash access: whatever commands the plan and the scout's brief call for, it can run with your session's permissions. Guardrails: the executer never commits, pushes, or deploys; destructive or network-touching commands require an explicit justification in the plan or brief; every command it runs is recorded in `execution.md` under `## Commands run`; and every non-empty diff passes an independent review and security audit before the Part's atomic commit. Review the artifacts under `.suhail/parts/` whenever something looks off. See [`SECURITY.md`](SECURITY.md) for the full threat model and how to report vulnerabilities.

## Install

Suhail's repo is its own plugin marketplace. Install with two commands inside Claude Code:

```
/plugin marketplace add wessamfathi/suhail
/plugin install suhail@suhail
```

This pulls the commands, agents, and helper scripts as a versioned plugin, so there is nothing to copy by hand. Update with `/plugin marketplace update suhail` then `/reload-plugins`; uninstall with `/plugin uninstall suhail@suhail`. Plugin-installed commands are namespaced: invoke them as `/suhail:su`, `/suhail:su-init`, and so on — that is how every command below is written. The unqualified forms (`/su`, `/su-init`, …) apply only when the command files are loaded as project or user commands, e.g. when developing from a checkout of this repo. Once installed, add `.suhail/` to any target repo's `.gitignore` (Suhail writes its run state there).

**Upgrading from Northstar (≤ 0.15)?** The project was renamed at v1.0.0. Remove the old plugin (`/plugin uninstall northstar@northstar`, `/plugin marketplace remove northstar`), delete any pre-0.15 hand-copied files (`~/.claude/commands/ns*.md`, `~/.claude/commands/northstar*.md`, `~/.claude/commands/scripts/northstar-*`, `~/.claude/agents/ns-*.md`), then install as above. The state directory moved from `.northstar/` to `.suhail/`; in-flight Northstar runs cannot be resumed by Suhail.

## Initialize a project

After installing Suhail, open your project folder and scan it once:

```
/suhail:su-init
```

`/suhail:su-init` dispatches the `su-indexer` subagent to read manifests, conventions docs (CLAUDE.md / AGENTS.md / README), and the directory tree, then caches the result under `.suhail/intel/` as four files: `stack.md`, `layout.md`, `conventions.md`, `modules.md`. Downstream agents read this cache as their baseline so per-Part research stays focused on what the Part actually touches.

`/suhail:su` and `/suhail:su-discover` refuse to run until this intel exists. Re-run `/suhail:su-init` (or `/suhail:su-init refresh`) after stack changes, monorepo restructures, or major new modules.

## Discover a plan

Suhail can interview you and draft a plan to achieve your goals:

```
/suhail:su-discover
```

`/suhail:su-discover` is an interactive slash command that interviews you about the vision, scope, dependencies, and per-Part detail, then writes a markdown plan in the exact format `/suhail:su` expects. The command orchestrates three phases: Phase 0 delegates to `su-discover-scout` (haiku, read-only, no Write tool) which silently scans the repo and returns a structured context summary; Phases 1 through 4 conduct the multi-turn interview in the top-level session; Phase 5 delegates to `su-discover-planner` (sonnet) which consumes the answers file and writes the plan. Hand the output path to `/suhail:su` to execute it. Optional argument: a target output path (defaults to `.suhail/plans/<slug>.md`).

## Quickstart

After install (and once `/suhail:su-init` has run, see above), point `/suhail:su` at your own plan file in any repo:

```
/suhail:su path/to/your-plan.md
```

The first invocation parses the plan, creates `.suhail/state.json`, and immediately scouts the first dependency level in parallel — the first thing you're asked is the **master plan approval** once those briefs are ready (approve all, review Parts individually, read the full briefs, or abort). Each subsequent `/suhail:su` call advances the run by one logical step.

To verify the toolchain, run the bundled self-test from a clone of this repo:

```
/suhail:su fixtures/test_plan.md
```

Expected result (about five minutes, detailed at the top of the fixture): three Parts across two levels; a mandatory ⚠ external-dependency pause before Part 2 executes; two marker files (`.suhail-smoketest.txt` containing `suhail smoke ok`, `.suhail-smoketest-2.txt` containing `suhail smoke ok 2`); full artifact sets (`brief.md`, `execution.md`, `review.md`, `audit.md`, captured diff) under `.suhail/parts/part-1/` and `part-2/`; and a synthetic inline brief for the trivial Part 3 — whose non-empty diff still gets a real verifier run (review + audit), since no classification can skip the audit.

## Slash commands

| Command | Purpose |
|---|---|
| `/suhail:su-init` | Scan the project and cache stack / layout / conventions / modules under `.suhail/intel/`. Required precursor for `/suhail:su` and `/suhail:su-discover`. |
| `/suhail:su-init refresh` | Force a rescan and overwrite existing intel. |
| `/suhail:su <plan-path>` | Initialize a new run against a plan file. A finished or aborted previous run is auto-archived to `.suhail/archive/`; an in-flight run refuses with "A run is already in progress — run `/su-abort` first." Refuses if intel is missing. |
| `/suhail:su` | Continue from current state. Advances one logical step per tick. |
| `/suhail:su-status` | Print the human-readable status dashboard (`.suhail/STATUS.md`). Read-only. |
| `/suhail:su-skip` | Mark the current Part `skipped` and advance to the next. |
| `/suhail:su retry` | Reset the current Part's retry counter and re-run from `scouting`. |
| `/suhail:su run-to <part-id>` | Auto-advance through Parts up to and including `<part-id>`. Pauses only on blockers; bypasses approval gates for the duration. |
| `/suhail:su-abort` | Set the run status to `aborted`. Does not delete artifacts. |
| `/suhail:su-discover [output-path]` | Interview the user and write a Suhail-format plan file. Delegates Phase 0 grounding to `su-discover-scout` (haiku, read-only) and Phase 5 plan-writing to `su-discover-planner` (sonnet). Independent of any active run; requires intel. |
| `/suhail:su-next` | Advance the current run by exactly one logical step, auto-approving the two sanctioned gates: the per-Part brief gate and the batch master-plan approval — note the latter approves **every brief in the level at once**. Performs no INIT, never loops. Requires an active run. |
| `/suhail:su-auto [plan-path]` | Auto-detect the most recent plan and run it in autorun mode. |

## How a run executes

```
per dependency level:
  su-scouts (parallel) → master plan approval → su-executers (serial)
    → su-verifiers (parallel) → per Part: atomic commit + transition card
  → level checkpoint → next level
```

Parts are grouped into dependency levels (level 0 = no dependencies). Each level is scouted in parallel and its briefs are approved together at the master-plan gate (or Part-by-Part if you choose "review individually"). Executers then run strictly serially; once every Part in the level has executed, verifiers run in parallel. Each verified-clean Part gets its own atomic commit, Manual-follow-ups checkpoint, and transition card, and the run pauses at the level boundary in interactive mode.

Each subagent reads its inputs from disk and writes its output to a known path inside `.suhail/parts/<part-id>/`. The orchestrator passes paths in prompts and never relays artifact bodies, so its own context stays small no matter how large the plan grows.

If the su-verifier reports a `[blocker]` finding, the orchestrator re-dispatches the su-executer with the findings attached. Up to three attempts per Part by default; after that, the orchestrator hands control back to you.

If any subagent encounters something it cannot resolve (missing file, ambiguous spec, unreachable service), it writes a `blocker.md` with options and the orchestrator surfaces it to the user as a multiple-choice question.

## Plan format

Any markdown file matching this minimal contract is a valid plan:

- **Parts** are H3 headings of the form `### Part 1 — <title>` (em-dash, with surrounding spaces).
- **Groups** are optional enclosing H2 headings (`## Milestone M023`, `## Phase 1`, etc.). Purely cosmetic.
- **Dependencies** are declared inline, either:
  - `**Depends on:** Part 2, Part 4`, or
  - Prose containing `Depends on Part N` (list forms like `Depends on Parts 2, 4, and 6` work too).
- Anything else inside a Part is free-form context passed to the scout.

See [`docs/plan-format.md`](docs/plan-format.md) for the full spec and examples.

## Runtime layout

When Suhail is operating on a target repo, it writes here:

```
.suhail/
├── intel/                      # written by /su-init, read by su-scout and /su-discover
│   ├── stack.md
│   ├── layout.md
│   ├── conventions.md
│   └── modules.md
├── plans/                      # default output dir for /su-discover; scanned by /su-auto
├── state.json                  # canonical state (JSON)
├── STATUS.md                   # human dashboard, regenerated each tick
├── archive/                    # finished/aborted runs, moved here on the next INIT
└── parts/
    └── part-<id>/
        ├── brief.md
        ├── execution.md            # execution-attempt-K.md on retries
        ├── review.md
        ├── audit.md
        ├── diff-attempt-N.patch    # captured diff
        └── blocker.md              # only if open
```

Add `.suhail/` to your target repo's `.gitignore`.

## Safety

- The **su-executer never pushes or deploys**. It flags deploys under "Manual follow-ups required" in `execution.md` for you to run. Command governance (justification for destructive/network commands, the `## Commands run` record) is covered in the Security model above and in [`SECURITY.md`](SECURITY.md).
- **Atomic per-Part commits (on by default).** After a Part is verified clean, the orchestrator creates one git commit from that Part's exact patch: it snapshots the working tree before and after the executer runs and commits only the difference, via git plumbing, without ever touching your staged or unstaged work (after each commit, index entries you hadn't modified are synced to the new HEAD so `git status` stays clean). Pre-existing staged or unstaged work of yours is never swept into a Suhail commit; if a Part edits a file you already had uncommitted edits in, the commit fails closed to a blocker instead of mixing content. Trade-off: Part commits bypass git commit hooks. Skipped Parts and non-git directories are never committed. The orchestrator never pushes, deploys, amends, or force-pushes. Disable for a run with `no-commit` at INIT (e.g. `/suhail:su no-commit <plan>` or `/suhail:su autorun no-commit <plan>`); continuations keep the run's commit setting, and with auto-commit off the interactive "Commit first" option still lets you commit on demand.
- The **su-verifier** runs two passes: a review pass (correctness, regressions, convention drift) and an audit pass (security, injection, secrets, input validation). The audit runs for every non-empty diff — no plan classification can skip it. Project-specific risks travel via the su-scout's `Domain risks worth flagging to auditor` section in `brief.md`. Domain knowledge is never hardcoded into the su-verifier.

## Troubleshooting

**"A run is already in progress — run `/su-abort` first."**: a previous run is still in flight. Use `/suhail:su-status` to inspect it, `/suhail:su` to continue it, or `/suhail:su-abort` to end it — after which the next `/suhail:su <plan-path>` archives its artifacts to `.suhail/archive/` and starts fresh.

**"jq is required but not found on PATH"**: the POSIX helper scripts hard-require jq. `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu), then re-run.

**"Plan file changed since last run"**: the plan's SHA differs from the recorded one. Choose "Re-parse" (Suhail rebuilds the Part list; in-flight Parts may be invalidated) or "Continue with cached structure" (proceed with the parts list from `state.json`).

**Su-verifier keeps re-dispatching su-executer**: there's a finding the su-executer cannot fix. After three attempts the orchestrator hands control back; read the latest `review.md` / `audit.md` and either resolve manually, edit the plan and `/suhail:su retry`, or `/suhail:su-skip`.

**Artifacts under `.suhail/parts/<id>/`** are your friend. They're the persistent record of every reasoning step. Open them any time.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for local setup, the fixture-based test flow, and release process, and [`CHANGELOG.md`](CHANGELOG.md) for what shipped when. Design docs: [`docs/architecture.md`](docs/architecture.md) (full design write-up), [`docs/decisions.md`](docs/decisions.md) (rationale log), [`docs/extending.md`](docs/extending.md) (adding a role).

## License

MIT. See [`LICENSE`](LICENSE).

## Status

Suhail v1.1.0. Telemetry: none. Issues and PRs welcome.
