# Changelog

All notable changes to Northstar are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] — 2026-05-17

### Added
- **Speculative scout (B5).** Before each user-pause point (`master_plan_approval` AskUserQuestion and interactive part-completion AskUserQuestion), the orchestrator calls `next_eligible_part()` and speculatively dispatches a scout for the next batch leader (B5 pause point #1) or next in-batch Part (B5 pause point #2) in the same assistant turn. Artifacts are adopted if the user continues, or discarded (renamed to `*.speculative.md`) on Abort/Skip.
- **Pipelined verifier+scout (B6).** In auto-advance mode (`batch_auto_approve == true` or `mode == "run-to"`), the verifier for Part N and a speculative scout for Part N+1 are dispatched in the same assistant turn, reducing wall-clock time per Part to `max(verifier, scout)`. Speculative artifacts are discarded if the verifier flags blockers and triggers re-execution.
- `Speculative dispatch (B5/B6)` subsection in the orchestrator defining `next_eligible_part()`, the speculative scout dispatch procedure, Discard rule, and Adopt rule.
- Second parallel-dispatch carve-out in `## Don't`: verifier-for-Part-N + scout-for-Part-N+1 in auto-advance mode is explicitly permitted with a documented safety argument.
- `state.speculative` optional field (`{ part_id, origin }`) in the state schema.

### Changed
- State schema `tool_version` bumped to `0.7.0`.
- Plan SHA drift handler now invokes the Discard rule on any stale `state.speculative` before re-parsing or resuming.

## [0.6.0] — 2026-05-17

### Added
- **Parallel scout batching and master-plan approval.** DAG levels are computed at INIT; all level-0 scouts are dispatched in a single assistant turn as multiple parallel `Agent(...)` calls. After scouts complete, a single consolidated AskUserQuestion presents all Parts' plans together with four options: `Approve all and start executing`, `Approve and review Parts individually`, `Show full briefs`, `Abort`. After all Parts in a level complete, level N+1 scouts are dispatched in parallel automatically.
- State schema gains `run_phase` (top-level), `current_batch` (list of part ids being scouted/approved), `batch_auto_approve` (boolean), and per-Part `level` (integer DAG level).
- STATUS.md header branches on `run_phase` to show batch scouting/approval context. Progress table gains a `Level` column.
- Explicit carve-out in `## Don't` for parallel scout dispatch (read-only, distinct output paths, no shared mutable state).
- DAG cycle detection at INIT: malformed plans with circular dependencies produce a blocker before `state.json` is created.

### Changed
- State schema `tool_version` bumped to `0.6.0`.
- INIT no longer ends with AskUserQuestion — it narrates and re-ticks directly into `batch_scouting`.

## [0.4.0] — 2026-05-17

### Added
- **Performance phase 1 — context-discipline wins across the role pipeline.** Six coordinated improvements land together, each targeting a specific source of wasted context or wasted dispatch in the role-subagent loop. (A1) The researcher now emits a stack-intel baseline so downstream roles inherit project conventions without re-discovering them. (A2) The planner's TL;DR section is gated as a hard contract — the orchestrator surfaces it on transition and refuses malformed deliverables. (A3) The executer emits early-exit signals (blocker.md vs. partial execution.md) so the orchestrator can short-circuit reviewer/auditor dispatch when no source-file work landed. (A4) The reviewer enforces a hard cap on per-review nits (five) so review.md stays bounded in context size regardless of how noisy the diff is. (A5) The security-auditor gains a checklist-coverage section that ties each finding back to a domain risk surfaced in research.md, making audit.md diffable across attempts. (A6) The indexer emits a sources manifest enumerating every file scanned so re-runs are reproducible and the manifest itself is a cache key. See `plans/plan_now.md` for the source analysis behind these changes.

### Changed
- State schema bumps `tool_version` to `0.4.0`.
- `commands/northstar.md` heading and STATUS.md template header reflect v0.4.0.

## [0.3.1] — 2026-05-15

### Added
- **Refined role subagent output contracts across six roles.** Every role subagent (researcher, planner, executer, reviewer, security-auditor, indexer) now opens its deliverable with a `## TL;DR` block (one-to-three bullets) so the orchestrator and human reader can scan the headline before the full body. Empty findings are canonicalised to the literal phrase `(none observed)` everywhere a list could otherwise be ambiguous (research gotchas, reviewer issues, auditor findings, indexer notes). The planner deliverable now exposes an explicit `## External dependencies` section that the orchestrator surfaces when transitioning out of `planning`; the executer's `## Manual follow-ups required` section is surfaced when transitioning out of `executing`. The reviewer enforces a hard cap of five nits per review (additional nits collapse into a single "N more nits omitted" line). The security-auditor adds a `## Checklist coverage` section that enumerates which domain risks from research.md were checked and the outcome. The indexer adds a `## Sources scanned` manifest listing every file path consulted so re-runs are diffable.

### Changed
- State schema bumps `tool_version` to `0.3.1`.
- `commands/northstar.md` heading and STATUS.md template header reflect v0.3.1.

## [0.3.0] — 2026-05-15

### Added
- **`/ns-next` slash command — zero-argument auto-stepper.** Advances the current Northstar run by exactly one logical state-machine tick without prompting. Refuses when there is no active run, when the run is aborted, when an unresolved `blocker.md` is open on the current Part, or when all Parts are already `completed`/`skipped`. At `awaiting_plan_approval` it injects an implicit "Approve" so the run progresses to `executing` without re-prompting; for every other eligible state (`pending`, `researching`, `planning`, `executing`, `reviewing`, `auditing`) it delegates to `northstar.md` for exactly one tick. Never loops, even in `run-to` mode. Lives at `commands/ns-next.md`; installed automatically by the existing `commands/*.md` glob in both installers.

### Changed
- State schema bumps `tool_version` to `0.3.0`.
- `commands/northstar.md` heading and STATUS.md template header reflect v0.3.0.

## [0.2.0] — 2026-05-15

### Added
- **`/ns-init` slash command — one-shot project scanner.** Dispatches the new `indexer` subagent to read manifests (root + nested), conventions docs (CLAUDE.md / AGENTS.md / .cursorrules / `.github/copilot-instructions.md` / README), and the top-level directory tree, then caches structured intel under `.northstar/intel/` as four files: `stack.md` (languages, package managers, build/test/lint commands per package), `layout.md` (top-level layout with one-line purpose per directory), `conventions.md` (distilled house rules), and `modules.md` (module inventory with entry points and responsibilities). Idempotent: re-run with no arguments prompts Refresh / Skip / Show summary; `/ns-init refresh` skips the prompt. Also creates `.northstar/`, `.northstar/intel/`, and `plans/` directories if missing. Lives at `commands/ns-init.md`; the new subagent lives at `agents/indexer.md`. Both are installed automatically by the existing `commands/*.md` and `agents/*.md` globs in both installers.
- **Indexer subagent** (`agents/indexer.md`). Read-only role, sonnet model, write-or-block contract matching the other role subagents. Carries the same fail-loud preflight, blocker protocol, and "no inline-chat substitution" discipline. Invoked only by `/ns-init`.
- **Researcher consumes intel as baseline.** The researcher agent now reads `.northstar/intel/*.md` as step 0 of its process — copying project-wide stack, layout, conventions, and module information into its report instead of rediscovering it per Part. Falls back to from-scratch discovery if intel is missing or stubbed.
- **Orchestrator passes the intel directory to the researcher.** `commands/northstar.md`'s `researching` state now adds an `Intel directory: .northstar/intel/` line to the researcher dispatch prompt.

### Changed (breaking)
- **Hard precursor gate on `/ns`, `/northstar`, and `/ns-discover`.** Both commands refuse to run when `.northstar/intel/` is missing any of the four required files. `/ns` enforces the gate at INIT only — once a run is in flight (`state.json` exists), subsequent ticks do not re-check intel, so deleting intel mid-run does not break the active pipeline. `/ns-discover` enforces the gate at the top of every invocation since it produces a one-shot deliverable. **Migration:** existing users must run `/ns-init` once per project before their next `/ns` or `/ns-discover` invocation.

### Changed
- State schema bumps `tool_version` to `0.2.0`.
- `commands/northstar.md` heading and STATUS.md template header reflect v0.2.0.

## [0.1.4] — 2026-05-15

### Added
- **`/ns-discover` slash command — interactive vision-to-plan agent.** Interviews the user via `AskUserQuestion` and free-text turns to capture vision, scope, dependencies, and per-Part detail, then writes a markdown plan in the exact contract `/ns` expects (H3 `### Part N — <title>` headings with em-dash, `Depends on Part N` declarations, free-form briefs). Defaults the output path to `plans/<slug>.md` derived from the captured title; accepts an optional `output-path` argument to override. Independent of any active Northstar run — produces a plan file the rest of the pipeline can execute. Lives at `commands/ns-discover.md`; installed automatically by the existing `commands/*.md` glob in both installers.

### Changed
- State schema bumps `tool_version` to `0.1.4`.

## [0.1.3] — 2026-05-15

### Fixed
- **Researcher false-positive preflight blocker.** The researcher's fail-loud preflight checked the output directory's existence with `Glob`, but `Glob` does not list empty directories — so on the first dispatch after INIT (when `.northstar/parts/<id>/` is freshly created and empty) the check fired even though the directory was present. The researcher would then bail out without producing `research.md`. The preflight no longer checks the directory; the orchestrator creates it at INIT and the researcher trusts the path.
- **Subagent inline-response bypass.** A subagent could silently skip its disk write and return the deliverable body inline in the chat response. The orchestrator's output verification correctly flagged this as a missing artifact and routed to `needs_user`, but the agent prompts did not explicitly forbid the behavior, so it kept recurring (observed against the reviewer in the smoke run that surfaced this bug).

### Added (safety)
- **Write-or-block contract in every role agent.** Researcher, planner, executer, reviewer, and security-auditor now carry an explicit contract section requiring the `Write` tool call as the deliverable, forbidding inline-chat substitution, restricting the final chat message to a one-line confirmation, and carving the single exception for the Blocker protocol (which still requires both `blocker.md` and a stub deliverable on disk). Matching `Don't` / `Constraints` bullets reinforce the rule.

### Changed
- State schema bumps `tool_version` to `0.1.3`.

## [0.1.2] — 2026-05-15

### Fixed
- **Bug 1 (showstopper):** the four read-only role subagents (researcher, planner, reviewer, security-auditor) lacked the `Write` tool, so they could not produce their output artifacts (research.md, plan.md, review.md, audit.md). Pipeline runs would fail silently at Part 1 / researching phase. Discovered during a pre-flight audit against <private-project>'s <private-plan>.md.
- **Bug 2:** the plan parser extended the last Part's body to end-of-file, absorbing any plan-level trailing sections (`## Critical files reference`, `## Verification`, `## Open questions`, etc.) into the final Part's brief. A Part's body now ends at the EARLIER of the next Part heading, the next H2 heading, or EOF.
- **Bug 3:** the dependency parser only matched `Depends on Part N` for a single N. A line like `Depends on Part 2 and Part 4` captured only Part 2. The new rule scans from each `Depends on` anchor to end-of-line and collects every integer preceded by `Part` or `Parts` (case-insensitive, deduplicated).

### Added (safety)
- **Fail-loud preflight in every role agent.** Each role now verifies its inputs (Part description present, prior-stage artifacts non-empty with required section headers) before doing any work, and writes a blocker.md instead of improvising when inputs are missing. This prevents cascade hallucinations where, e.g., a planner without research.md would have invented a plan from the Part description alone.
- **Output verification in the orchestrator.** After every `Agent(...)` dispatch, the orchestrator verifies the expected artifact exists, is non-empty, and contains the role's expected H2 sentinel sections. On failure it writes a blocker.md (`from: orchestrator`) and routes to `needs_user` instead of advancing state. The orchestrator's "Don't" list now explicitly forbids improvising research, plans, execution summaries, or verdicts on behalf of a failing subagent.

### Added (polish)
- `git add -N <new-files>` before computing the diff, so newly-created files appear in `git diff` output for the reviewer and security-auditor instead of being invisible.
- Researcher now uses Glob to find nested manifests (e.g. `services/*/package.json`) and surfaces both root and sub-package commands in `## Stack conventions` — fixes the monorepo / sub-package case where the root manifest would have been wrongly treated as authoritative.
- "Show manual follow-ups" is now an option in the Part-completion AskUserQuestion. Reads `execution.md`'s `## Manual follow-ups required` section so the user is reminded to deploy edge functions, regen types, apply migrations, etc. before continuing.
- `/ns continue` is accepted as a friendly alias for `/ns` with no arguments.

### Changed
- State schema bumps `tool_version` to `0.1.2`.

## [0.1.1] — 2026-05-14

### Fixed
- Orchestrator could not actually dispatch role subagents from inside a Claude Code subagent context — the platform does not allow subagents to spawn nested subagents. Moved the orchestrator logic out of `agents/northstar.md` and into the slash command body (`commands/northstar.md`), so the top-level session plays the orchestrator role and dispatches role subagents directly. The role subagents (researcher, planner, executer, reviewer, security-auditor) are unchanged.

### Changed
- `commands/ns.md` is now a thin pointer that reads `commands/northstar.md` and executes its instructions, keeping a single source of truth for the orchestrator prompt.
- Install scripts now remove any stale `~/.claude/agents/northstar.md` (or `<project>/.claude/agents/northstar.md`) left behind by a v0.1.0 install.
- State schema bumps `tool_version` to `0.1.1` and adds a top-level `aborted` boolean (previously implied via `current_step == "aborted"`).

## [0.1.0] — 2026-05-14

### Added
- Initial release.
- `northstar` orchestrator subagent.
- Role subagents: `researcher`, `planner`, `executer`, `reviewer`, `security-auditor`.
- Slash commands `/northstar` and `/ns` alias.
- Modes: interactive (default) and `run-to <part-id>` (auto-advance to a target Part).
- File-based subagent IPC under `.northstar/parts/<id>/`.
- Self-test fixture at `fixtures/test_plan.md`.
- Install scripts for POSIX (`scripts/install.sh`) and Windows (`scripts/install.ps1`).
- Plan-format contract documented in `docs/plan-format.md`.
