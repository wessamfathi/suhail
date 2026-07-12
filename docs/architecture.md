# Architecture

Suhail is a thin coordinator over three specialized roles. This document covers the design choices behind the structure, the data flow, and the reasoning behind the constraints.

## The four roles

| Role | Tools | Model | Output |
|---|---|---|---|
| **su-indexer** | Read, Write, Glob, Grep, Bash | sonnet | `.suhail/intel/{stack,layout,conventions,modules}.md` — project-wide baseline cached once per project by `/su-init` |
| **su-scout** | Read, Write, Glob, Grep | sonnet | `brief.md` — discovered stack conventions, files to touch, reusable helpers, gotchas, domain risks, and ordered step list |
| **su-executer** | Read, Edit, Write, Glob, Grep, Bash | sonnet | `execution.md` — file changes, command results, manual follow-ups |
| **su-verifier** | Read, Write, Glob, Grep, Bash | haiku (`claude-haiku-4-5-20251001`) | `review.md` + `audit.md` — two-pass verdict and findings (review pass: correctness, regressions, convention drift; audit pass: security and compliance) |
| **su-discover-scout** | Read, Glob, Grep | haiku (`claude-haiku-4-5-20251001`) | Structured context summary returned as response (no disk write) — Phase 0 grounding for `/su-discover`. Dispatched exclusively by `/su-discover`, not by the orchestrator. |
| **su-discover-planner** | Read, Write | sonnet | `.suhail/plans/<slug>.md` — Suhail-format plan file. Phase 5 plan-writing for `/su-discover`. Dispatched exclusively by `/su-discover`, not by the orchestrator. |

Plus the **orchestrator** (`/su`) itself: opus, has access to Agent + AskUserQuestion + state I/O, dispatches the roles in sequence. The **su-indexer** is dispatched only by `/su-init`, not by the orchestrator — it runs once per project as a precursor.

## Pipeline shape

```
(once per project)
  /su-init → su-indexer → .suhail/intel/{stack,layout,conventions,modules}.md

(per Part, inside /su)
  su-scout → (user approval) → su-executer → su-verifier → completed → (user approval) → next Part
                                   ▲               │
                                   │               │ findings include [blocker]
                                   └───────────────┘
                                   up to max_retries (default 3)
```

The intel cache is the only project-wide artifact. Per-Part artifacts live under `.suhail/parts/<id>/`. The su-scout reads the intel cache as step 0 of its process so it does not re-derive stack, layout, conventions, or module structure on every Part.

The su-verifier runs two sequential passes on every Part: a review pass (correctness, regressions, convention drift) producing `review.md`, then an audit pass (security and compliance) producing `audit.md`. If either pass finds `blocker`-severity issues, the su-verifier triggers a re-dispatch of the su-executer. This serializes feedback so the su-executer addresses correctness before security.

## Why files-as-IPC

Every subagent communicates with the orchestrator and with subsequent subagents through markdown files in `.suhail/parts/<id>/`. The orchestrator passes paths in prompts, never artifact bodies.

Trade-off: each subagent does a small amount of file I/O it could have avoided. In exchange:

- The orchestrator's own context stays bounded regardless of plan size or artifact size. Without this, walking a 50-Part plan would blow out Suhail's context within a few Parts.
- Artifacts are inspectable. A user reviewing a run can read `brief.md` and form their own opinion before approving the plan. Same for every later stage.
- Subagents are stateless. Each invocation can read its inputs from disk, run, write outputs, and exit. No long-lived agents, no in-memory state to corrupt.
- Re-running a stage is trivial. The orchestrator's `retry` command renames the existing artifacts to `*.orig.md` and starts fresh.

## Why one Part per tick

The orchestrator advances state by exactly one logical step per invocation (one Part end-to-end in interactive mode). When the Part finishes, it ends the turn with an AskUserQuestion. The user explicitly chooses to continue.

This is the system's most important property. The user requested it explicitly: every Part is a checkpoint. In interactive mode there is no way to advance past a Part without the user authorizing.

