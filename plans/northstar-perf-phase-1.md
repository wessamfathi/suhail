# Northstar perf Phase 1

This plan executes the conservative, surgical optimizations A1–A6 from `plans/plan_now.md`. Each item is a low-risk edit that preserves Northstar's core architectural contract (file-based IPC, role separation, write-or-block, output verification). The bundle's goal is to roughly halve per-Part wall-clock with no architectural risk.

Scope is strictly A1–A6 plus a final release Part. All B-series structural and transformational optimizations (B1–B18) are explicitly out of scope and will be addressed in follow-up plans. Each Part is independent — no `Depends on` edges — so they can land in any order; the release Part (Part 7) is intended to be run last but carries no formal dependency.

Per-Part verification is the standard Northstar smoke test from `CLAUDE.md`: reinstall the working copy as the project's own `.claude/`, open a fresh Claude Code session, run `/ns fixtures/test_plan.md`, walk it through, and clean up. See each Part for specifics.

## Phase 1 — Surgical wins

### Part 1 — Parallelize reviewer and security-auditor dispatch

Collapse the `reviewing` and `auditing` phases in `commands/northstar.md` (around `:208-239`) into a single combined phase that dispatches both subagents in parallel — one Agent message containing two tool calls. Unify the two verdicts using worst-of semantics: if either subagent returns `blockers`, re-execute the Part; otherwise advance. The two artifacts (`review.md` and `audit.md`) remain separate on disk.

The "Don't call subagents in parallel" rule at `commands/northstar.md:354` exists to enforce the researcher → planner → executer dependency. Relax it to "serial except for the independent reviewer/auditor pair." Update both the rule wording and any narration discipline that assumes a strictly serial state machine.

Touch points: `commands/northstar.md` state-machine description, dispatch shape for `reviewing`/`auditing`, verdict-merge logic, the "Don't" rule at `:354`. No agent-file edits required — `agents/reviewer.md` and `agents/security-auditor.md` already state the roles are independent.

**Depends on:** (none)

**Verification:**
- Manual: `scripts/install.ps1 -Project <dev-dir>\northstar -Force`; fresh Claude Code session in `<dev-dir>\northstar`; run `/ns fixtures/test_plan.md`; confirm both `review.md` and `audit.md` are written and the phase narration shows a single combined event rather than two serial events. Wall-clock for the verify phase should drop noticeably.
- Programmatic: after the fixture run, `Test-Path .northstar\parts\part-1\review.md` AND `Test-Path .northstar\parts\part-1\audit.md` both true; state.json shows verdicts merged; cleanup with `/ns-abort` (if needed) and `Remove-Item -Recurse -Force .northstar, .northstar-smoketest.txt`.

### Part 2 — Make researcher stack-discovery conditional on intel

In `agents/researcher.md` (around `:42-56`), the current step 0 says "read intel to skip re-deriving stack/build/test/lint/conventions" and step 1 then orders the model to do exactly that re-derivation. Rewrite step 1 to be conditional: if `.northstar/intel/stack.md` is present and not blocked, skip step 1 entirely. Only inspect sub-package manifests when the current Part touches a sub-package that intel did not list.

Preserve the existing section structure (`## Input`, `## Process`, `## Output`, `## Blocker protocol`, `## Don't`) per CLAUDE.md convention. Keep the fallback path for projects without intel (so the researcher still works when `/ns-init` was skipped, which can happen on tiny test runs).

Touch points: `agents/researcher.md` step 1 wording and any cross-references in subsequent steps.

**Depends on:** (none)

**Verification:**
- Manual: `scripts/install.ps1 -Project <dev-dir>\northstar -Force`; fresh Claude Code session in `<dev-dir>\northstar`; ensure `.northstar/intel/` exists (run `/ns-init` if needed); run `/ns fixtures/test_plan.md`; inspect the researcher's tool-call trace and `research.md` to confirm stack re-derivation was skipped (no Read on root manifests, tsconfig, eslint, etc.).
- Programmatic: after the fixture run, `research.md` should still contain a usable Stack conventions / Files-to-touch / Gotchas summary (the researcher quotes intel rather than reproducing it); cleanup as in Part 1.

### Part 3 — Skip security-auditor on no-surface diffs

Add an orchestrator-side heuristic to `commands/northstar.md` so that before dispatching the security-auditor, the orchestrator inspects the set of changed paths for the current Part. If every changed path matches a no-surface pattern, synthesize `audit.md` with `Verdict: clean` and `Summary: No security-relevant surface (orchestrator heuristic).` and skip the LLM dispatch entirely.

