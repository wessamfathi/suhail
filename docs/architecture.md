# Architecture

Northstar is a thin coordinator over three specialized roles. This document covers the design choices behind the structure, the data flow, and the reasoning behind the constraints.

## The four roles

| Role | Tools | Model | Output |
|---|---|---|---|
| **indexer** | Read, Write, Glob, Grep, Bash | sonnet | `.northstar/intel/{stack,layout,conventions,modules}.md` — project-wide baseline cached once per project by `/ns-init` |
| **scout** | Read, Write, Glob, Grep | sonnet | `brief.md` — discovered stack conventions, files to touch, reusable helpers, gotchas, domain risks, and ordered step list |
| **executer** | Read, Edit, Write, Glob, Grep, Bash | sonnet | `execution.md` — file changes, command results, manual follow-ups |
| **verifier** | Read, Write, Glob, Grep, Bash | sonnet | `review.md` + `audit.md` — two-pass verdict and findings (review pass: correctness, regressions, convention drift; audit pass: security and compliance) |

Plus the **orchestrator** (`northstar`) itself: opus, has access to Agent + AskUserQuestion + state I/O, dispatches the roles in sequence. The **indexer** is dispatched only by `/ns-init`, not by the orchestrator — it runs once per project as a precursor.

## Pipeline shape

```
(once per project)
  /ns-init → indexer → .northstar/intel/{stack,layout,conventions,modules}.md

(per Part, inside /ns)
  scout → (user approval) → executer → verifier → completed → (user approval) → next Part
                              ▲           │
                              │           │ findings include [blocker]
                              └───────────┘
                              up to max_retries (default 3)
```

The intel cache is the only project-wide artifact. Per-Part artifacts live under `.northstar/parts/<id>/`. The scout reads the intel cache as step 0 of its process so it does not re-derive stack, layout, conventions, or module structure on every Part.

The verifier runs two sequential passes on every Part: a review pass (correctness, regressions, convention drift) producing `review.md`, then an audit pass (security and compliance) producing `audit.md`. If either pass finds `blocker`-severity issues, the verifier triggers a re-dispatch of the executer. This serializes feedback so the executer addresses correctness before security.

## Why files-as-IPC

Every subagent communicates with the orchestrator and with subsequent subagents through markdown files in `.northstar/parts/<id>/`. The orchestrator passes paths in prompts, never artifact bodies.

Trade-off: each subagent does a small amount of file I/O it could have avoided. In exchange:

- The orchestrator's own context stays bounded regardless of plan size or artifact size. Without this, walking a 50-Part plan would blow out Northstar's context within a few Parts.
- Artifacts are inspectable. A user reviewing a run can read `brief.md` and form their own opinion before approving the plan. Same for every later stage.
- Subagents are stateless. Each invocation can read its inputs from disk, run, write outputs, and exit. No long-lived agents, no in-memory state to corrupt.
- Re-running a stage is trivial. The orchestrator's `retry` command renames the existing artifacts to `*.orig.md` and starts fresh.

## Why one Part per tick

The orchestrator advances state by exactly one logical step per invocation (one Part end-to-end in interactive mode). When the Part finishes, it ends the turn with an AskUserQuestion. The user explicitly chooses to continue.

This is the system's most important property. The user requested it explicitly: every Part is a checkpoint. In interactive mode there is no way to advance past a Part without the user authorizing.

`run-to <part-id>` is the explicit escape hatch for unattended runs. It bypasses per-Part pauses AND scout-approval, walks Parts until it hits the named target, and then reverts to interactive mode. A 20-Part safety cap forces an interactive checkpoint even mid-target, so runs can't go arbitrarily long unattended.

## Why the verifier uses two passes

The verifier runs a review pass followed by an audit pass within a single agent invocation. The passes are sequential — the audit pass runs only after the review pass is clean — so the executer addresses correctness before security concerns.

- The review pass catches: missing planned steps, broken patterns, missed reuse opportunities, regressions outside the planned files, type/null safety, performance smells.
- The audit pass catches: missing auth checks, injection, secrets in the diff, missing input validation, deep-link host validation.