`run-to <part-id>` is the explicit escape hatch for unattended runs. It bypasses per-Part pauses AND su-scout-approval, walks Parts until it hits the named target, and then reverts to interactive mode. A 20-Part safety cap forces an interactive checkpoint even mid-target, so runs can't go arbitrarily long unattended.

## Why the su-verifier uses two passes

The su-verifier runs a review pass followed by an audit pass within a single agent invocation. The passes are sequential — the audit pass runs only after the review pass is clean — so the su-executer addresses correctness before security concerns.

- The review pass catches: missing planned steps, broken patterns, missed reuse opportunities, regressions outside the planned files, type/null safety, performance smells.
- The audit pass catches: missing auth checks, injection, secrets in the diff, missing input validation, deep-link host validation.

Many bugs are correctness AND security issues (e.g. a missing auth check is both). Both passes will catch them; the su-verifier reports findings from both in its output artifacts (`review.md` and `audit.md`).

## Why the domain-hints channel

The su-verifier's audit pass is intentionally generic — language-agnostic checklist, no project knowledge. The su-scout writes a `Domain risks worth flagging to auditor` section in `brief.md` when the codebase implies specific concerns (e.g. "this Part touches AI-generated content; verify provenance is stored", or "this Part adds a new RPC; ensure RLS-equivalent policy is set").

This is the **only** channel by which project-specific risk reaches the su-verifier's audit pass. The su-verifier reads that section and folds it into its checklist. If the su-scout writes nothing there, the audit pass runs purely on its generic checks.

This design means: to use Suhail in a new domain, you don't extend the su-verifier's prompt — you trust the su-scout to discover and surface what matters. Domain knowledge flows through runtime artifacts, not hardcoded prompt edits.

## State management

The orchestrator owns `.suhail/state.json` exclusively. It always writes the full file from its in-memory representation; never partial-updates. The schema is documented in `commands/su.md`.

State writes and STATUS.md rendering are delegated to `suhail-write` (see `## Orchestrator IO scripts` below). The orchestrator pipes the full state JSON to the script on stdin and treats a non-zero exit as a hard blocker.

## Orchestrator IO scripts

Two shell scripts (`suhail-read.{ps1,sh}` and `suhail-write.{ps1,sh}`) handle the mechanical I/O operations that would otherwise require the orchestrator to manage file handles, atomic writes, and template rendering inline. Both pairs ship in the plugin's `scripts/` directory.

At runtime the orchestrator resolves the scripts directory using a four-step lookup before the first invocation: (1) `${CLAUDE_PLUGIN_ROOT}/scripts/` (plugin install — the token is substituted inline when plugin-installed, and left literal otherwise so it falls through); (2) `./.claude/commands/scripts/` (manual project copy); (3) `$CLAUDE_CONFIG_DIR/commands/scripts/` if `CLAUDE_CONFIG_DIR` is set, otherwise `~/.claude/commands/scripts/` (manual user copy); (4) `./scripts/` as a dev-repo fallback for running `/su` directly inside the Suhail source repo. The authoritative definition of this lookup is in the `## Script-path resolution` section of `commands/su.md`.

**`suhail-read`** reads a part directory (`.suhail/parts/<id>/`) and returns a structured JSON summary of the artifacts present — brief.md, execution.md, review.md, audit.md, blocker.md. The orchestrator calls it after subagent dispatch to extract verdict fields and file lists without reading full artifact bodies into its own context.

**`suhail-write`** accepts the full state JSON on stdin, writes `state.json` atomically (write to a temp file, then rename), and renders `STATUS.md` from the state fields — including `tool_version`, which it reads from `state.tool_version` at runtime. No hardcoded version string lives in the script; bumping `tool_version` in the state schema in `commands/su.md` is sufficient for `STATUS.md` to reflect the new version automatically.

**Why scripts, not agents:** both operations are purely mechanical — JSON field extraction, string substitution, atomic file write. No reasoning or judgment is involved. Using an agent dispatch for these tasks would consume a full subagent context slot and incur LLM latency for a deterministic transform. Scripts also execute synchronously and return a clear exit code, letting the orchestrator treat a non-zero exit as an immediate hard blocker without a dispatch-verify cycle. See `docs/decisions.md` for the full rationale and the alternatives considered.

The script interface is documented in the `## Script contracts` section of `commands/su.md`.