No-surface pattern set (case-insensitive, exact-match on segments where relevant):
- Extensions: `*.md`, `*.css`, `*.scss`, `*.sass`, `*.less`, `*.svg`, `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, `*.ico`, `*.woff`, `*.woff2`, `*.ttf`, `*.eot`, `*.snap`.
- Path segments: `tests/`, `__tests__/`, `test/`, `spec/`.
- Filename patterns: `*.test.*`, `*.spec.*`, `*.stories.*`.

If ANY changed path falls outside the set, dispatch the auditor normally. Coordinate with Part 1: if Parts 1 and 3 both land, the heuristic gate runs before the parallel reviewer+auditor dispatch and short-circuits only the auditor leg (reviewer still runs).

Touch points: `commands/northstar.md` state-machine, the `auditing` phase entry condition, and the synthetic `audit.md` template.

**Depends on:** (none)

**Verification:**
- Manual: reinstall as above; create a docs-only fixture Part (or use `fixtures/test_plan.md` modified to touch only `.northstar-smoketest.txt` — already a no-code path, but adjust the pattern list to include it or use a `.md`-touching Part); run it; confirm `audit.md` is written by the orchestrator (not a subagent) and that no auditor dispatch appears in the trace.
- Programmatic: after the fixture run, `audit.md` exists with `Verdict: clean` and the heuristic summary string; tool-use trace shows zero `security-auditor` Agent dispatches for that Part; cleanup as in Part 1.

### Part 4 — Add auto-advance option to interactive pauses

Surface an "Approve and auto-advance until next blocker" option on both interactive pauses in `commands/northstar.md`: the plan-approval pause (`awaiting_plan_approval`, around `:176`) and the part-completion question (around `:251`). When the user selects this option, flip `mode = "run-to"` in `state.json` with the run-to target set to the last Part. No new state-machine phase is needed — this promotes the existing `run-to` capability into the default question UI.

Preserve all existing options (Approve / Reject / Abort / etc.). The new option becomes one additional choice. Document the resulting `state.json` mutation in the orchestrator narration so the user can see the mode flip in STATUS.md.

Touch points: the two AskUserQuestion definitions in `commands/northstar.md`, the option-handling logic that mutates `state.json`, the STATUS.md template if it surfaces `mode`.

**Depends on:** (none)

**Verification:**
- Manual: reinstall as above; run `/ns fixtures/test_plan.md`; at the first interactive pause select "Approve and auto-advance until next blocker"; confirm Northstar runs through the remaining Parts without further prompts (fixture has one Part, so this is more meaningful with a multi-Part fixture — also run against `<dev-dir>\tot\<private-plan>.md` if available). Confirm `state.json` shows `mode: "run-to"` and a non-null `run_to`.
- Programmatic: after a multi-Part run with auto-advance selected, `jq '.mode, .run_to'` on `state.json` returns `"run-to"` and the last Part's id; cleanup as in Part 1.

### Part 5 — Switch reviewer and auditor to Haiku 4.5

In `agents/reviewer.md` and `agents/security-auditor.md`, change the `model:` field in the frontmatter from `sonnet` to `claude-haiku-4-5-20251001`. Leave researcher and planner on Sonnet, executer on Opus. No prompt edits — Haiku 4.5 is being trusted to handle the structured-verdict task at its current prompt size.

This is a one-line change per file. The risk (Haiku may produce more false negatives on subtle issues) is accepted; verification is the standard fixture smoke. If a future fixture regression shows up, the change is trivial to revert via git.

Touch points: `agents/reviewer.md` frontmatter, `agents/security-auditor.md` frontmatter.

**Depends on:** (none)

**Verification:**
- Manual: reinstall as above; run `/ns fixtures/test_plan.md`; confirm the reviewer and auditor dispatches return valid `review.md` and `audit.md` with the expected sections; confirm Claude Code's dispatch trace shows the Haiku model id was used.
- Programmatic: `Get-Content agents\reviewer.md, agents\security-auditor.md | Select-String 'model:'` shows `claude-haiku-4-5-20251001` for both; after the fixture run, both artifact files exist, are non-empty, and contain their required sentinels per `commands/northstar.md` output verification; cleanup as in Part 1.

### Part 6 — Trim reviewer input bundle

In `commands/northstar.md` (around `:215-228`), change the reviewer dispatch shape so the reviewer no longer receives the full research.md and full plan.md. Instead, pass only the sections reviewer actually consumes per `agents/reviewer.md:42`:
- From `research.md`: the `Stack conventions`, `Gotchas`, and `Patterns to follow` sections.
- From `plan.md`: the `## Steps` section.
- Diff, `execution.md`, and changed files at HEAD continue to be passed as today.

