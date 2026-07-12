# Changelog

All notable changes to Suhail (formerly Northstar) are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(Nothing yet.)

## [1.0.0] — 2026-07-12

### Changed
- **Project renamed: Northstar → Suhail.** "Northstar" collided with several adjacent projects in the AI-agent and dev-tool space, so the project is rebranded to **Suhail** — the Arabic name for Canopus, the guiding star of Arab navigators. Same guiding-star identity, collision-free name. Everything else about the pipeline is unchanged; this release is the rename plus the version reset to 1.0.0 (the state-dir move is a breaking change, per the project's IPC-stability rule).
- Full old → new mapping:

  | Old | New |
  |---|---|
  | `/ns`, `/ns-init`, `/ns-discover`, `/ns-next`, `/ns-status`, `/ns-abort`, `/ns-auto`, `/ns-skip` | `/su`, `/su-init`, `/su-discover`, `/su-next`, `/su-status`, `/su-abort`, `/su-auto`, `/su-skip` |
  | Agents `ns-scout`, `ns-executer`, `ns-verifier`, `ns-indexer`, `ns-discover-scout`, `ns-discover-planner` | `su-scout`, `su-executer`, `su-verifier`, `su-indexer`, `su-discover-scout`, `su-discover-planner` |
  | State dir `.northstar/` (incl. `intel/`, `parts/`, `plans/`) | `.suhail/` |
  | Smoke-test artifact `.northstar-smoketest.txt` (env var `NORTHSTAR_SMOKE_TOKEN`) | `.suhail-smoketest.txt` (`SUHAIL_SMOKE_TOKEN`) |
  | Scripts `scripts/northstar-{write,read,tick,clean}.{sh,ps1}` | `scripts/suhail-{write,read,tick,clean}.{sh,ps1}` |
  | Plugin `northstar@northstar` from `wessamfathi/northstar` | `suhail@suhail` from `wessamfathi/suhail` |

### Migration
- **Finish or abort in-flight runs before upgrading.** Suhail reads state from `.suhail/`, so an existing `.northstar/` run will not be picked up. Either complete the run on the old version, or move the state (`mv .northstar .suhail`) before the first `/su` invocation.
- **Reinstall the plugin under its new name:** remove the old marketplace/plugin (`northstar@northstar`), then `/plugin marketplace add wessamfathi/suhail` and `/plugin install suhail@suhail`.
- **Update target-repo `.gitignore` entries** from `.northstar/` / `.northstar-*.txt` to `.suhail/` / `.suhail-*.txt`.
- Changelog entries below this one predate the rename and intentionally keep the old `Northstar` / `ns-` names.

## [0.15.0] — 2026-07-02

### Removed
- **Copy-install scripts deleted.** `scripts/install.sh` and `scripts/install.ps1` are gone; distribution is plugin-only. Migration for pre-0.15 copy installs: delete the hand-copied `~/.claude/commands/ns*.md`, `~/.claude/commands/northstar*.md`, `~/.claude/commands/scripts/northstar-*`, and `~/.claude/agents/ns-*.md`, then install the plugin — stale copies shadow or duplicate the plugin versions (`/plugin marketplace add wessamfathi/northstar` → `/plugin install northstar@northstar`). All references scrubbed from `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `docs/extending.md`, and `docs/architecture.md`. The local-dev flow now installs the working copy as a plugin from a local marketplace. Decision recorded in `docs/decisions.md` (supersedes the 2026-05-14 install-scope decision). Drops support for pre-plugin Claude Code versions; the manual project/user-copy lookup steps in `commands/ns.md` remain for hand-copied installs.

## [0.14.0] — 2026-07-02

### Added
- **Claude Code plugin distribution.** The repo is now its own plugin marketplace. `.claude-plugin/plugin.json` (plugin manifest) and `.claude-plugin/marketplace.json` (catalog) let users install with `/plugin marketplace add wessamfathi/northstar` then `/plugin install northstar@northstar`. The plugin bundles `commands/`, `agents/`, and `scripts/` as-is; the script installers (`scripts/install.{sh,ps1}`) remain as a fallback for pre-plugin Claude Code versions.

### Changed
- **Script-path resolution gained a plugin-aware first step.** `commands/ns.md`, `commands/ns-abort.md`, and `commands/ns-skip.md` now check `${CLAUDE_PLUGIN_ROOT}/scripts/` first (and `ns-skip.md` checks `${CLAUDE_PLUGIN_ROOT}/commands/ns.md` for the orchestrator locator). The plugin system substitutes the token inline before a command file is read; in non-plugin contexts it stays literal and resolution falls through to the existing project/user/dev-repo paths, so behavior is unchanged for script-installed and dev-repo setups.
- **`.claude-plugin/plugin.json` `version` added as a fourth release sync point** (`CLAUDE.md` § "Version bumps", `CONTRIBUTING.md` § "Releasing").

## [0.13.0] — 2026-07-01

### Fixed
- **Tick scripts synced to the batched state machine.** `scripts/northstar-tick.sh` / `.ps1` had drifted from the batched autorun/verification flow in `commands/ns.md`, breaking batch and autorun ticks; the scripts now match the current state machine.
- **`Abort` option in `ns.md`'s interactive complete-handler made reachable.** The menu previously exceeded the 4-option cap, pushing `Abort` out of reach; the menu is now split so `Abort` is always selectable.
- **`/ns-next` aligned with the batch `master_plan_approval` gate.** `commands/ns-next.md` now respects the same batch approval gate as the main orchestrator instead of bypassing it.
- **`install.sh` header label corrected.** The script's header comment mislabeled itself `POSIX`; it now correctly reads `bash`.
- **`northstar-read.sh` / `.ps1` parse parity.** The two scripts had diverged in how they parsed state; brought back in sync so both read the same fields the same way.
- Dead `die1()` function removed from `scripts/northstar-clean.sh`.
- `ns-` naming normalized in command prose (`ns-init.md`, `ns-discover.md`), and `fixtures/test_plan.md` fixture titles corrected.
- **Blocker-resolution routing.** The role subagents write `from: ns-scout` / `ns-executer` / `ns-verifier` in `blocker.md`, but the orchestrator's `needs_user` handler matched the pre-`ns-` bare names (`scout` / `executer` / `verifier`), so an agent-raised blocker matched no routing branch — the blocker card was not emitted and the post-resolution phase restoration was undefined. `commands/ns.md` now matches the `ns-`-prefixed `from:` values that agents actually emit (blocker-card gate, phase-restoration map, and the `blocker.md` schema line).
- Version sync: `commands/ns.md` heading + `tool_version` and the `README.md` footer bumped `0.11.0` → `0.12.0` to match the shipped `[0.12.0]` CHANGELOG section.
- `.gitignore` newline guard in `install.sh` / `install.ps1` so `.northstar/` is not concatenated onto a target `.gitignore` that lacks a trailing newline.

### Changed
- **Docs/prose accuracy sweep** across `README.md`, `docs/architecture.md`, `docs/decisions.md`, `commands/ns-next.md`, `commands/ns-discover.md`, and the fixtures: corrected stale artifact names (`research.md` / `plan.md` → `brief.md`), non-existent per-Part states (`researching` / `planning` / `reviewing` / `auditing` → `scouting` / `executing` / `executed` / `verifying`), merged-role names (`researcher` / `planner` / `security-auditor` → `ns-scout` / `ns-verifier`), and the `ns-verifier` model in the architecture table (`sonnet` → `haiku`).
- `install.ps1` parity with `install.sh`: added `-Help`, disabled positional binding so a bare positional path is rejected instead of silently binding to `-Project`, and aligned the STATUS.md artifact arrow glyph (`->` → `→`).
- Repository prepared for public release: removed internal-only development artifacts (`plans/`, `docs/script-extraction-candidates.md`, `.claude/skills/`) from the tree.

## [0.12.0] — 2026-05-22

### Changed
- **All six agent files renamed to `ns-` prefix.** `agents/scout.md` → `agents/ns-scout.md`, `agents/executer.md` → `agents/ns-executer.md`, `agents/verifier.md` → `agents/ns-verifier.md`, `agents/indexer.md` → `agents/ns-indexer.md`, `agents/discover-scout.md` → `agents/ns-discover-scout.md`, `agents/discover-planner.md` → `agents/ns-discover-planner.md`. Internal `name:` frontmatter and identity sentences updated to match.
- **`subagent_type` literals updated** in `commands/ns.md`, `commands/ns-init.md`, and `commands/ns-discover.md` to use the `ns-` forms (`ns-scout`, `ns-executer`, `ns-verifier`, `ns-indexer`, `ns-discover-scout`, `ns-discover-planner`).
- **`/northstar` alias removed.** `commands/northstar.md` was deleted in v0.7.2; all remaining doc references to `/northstar` as a usable command have been removed. The sole orchestrator entrypoint is `/ns`.
- **Docs and prose swept** — `CLAUDE.md`, `docs/architecture.md`, `docs/extending.md`, `docs/decisions.md`, `README.md`, `fixtures/README.md`, `fixtures/test_plan.md`, and `fixtures/parallel-verifier-plan.md` updated to use `ns-` identifier names wherever referring to agent files, dispatch names, or role identifiers. Historical CHANGELOG and decisions log entries are unchanged (they are archival records of the names that shipped under those versions).
- `state.tool_version` bumped to `0.12.0`.

## [0.11.0] — 2026-05-21

### Added
- **Atomic per-Part git commits**, on by default (`auto_commit: true` in `state.json`). After a Part is verified clean and marked `completed`, the orchestrator stages only that Part's `files_changed` and creates one commit (`commands/ns.md` `complete` handler step 1b + rewritten `## Commit policy`). Applies in all modes. Skipped Parts, empty `files_changed`, and non-git working directories are never committed. The orchestrator still never pushes, deploys, amends, or force-pushes; a failed commit (e.g. rejected by a pre-commit hook) raises an orchestrator blocker rather than retrying or amending.
- `no-commit` argument modifier for `/ns` (composes with any INIT shape, e.g. `/ns no-commit <plan>`, `/ns autorun no-commit <plan>`): sets `auto_commit: false` to disable per-Part commits for the run.

### Fixed
- **Helper-script path resolution.** `northstar-write`/`read`/`tick` were invoked as bare `scripts/*.{ps1,sh}` paths resolved against the working directory, so they only worked inside the Northstar dev repo. Added a project-then-global resolution convention to `commands/ns.md` (`./.claude/commands/scripts/` → `$CLAUDE_CONFIG_DIR/commands/scripts/` or `~/.claude/commands/scripts/` → `./scripts/` dev fallback) and updated every invocation in `ns.md`, `ns-abort.md`, `ns-skip.md` to use it. Northstar now works under both project (`./.claude`) and global installs. Docs (`architecture.md`, `extending.md`) synced.

### Changed
- The "Commit policy" section of `commands/ns.md` rewritten from "never commit" to default-on atomic commits; the interactive "Commit first" option is retained for on-demand commits when auto-commit is off.
- `/ns-discover` Phase 2 no longer asks free-form follow-up questions for hard constraints and out-of-scope; clarification happens through the AskUserQuestion clusters only, and Phase 5c writes `none` defaults so the answers-file schema stays satisfiable.
- `state.tool_version` bumped to `0.11.0`.

## [0.10.0] — 2026-05-20

### Added
- `/ns-abort` command (`commands/ns-abort.md`): standalone, zero-argument command that marks the current run `aborted` via `northstar-write` and preserves all `.northstar/` artifacts. Refuses cleanly when no run is active or the run is already aborted.
- `/ns-status` command (`commands/ns-status.md`): standalone, read-only command that prints `.northstar/STATUS.md` verbatim. Never advances state or writes any file.
- `/ns-skip` command (`commands/ns-skip.md`): standalone, zero-argument command that marks the current Part `skipped` via `northstar-write`, then offers to advance (delegating one tick to `ns.md`). The tick script's `skipped` branch auto-selects the next eligible Part.

### Changed
- `abort`, `status`, and `skip` removed as `/ns` arguments — each is now a dedicated single-shot command (`/ns-abort`, `/ns-status`, `/ns-skip`). The `/ns` argument-hint, argument table, INIT/refuse messages, and the `aborted` tick-handler note in `commands/ns.md` updated accordingly. The split follows a consistent rule: read-only or single-shot state actions are top-level commands; pipeline-driving verbs (`retry`, `run-to`, `continue`, INIT) stay as `/ns` arguments.
- INIT now auto-cleans a `finished`/`aborted` prior run without prompting (`commands/ns.md` INIT step 0b): it deletes `state.json`, `STATUS.md`, and the stale `.northstar/parts/` artifacts so a fresh run on a different plan cannot adopt a previous run's briefs. Intel under `.northstar/intel/` is never touched.
- `state.tool_version` bumped to `0.10.0`.

### Migration
- Replace `/ns abort` → `/ns-abort`, `/ns status` → `/ns-status`, `/ns skip` → `/ns-skip`. Behavior is identical.

## [0.9.0] — 2026-05-20

### Added
- `northstar-read.{ps1,sh}` (`scripts/northstar-read.ps1`, `scripts/northstar-read.sh`): artifact parser that reads a part directory and returns a structured JSON summary. Install scripts copy both into `commands/scripts/`.
- `northstar-write.{ps1,sh}` (`scripts/northstar-write.ps1`, `scripts/northstar-write.sh`): atomic state writer and STATUS.md renderer. Accepts full state JSON on stdin, writes `state.json` atomically, and renders `STATUS.md` from `state.tool_version` at runtime. Now owns the STATUS.md template previously inline in `commands/ns.md`. Install scripts copy both into `commands/scripts/`.

### Changed
- `commands/ns.md` rewired to pipe state JSON to `northstar-write` (via stdin) and call `northstar-read` for artifact parsing. The orchestrator no longer writes `state.json` directly.
- Inline `## STATUS.md generation` template removed from `commands/ns.md`; generation is now fully delegated to `northstar-write`.
- `## Script contracts` section added to `commands/ns.md` documenting the stdin/stdout interface for `northstar-read` and `northstar-write`.
- `/ns-init` and `/ns-discover` terminal handoffs quieted — finish confirmation is now a single narration sentence rather than a multi-line block.
- `/ns-auto` finish confirmation quieted to match.
- `state.tool_version` bumped to `0.9.0`.

## [0.8.0] — 2026-05-20

### Added
- `discover-scout` agent (`agents/discover-scout.md`): read-only, one-shot Phase 0 grounding agent dispatched by `/ns-discover`. Uses model `claude-haiku-4-5-20251001` (haiku). Scans the repo silently and returns a structured context summary as its response — no disk write. Keeps the interview session's context separate from the file-scan context.
- `discover-planner` agent (`agents/discover-planner.md`): write-only, one-shot Phase 5 plan-writing agent dispatched by `/ns-discover`. Uses sonnet. Consumes the answers file at `.northstar/discover/<slug>.answers.md` and writes a Northstar-format plan to `.northstar/plans/<slug>.md`.

### Changed
- `/ns-discover` now delegates Phase 0 silent grounding to `discover-scout` and Phase 5 plan-writing to `discover-planner`. The slash command retains the multi-turn interview (Phases 1–4) because `AskUserQuestion` and cross-turn context require the top-level session. The answers file at `.northstar/discover/<slug>.answers.md` is the IPC artifact between the command and `discover-planner` — same files-as-IPC contract as the rest of the pipeline.
- State schema `tool_version` bumped to `0.8.0`.

## [0.7.2] — 2026-05-19

### Added
- `/ns-auto` command: auto-detects the most recent plan under `.northstar/plans/` and runs it in autorun mode. Accepts an optional plan path argument.

### Changed
- Consolidated `commands/northstar.md` into `commands/ns.md` — `ns.md` is now the single source of truth for the orchestrator prompt; `northstar.md` has been removed.
- State schema `tool_version` bumped to `0.7.2`.

## [0.7.1] — 2026-05-18

### Added
- `run_phase: "finished"` terminal state, set automatically when all Parts complete successfully.

### Changed
- On INIT with a plan path, if `state.json` exists with `run_phase == "finished"` or `aborted == true`, Northstar now prompts once ("Delete its state and start a new run?") and auto-cleans on confirmation — instead of refusing outright.
- End-of-run AskUserQuestion simplified to `Show summary` / `Done`; removed the `Abort` option (state cleanup now happens automatically on the next `/ns <plan>` invocation).

## [0.7.0] — 2026-05-17

### Added
- **Speculative scout (B5).** Before each user-pause point (`master_plan_approval` AskUserQuestion and interactive part-completion AskUserQuestion), the orchestrator calls `next_eligible_part()` and speculatively dispatches a scout for the next batch leader (B5 pause point #1) or next in-batch Part (B5 pause point #2) in the same assistant turn. Artifacts are adopted if the user continues, or discarded (renamed to `*.speculative.md`) on Abort/Skip.
- **Pipelined verifier+scout (B6).** In auto-advance mode (`batch_auto_approve == true` or `mode == "run-to"`), the verifier for Part N and a speculative scout for Part N+1 are dispatched in the same assistant turn, reducing wall-clock time per Part to `max(verifier, scout)`. Speculative artifacts are discarded if the verifier flags blockers and triggers re-execution.
- `Speculative dispatch (B5/B6)` subsection in the orchestrator defining `next_eligible_part()`, the speculative scout dispatch procedure, Discard rule, and Adopt rule. ("B5"/"B6" are the two speculation origins as recorded in `state.speculative.origin` — pause-point speculation and pipelined verifier+scout respectively; the letters are historical work-item ids.)
- Second parallel-dispatch carve-out in `## Don't`: verifier-for-Part-N + scout-for-Part-N+1 in auto-advance mode is explicitly permitted with a documented safety argument.
- `state.speculative` optional field (`{ part_id, origin }`) in the state schema.

### Changed
- State schema `tool_version` bumped to `0.7.0`.
- Plan SHA drift handler now invokes the Discard rule on any stale `state.speculative` before re-parsing or resuming.

## [0.6.0] — 2026-05-17

> Version 0.5.0 was skipped — the numbering jumps from 0.4.0 to 0.6.0; no 0.5.x release ever existed.

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
- **Performance phase 1 — context-discipline wins across the role pipeline.** Six coordinated improvements land together, each targeting a specific source of wasted context or wasted dispatch in the role-subagent loop. (A1) The researcher now emits a stack-intel baseline so downstream roles inherit project conventions without re-discovering them. (A2) The planner's TL;DR section is gated as a hard contract — the orchestrator surfaces it on transition and refuses malformed deliverables. (A3) The executer emits early-exit signals (blocker.md vs. partial execution.md) so the orchestrator can short-circuit reviewer/auditor dispatch when no source-file work landed. (A4) The reviewer enforces a hard cap on per-review nits (five) so review.md stays bounded in context size regardless of how noisy the diff is. (A5) The security-auditor gains a checklist-coverage section that ties each finding back to a domain risk surfaced in research.md, making audit.md diffable across attempts. (A6) The indexer emits a sources manifest enumerating every file scanned so re-runs are reproducible and the manifest itself is a cache key. (A1–A6 were the internal work-item ids for this phase; they appear nowhere in the shipped code.)

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
- **Bug 1 (showstopper):** the four read-only role subagents (researcher, planner, reviewer, security-auditor) lacked the `Write` tool, so they could not produce their output artifacts (research.md, plan.md, review.md, audit.md). Pipeline runs would fail silently at Part 1 / researching phase. Discovered during a pre-flight audit against a real-world plan file.
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