## Why the orchestrator lives in the slash command, not as a subagent

The orchestrator's logic is in `commands/su.md` (the slash command body) rather than `agents/suhail.md` (a subagent, removed in v0.7.2). The reason is a Claude Code platform constraint: **subagents invoked via the Agent tool cannot themselves spawn further subagents.** Only the top-level session can dispatch subagents. If the orchestrator were a subagent, it would have no way to call the su-scout / su-executer / su-verifier that it coordinates.

By putting the orchestrator into the slash command, invoking `/su` makes the top-level session take on the orchestrator role for the turn. The top-level session does have access to the Agent tool and can dispatch the role subagents (su-scout, su-executer, su-verifier), which run in isolated contexts. The pipeline tree is exactly two levels deep: top-level session → role subagent.

Cost: the orchestrator's instructions (a few hundred lines) live in the top-level session's context for each turn — see "Context window impact" below.

## Why the initializer is a slash command (and the su-indexer is a subagent)

`/su-init` (`commands/su-init.md`) is a thin orchestrator that dispatches the `su-indexer` role subagent and verifies its outputs. The split mirrors the rest of the pipeline:

- The slash command runs at the top level so it can use `AskUserQuestion` (for the Refresh / Skip / Show summary prompt when intel already exists) and `Agent` (to dispatch the su-indexer).
- The su-indexer is a one-shot subagent. It scans the repo and writes four markdown files under `.suhail/intel/`. Putting the scan in a subagent keeps the slash command's context bounded — the top-level session never sees the raw manifest dumps, lint configs, or directory listings that the su-indexer pages through. Same files-as-IPC contract as every other role.
- `/su-init` enforces output verification the same way `/su` does: each of the four intel files must exist, be non-empty, and contain its required H2 sentinel section. On failure it writes a `from: orchestrator` blocker and pauses for the user.

The precursor gate is enforced by `/su` and `/su-discover`. The gate runs at INIT only for `/su` (a mid-run intel deletion does not break an in-flight run) and at every invocation for `/su-discover` (which produces a one-shot deliverable). The precursor gate previously also applied to `/suhail`, which was removed in v0.7.2.

## Why the discoverer is also a slash command

`/su-discover` (`commands/su-discover.md`) is the upstream companion to `/su`: it interviews the user about their vision and emits a Suhail-format plan file. It is a slash command, not a subagent, for the same platform reason as the orchestrator — and one additional one specific to its role:

- Like the orchestrator, the discoverer needs `AskUserQuestion`, which is a top-level-session capability. The multi-turn nature of an interview (vision capture → scope confirmation → per-Part deep-dive, with redraft loops) requires the top-level session to hold context across turns. Subagents are one-shot and cannot bridge `AskUserQuestion` round-trips.

As of v0.8.0, `/su-discover` operates as a three-piece split:

- **Phase 0 (silent grounding)** delegates to `su-discover-scout` (`agents/su-discover-scout.md`): read-only, one-shot, uses model `claude-haiku-4-5-20251001` (haiku). It scans the repo (CLAUDE.md, README, manifests, directory tree) and returns a structured context summary as its response — no disk write. Appropriate here because the summary is transient context the slash command needs for interview grounding, not an artifact the user needs to inspect or retry. Keeping the scan in a subagent also separates the file-scan context from the interview session's context.
- **Phases 1–4 (multi-turn interview)** remain in the slash command itself. The command holds structured answers in memory across `AskUserQuestion` turns and builds the answers file at `.suhail/discover/<slug>.answers.md` once the interview concludes. This answers file is the IPC artifact between the command and the next phase — same files-as-IPC contract as the rest of the pipeline.
- **Phase 5 (plan-writing)** delegates to `su-discover-planner` (`agents/su-discover-planner.md`): write-only, one-shot, sonnet. It reads the answers file and writes a Suhail-format plan to `.suhail/plans/<slug>.md`. Putting plan-writing in a subagent keeps the slash command's context bounded and makes the plan-writing step independently retryable.

The discoverer and the orchestrator are intentionally decoupled. Its primary output is the plan file at the user's chosen path — this keeps the two commands composable: you can run `/su-discover` to produce a plan, edit it by hand, then hand it to `/su` — or skip `/su-discover` entirely and write the plan yourself.