Implementation: either (a) extract the relevant sections inline into the dispatch prompt at orchestrator time, or (b) write a trimmed `review-input.md` artifact into `.northstar/parts/<id>/` and pass that path. Option (b) is preferred because it keeps with file-based IPC and lets the reviewer Read a single trimmed input. Either way, update `agents/reviewer.md` to document the new input contract.

Touch points: `commands/northstar.md` reviewer dispatch shape; `agents/reviewer.md` Input section.

**Depends on:** (none)

**Verification:**
- Manual: reinstall as above; run `/ns fixtures/test_plan.md`; inspect the reviewer dispatch prompt (or the new `review-input.md` artifact) and confirm only the listed sections are present from research/plan; confirm `review.md` still ends with a valid verdict.
- Programmatic: if option (b), `Test-Path .northstar\parts\part-1\review-input.md` is true and the file contains only the listed sections; reviewer's `review.md` exists with required sentinels; cleanup as in Part 1.

## Release

### Part 7 — Bump tool_version to 0.4.0 and add CHANGELOG entry

After Parts 1–6 have landed, bump `tool_version` to `0.4.0` in all three locations per `CLAUDE.md`:

1. `commands/northstar.md`:
   - Top H1 heading: `# /northstar (alias: /ns) — Northstar v0.4.0`.
   - `tool_version` field inside the state schema block.
   - STATUS.md template header.
2. `README.md` footer line: `Northstar v0.4.0. Telemetry: none.`
3. `CHANGELOG.md`: new top section `## [0.4.0] — <today's date>` summarizing A1–A6 wins, with a note pointing at `plans/plan_now.md` for the source analysis.

After the file edits land, the user should run `git tag v0.4.0` and push. This Part does not include the tag push — it stops at file edits.

This Part carries no formal `Depends on` edge per user preference, but is intended to be run last; if executed before Parts 1–6, the CHANGELOG entry will describe changes that don't yet exist.

Touch points: `commands/northstar.md`, `README.md`, `CHANGELOG.md`.

**Depends on:** (none)

**Verification:**
- Manual: `git grep -n '0\.4\.0'` shows the new version in all three required locations and nowhere stale; `CHANGELOG.md` opens with `## [0.4.0] — <date>` and lists A1–A6; reinstall and run `/ns fixtures/test_plan.md` once more to confirm STATUS.md renders with the new version string.
- Programmatic: `Select-String -Path commands\northstar.md, README.md, CHANGELOG.md -Pattern '0\.4\.0'` returns matches in all three files; `git status` shows only the three expected modified files; cleanup as in Part 1.

## Critical files reference

- `commands/northstar.md` — orchestrator state machine; touched by Parts 1, 3, 4, 6, 7.
- `agents/researcher.md` — touched by Part 2.
- `agents/reviewer.md` — touched by Parts 5 and 6.
- `agents/security-auditor.md` — touched by Part 5.
- `README.md` — touched by Part 7.
- `CHANGELOG.md` — touched by Part 7.
- `plans/plan_now.md` — source analysis document; reference, do not edit.
- `fixtures/test_plan.md` — primary smoke-test target for every Part's verification.
- `<dev-dir>\tot\<private-plan>.md` — optional second smoke target (per `CLAUDE.md`) for Parts touching researcher or stack-conventions plumbing (Part 2) and for multi-Part auto-advance (Part 4).

## Open questions

- B8 (prompt caching audit) was deferred out of scope for this plan but is flagged in `plans/plan_now.md` as potentially the largest single win. Worth a follow-up 30-minute spike before or after this plan lands.
- A5 trusts Haiku 4.5 unconditionally per the discovery interview; if any fixture regression surfaces (false negatives on subtle reviewer/auditor issues), revert via git and reopen as an A/B comparison Part.
- Part 7 (release) has no formal dependency edge per user preference, but is intended to land last. If a future operator runs it out of order, the CHANGELOG entry will be premature.
- The no-surface pattern set in Part 3 is initial — tune via experience after the first few Parts ship; consider extracting to a settings.json field if it needs frequent edits.