Many bugs are correctness AND security issues (e.g. a missing auth check is both). Both passes will catch them; the verifier reports findings from both in its output artifacts (`review.md` and `audit.md`).

## Why the domain-hints channel

The verifier's audit pass is intentionally generic — language-agnostic checklist, no project knowledge. The scout writes a `Domain risks worth flagging to auditor` section in `brief.md` when the codebase implies specific concerns (e.g. "this Part touches AI-generated content; verify provenance is stored", or "this Part adds a new RPC; ensure RLS-equivalent policy is set").

This is the **only** channel by which project-specific risk reaches the verifier's audit pass. The verifier reads that section and folds it into its checklist. If the scout writes nothing there, the audit pass runs purely on its generic checks.

This design means: to use Northstar in a new domain, you don't extend the verifier's prompt — you trust the scout to discover and surface what matters. Domain knowledge flows through runtime artifacts, not hardcoded prompt edits.

## State management

The orchestrator owns `.northstar/state.json` exclusively. It always writes the full file from its in-memory representation; never partial-updates. The schema is documented in `commands/northstar.md`.

## Why the orchestrator lives in the slash command, not as a subagent

The orchestrator's logic is in `commands/northstar.md` (the slash command body) rather than `agents/northstar.md` (a subagent). The reason is a Claude Code platform constraint: **subagents invoked via the Agent tool cannot themselves spawn further subagents.** Only the top-level session can dispatch subagents. If the orchestrator were a subagent, it would have no way to call the scout / executer / verifier that it coordinates.

By putting the orchestrator into the slash command, invoking `/ns` or `/northstar` makes the top-level session take on the orchestrator role for the turn. The top-level session does have access to the Agent tool and can dispatch the role subagents (scout, executer, verifier), which run in isolated contexts. The pipeline tree is exactly two levels deep: top-level session → role subagent.

Cost: the orchestrator's instructions (a few hundred lines) live in the top-level session's context for each turn — see "Context window impact" below.

## Why the initializer is a slash command (and the indexer is a subagent)

`/ns-init` (`commands/ns-init.md`) is a thin orchestrator that dispatches the `indexer` role subagent and verifies its outputs. The split mirrors the rest of the pipeline:

- The slash command runs at the top level so it can use `AskUserQuestion` (for the Refresh / Skip / Show summary prompt when intel already exists) and `Agent` (to dispatch the indexer).
- The indexer is a one-shot subagent. It scans the repo and writes four markdown files under `.northstar/intel/`. Putting the scan in a subagent keeps the slash command's context bounded — the top-level session never sees the raw manifest dumps, lint configs, or directory listings that the indexer pages through. Same files-as-IPC contract as every other role.
- `/ns-init` enforces output verification the same way `/ns` does: each of the four intel files must exist, be non-empty, and contain its required H2 sentinel section. On failure it writes a `from: orchestrator` blocker and pauses for the user.

The precursor gate is enforced by `/ns`, `/northstar`, and `/ns-discover`. The gate runs at INIT only for `/ns` (a mid-run intel deletion does not break an in-flight run) and at every invocation for `/ns-discover` (which produces a one-shot deliverable).

## Why the discoverer is also a slash command

`/ns-discover` (`commands/ns-discover.md`) is the upstream companion to `/ns`: it interviews the user about their vision and emits a Northstar-format plan file. It is a slash command, not a subagent, for the same platform reason as the orchestrator — and one additional one specific to its role:

- Like the orchestrator, the discoverer needs `AskUserQuestion`, which is a top-level-session capability. A subagent could call it, but the multi-turn nature of an interview (vision capture → scope confirmation → per-Part deep-dive, with redraft loops) requires the top-level session to hold context across turns. Subagents are one-shot.
- The discoverer does not dispatch any role subagents. It reads files (existing CLAUDE.md, README, repo layout) for grounding, asks structured questions, and writes a single markdown file. The output is consumed by `/ns` in a later session.
- The discoverer and the orchestrator are intentionally decoupled. The discoverer never writes to `.northstar/`. Its only output is the plan file at the user's chosen path. This keeps the two commands composable: you can run `/ns-discover` to produce a plan, edit it by hand, then hand it to `/ns` — or skip `/ns-discover` entirely and write the plan yourself.