## Context window impact

The orchestrator prompt is ~600 lines (10–15K tokens) and is injected into the top-level session on every `/su` invocation. Beyond that, what enters the top-level context per Part is:

- One short narration sentence per subagent dispatch (~5 per Part).
- One short narration sentence per subagent return (~5 per Part).
- One AskUserQuestion per Part-completion checkpoint, plus any blocker-resolution exchanges (typically 0–1 per Part).
- The list of files changed (≤20 paths per Part typically).

What does NOT enter the top-level context:
- Subagent prompts.
- Subagent output bodies (brief.md, execution.md, review.md, audit.md). These live on disk under `.suhail/parts/<id>/` and the orchestrator reads them only when extracting structured fields (verdict, file list) — even then, only the relevant lines, not full file contents.
- Diff patches.

A 50-Part run accumulates roughly 5–10K tokens of narration plus the recurring ~15K orchestrator prompt — well within Claude Code's auto-compaction threshold. The trade-off relative to the original "orchestrator as subagent" idea: that design would have isolated even the narration into a separate context, so the top-level session would have seen only the final summary. With the slash-command-orchestrator design, you see the full per-Part narration in your session, which is actually useful for situational awareness — and the heavy artifact bodies still don't enter your context.

`.suhail/STATUS.md` is regenerated from state every tick by `suhail-write` (see `## Orchestrator IO scripts`). It's the human-readable view, never read back by the orchestrator.

Each Part has its own subdirectory of artifacts. Retries do not delete prior artifacts — they suffix the new attempt with `-attempt-N` and the old ones with `.orig.md` (on `retry` command) or just append (within normal retry loops). The full history is preserved for inspection.

## The plan-SHA invariant

INIT records `plan_sha256` of the plan file. On every subsequent invocation, the orchestrator re-hashes the plan and compares. If they differ, it pauses and asks: re-parse (which may invalidate in-flight Parts) or continue with the cached structure.

This guards against the common mistake of editing the plan mid-run and assuming the new edit is reflected. It also lets you confidently edit Parts that haven't started yet — answer "re-parse" and any Parts in `pending` status get their new bodies; in-flight Parts are flagged as potentially stale.

## Tool surface

The orchestrator has `Bash` access for three things:
1. SHA-256 the plan file.
2. Compute diffs (`git diff`) to pass to the su-verifier.
3. Run `git add` and `git commit` to create one atomic commit per Part when a Part is verified clean (on by default; disabled per run with the `no-commit` argument), and on demand when the user chooses "Commit first" at a Part-completion prompt. Only the Part's own changed files are staged.

It does NOT use Bash for arbitrary code execution. It does NOT deploy. It does NOT push, amend, or force-push.

## Boundary with the user

Suhail talks to the user in exactly these moments:

| Trigger | Mechanism |
|---|---|
| INIT completed, ready to start | AskUserQuestion: start Part 1? |
| Scout produced brief (interactive mode) | AskUserQuestion: approve plan? |
| Subagent flagged a blocker | AskUserQuestion: pick a resolution option |
| Verifier exceeded retry budget | AskUserQuestion: skip / abort / fix manually |
| Part completed (interactive mode) | AskUserQuestion: continue / pause / commit first |
| Run-to safety cap (20 Parts unattended) | AskUserQuestion: continue / pause |
| Run-to target reached | AskUserQuestion: continue interactively? |
| All Parts done | AskUserQuestion: summary / abort / done |
| Plan SHA drift | AskUserQuestion: re-parse / continue cached |
| Any narrated update | One short sentence as plain text, no question |

The orchestrator never silently advances past a user-facing checkpoint. Every checkpoint is a real AskUserQuestion, not a yes/no prompt buried in narration.

## What Suhail is not

- Not a build system. It runs whatever commands the plan and research specify.
- Not a CI runner. It executes locally, in Claude Code, in your shell.
- Not a project manager. The plan file is the source of truth for what work exists; Suhail just walks it.
- Not opinionated about your stack. The scout discovers; the rest of the pipeline consumes what it found.
