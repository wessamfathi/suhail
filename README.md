# Northstar

A generic, distributable plan-orchestration pipeline for [Claude Code](https://claude.com/claude-code).

Northstar walks any structured plan file (markdown with `### Part N — Title` headings) to completion by dispatching specialized subagents — **scout**, **executer**, **verifier** — through each Part. State persists across sessions. Progress is narrated. Blockers are surfaced as user-answerable questions. **After every Part, Northstar pauses for explicit user approval before advancing.**

Northstar itself is domain-agnostic. It does not assume a language, framework, or stack — the **scout** discovers conventions (CLAUDE.md / AGENTS.md / README / manifests) and surfaces them in `brief.md` so the rest of the pipeline can stay generic.

## Install

User-level (recommended — works across every repo):

```bash
# POSIX
./scripts/install.sh

# Windows
.\scripts\install.ps1
```

This copies the agents to `~/.claude/agents/` and the slash commands to `~/.claude/commands/`.

## Initialize a project

Before running `/ns` or `/ns-discover` against a project, scan it once:

```
/ns-init
```

`/ns-init` dispatches the `indexer` subagent to read manifests, conventions docs (CLAUDE.md / AGENTS.md / README), and the directory tree, then caches the result under `.northstar/intel/` as four files: `stack.md`, `layout.md`, `conventions.md`, `modules.md`. Downstream agents read this cache as their baseline so per-Part research stays focused on what the Part actually touches.

`/ns` and `/ns-discover` refuse to run until this intel exists. Re-run `/ns-init` (or `/ns-init refresh`) after stack changes, monorepo restructures, or major new modules.

Project-level (install into a specific repo's `.claude/`):

```bash
./scripts/install.sh --project /path/to/repo
.\scripts\install.ps1 -Project C:\path\to\repo
```

Add `--gitignore` (POSIX) or `-Gitignore` (Windows) when using `--project` to also append `.northstar/` to that repo's `.gitignore`. Off by default.

Add `--force` / `-Force` to overwrite existing files (default refuses and prints a diff).

## Discover a plan

Don't have a plan file yet? Let Northstar interview you and draft one:

```
/ns-discover
```

`/ns-discover` is an interactive slash command that interviews you about the vision, scope, dependencies, and per-Part detail, then writes a markdown plan in the exact format `/ns` expects. The command orchestrates three phases: Phase 0 delegates to `discover-scout` (haiku, read-only, no Write tool) which silently scans the repo and returns a structured context summary; Phases 1–4 conduct the multi-turn interview in the top-level session; Phase 5 delegates to `discover-planner` (sonnet) which consumes the answers file and writes the plan. Hand the output path to `/ns` to execute it. Optional argument: a target output path (defaults to `.northstar/plans/<slug>.md`).

## Quickstart

After install, in any repo:

```
/ns fixtures/test_plan.md
```

The first invocation parses the plan, creates `.northstar/state.json`, and asks you to confirm starting Part 1. Each subsequent `/ns` call advances state by one Part. Northstar narrates each subagent dispatch and pauses after every Part with a question:

> Part 1 complete. Continue to Part 2? (Continue / Pause / Commit first / Show diff / Show review / Show audit)

Run the bundled self-test once after install to verify the toolchain:

```
/ns fixtures/test_plan.md
```

Expected result: a `.northstar-smoketest.txt` file containing `northstar smoke ok`, with five clean artifacts under `.northstar/parts/part-1/`.

## Slash commands

| Command | Purpose |
|---|---|
| `/ns-init` | Scan the project and cache stack / layout / conventions / modules under `.northstar/intel/`. Required precursor for `/ns` and `/ns-discover`. |
| `/ns-init refresh` | Force a rescan and overwrite existing intel. |
| `/ns <plan-path>` | Initialize a new run against a plan file. Refuses if state already exists (use `/ns-abort` first) or if intel is missing (run `/ns-init` first). |
| `/ns` | Continue from current state. Advances by one Part per tick. |
| `/ns-status` | Print the human-readable status dashboard (`.northstar/STATUS.md`). Read-only. |
| `/ns-skip` | Mark the current Part `skipped` and advance to the next. |
| `/ns retry` | Reset the current Part's retry counter and re-run from `researching`. |
| `/ns run-to <part-id>` | Auto-advance through Parts up to and including `<part-id>`. Pauses only on blockers; bypasses per-Part and scout-approval pauses for the duration. |
| `/ns-abort` | Set the run status to `aborted`. Does not delete artifacts. |
| `/ns-discover [output-path]` | Interview the user and write a Northstar-format plan file. Delegates Phase 0 grounding to `discover-scout` (haiku, read-only) and Phase 5 plan-writing to `discover-planner` (sonnet). Independent of any active run; requires intel. |
| `/ns-next` | Auto-advance the current Northstar run by exactly one logical step. Zero-argument shortcut for "next" — performs no INIT, does not loop in `run-to` mode, and auto-approves the scout only at `awaiting_plan_approval`. Requires an active run. |
| `/ns-auto [plan-path]` | Auto-detect the most recent plan and run it in autorun mode. |

## How a Part is executed

```
scout → (user approval) → executer → verifier → completed → (user approval) → next Part
```

Each subagent reads its inputs from disk and writes its output to a known path inside `.northstar/parts/<part-id>/`. The orchestrator passes paths in prompts — it never relays artifact bodies — so its own context stays small no matter how large the plan grows.

If the verifier reports a `[blocker]` finding, the orchestrator re-dispatches the executer with the findings attached. Up to three attempts per Part by default; on exhaustion, control returns to the user.

If any subagent encounters something it cannot resolve (missing file, ambiguous spec, unreachable service), it writes a `blocker.md` with options and the orchestrator surfaces it to the user as a multiple-choice question.

## Plan format

Any markdown file matching this minimal contract is a valid plan:

- **Parts** are H3 headings of the form `### Part 1 — <title>` (em-dash, with surrounding spaces).
- **Groups** are optional enclosing H2 headings (`## Milestone M023`, `## Phase 1`, etc.). Purely cosmetic.
- **Dependencies** are declared inline, either:
  - `**Depends on:** Part 2, Part 4`, or
  - Prose containing `Depends on Part N` (regex fallback).
- Anything else inside a Part is free-form context passed to the scout.

See [`docs/plan-format.md`](docs/plan-format.md) for the full spec and examples.

## Runtime layout

When Northstar is operating on a target repo, it writes here:

```
.northstar/
├── intel/                      # written by /ns-init, read by scout and /ns-discover
│   ├── stack.md
│   ├── layout.md
│   ├── conventions.md
│   └── modules.md
├── state.json                  # canonical state (JSON)
├── STATUS.md                   # human dashboard, regenerated each tick
└── parts/
    └── part-<id>/
        ├── brief.md
        ├── plan.md
        ├── execution.md
        ├── review.md
        ├── audit.md
        ├── diff-attempt-N.patch
        └── blocker.md          # only if open
```

Add `.northstar/` to your target repo's `.gitignore`. The install script will do this for you if you pass `--gitignore` with `--project`.

## Safety

- The **executer never commits**. It also never deploys. Deploys are flagged as "Manual follow-ups required" in `execution.md` for you to run.
- **Atomic per-Part commits (on by default).** After a Part is verified clean, the orchestrator creates one git commit containing only that Part's changed files, so history is reviewable, pushable, and revertable Part-by-Part. Skipped Parts and non-git directories are never committed. The orchestrator never pushes, deploys, amends, or force-pushes. Disable for a run with `no-commit` (e.g. `/ns no-commit <plan>` or `/ns autorun no-commit <plan>`); with auto-commit off, the interactive "Commit first" option still lets you commit on demand.
- The **verifier** runs two passes: a review pass (correctness, regressions, convention drift) and an audit pass (security, injection, secrets, input validation). Project-specific risks travel via the scout's `Domain risks worth flagging to auditor` section in `brief.md` — domain knowledge is never hardcoded into the verifier.

## Troubleshooting

**"`.northstar/state.json` already exists"** — a previous run is in flight. Use `/ns-status` to inspect, `/ns` to continue, or `/ns-abort` then re-init.

**"Plan file changed since last run"** — the plan's SHA differs from the recorded one. Choose "Re-parse" (Northstar rebuilds the Part list; in-flight Parts may be invalidated) or "Continue with cached structure" (proceed with the parts list from `state.json`).

**Verifier keeps re-dispatching executer** — there's a finding the executer cannot fix. After three attempts the orchestrator hands control back; read the latest `review.md` / `audit.md` and either resolve manually, edit the plan and `/ns retry`, or `/ns-skip`.

**Artifacts under `.northstar/parts/<id>/`** are your friend. They're the persistent record of every reasoning step. Open them any time.

## Design

- **Files-as-IPC.** All subagent communication happens through files in `.northstar/parts/<id>/`. The orchestrator's prompt context never bloats with subagent output bodies.
- **Single state.json + regenerated STATUS.md.** Atomic writes, one place to scan, plus a human-readable dashboard.
- **One Part per tick.** Hard pause at Part boundaries. Retry loops inside a Part happen within a single tick.
- **Stack-agnostic agents.** Project context is discovered by the scout at runtime and surfaced to the rest of the pipeline through `brief.md`.
- **Domain risks via a single channel.** Verifier's audit pass inherits project-specific concerns only if the scout surfaces them — the verifier's prompt itself contains no domain knowledge.

See [`docs/architecture.md`](docs/architecture.md) for the full design write-up, [`docs/decisions.md`](docs/decisions.md) for the rationale behind each major design choice, and [`docs/extending.md`](docs/extending.md) for how to add a new subagent role.

## License

MIT. See [`LICENSE`](LICENSE).

## Status

Northstar v0.11.0. Telemetry: none. Issues and PRs welcome.