## Context window impact

The orchestrator prompt is ~600 lines (10–15K tokens) and is injected into the top-level session on every `/ns` invocation. Beyond that, what enters the top-level context per Part is:

- One short narration sentence per subagent dispatch (~5 per Part).
- One short narration sentence per subagent return (~5 per Part).
- One AskUserQuestion per Part-completion checkpoint, plus any blocker-resolution exchanges (typically 0–1 per Part).
- The list of files changed (≤20 paths per Part typically).

What does NOT enter the top-level context:
- Subagent prompts.
- Subagent output bodies (research.md, plan.md, execution.md, review.md, audit.md). These live on disk under `.northstar/parts/<id>/` and the orchestrator reads them only when extracting structured fields (verdict, file list) — even then, only the relevant lines, not full file contents.
- Diff patches.

A 50-Part run accumulates roughly 5–10K tokens of narration plus the recurring ~15K orchestrator prompt — well within Claude Code's auto-compaction threshold. The trade-off relative to the original "orchestrator as subagent" idea: that design would have isolated even the narration into a separate context, so the top-level session would have seen only the final summary. With the slash-command-orchestrator design, you see the full per-Part narration in your session, which is actually useful for situational awareness — and the heavy artifact bodies still don't enter your context.

`.northstar/STATUS.md` is regenerated from state every tick. It's the human-readable view, never read back by the orchestrator.

Each Part has its own subdirectory of artifacts. Retries do not delete prior artifacts — they suffix the new attempt with `-attempt-N` and the old ones with `.orig.md` (on `retry` command) or just append (within normal retry loops). The full history is preserved for inspection.

## The plan-SHA invariant

INIT records `plan_sha256` of the plan file. On every subsequent invocation, the orchestrator re-hashes the plan and compares. If they differ, it pauses and asks: re-parse (which may invalidate in-flight Parts) or continue with the cached structure.

This guards against the common mistake of editing the plan mid-run and assuming the new edit is reflected. It also lets you confidently edit Parts that haven't started yet — answer "re-parse" and any Parts in `pending` status get their new bodies; in-flight Parts are flagged as potentially stale.

## Tool surface

The orchestrator has `Bash` access for three things:
1. SHA-256 the plan file.
2. Compute diffs (`git diff`) to pass to the verifier.
3. Run `git add` and `git commit` only when the user explicitly chose "Commit first" at a Part-completion prompt.

It does NOT use Bash for arbitrary code execution. It does NOT deploy. It does NOT push.

## Boundary with the user

Northstar talks to the user in exactly these moments:

| Trigger | Mechanism |
|---|---|
| INIT completed, ready to start | AskUserQuestion: start Part 1? |
| Planner produced output (interactive mode) | AskUserQuestion: approve plan? |
| Subagent flagged a blocker | AskUserQuestion: pick a resolution option |
| Reviewer/auditor exceeded retry budget | AskUserQuestion: skip / abort / fix manually |
| Part completed (interactive mode) | AskUserQuestion: continue / pause / commit first |
| Run-to safety cap (20 Parts unattended) | AskUserQuestion: continue / pause |
| Run-to target reached | AskUserQuestion: continue interactively? |
| All Parts done | AskUserQuestion: summary / abort / done |
| Plan SHA drift | AskUserQuestion: re-parse / continue cached |
| Any narrated update | One short sentence as plain text, no question |

The orchestrator never silently advances past a user-facing checkpoint. Every checkpoint is a real AskUserQuestion, not a yes/no prompt buried in narration.

## What Northstar is not

- Not a build system. It runs whatever commands the plan and research specify.
- Not a CI runner. It executes locally, in Claude Code, in your shell.
- Not a project manager. The plan file is the source of truth for what work exists; Northstar just walks it.
- Not opinionated about your stack. The scout discovers; the rest of the pipeline consumes what it found.
