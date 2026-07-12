# Extending Suhail

Suhail ships with three role subagents (su-scout, su-executer, su-verifier) plus a slash-command orchestrator. Adding new roles is a matter of writing one markdown file and (usually) editing the orchestrator's state machine to dispatch it at the right phase.

The orchestrator itself lives in `commands/su.md` rather than as a subagent because Claude Code does not allow subagents to spawn further subagents. The top-level session plays the orchestrator role per turn. See `docs/architecture.md` for the full rationale.

## The contract a subagent must satisfy

Every role subagent in Suhail follows the same contract:

1. **Reads inputs by file path.** The orchestrator passes input paths in the prompt; the subagent uses Read.
2. **Writes a single output file at a known path.** The orchestrator passes the output path; the subagent uses Write.
3. **Signals blockers via `blocker.md`** in the part's directory, with frontmatter declaring `from`, `severity`, and `options`.
4. **Never coordinates directly with other subagents.** All coordination flows through the orchestrator.
5. **Frontmatter declares `name`, `description`, `tools`, `model`** per Claude Code's subagent format.

If your new role can't satisfy this contract, it doesn't belong in the Suhail pipeline — consider building it as a separate tool the user invokes manually.

## Adding a role: worked example

Suppose you want to add a **performance-auditor** role that runs after the su-verifier on Parts that touch hot paths.

### 1. Write the agent file

Create `agents/performance-auditor.md`:

```markdown
---
name: performance-auditor
description: Generic performance-focused diff review. Looks for unbounded loops over user data, missing pagination, sync I/O on render paths, missing memoization in hot components. Domain-specific hot paths are surfaced by the su-scout. Writes to .suhail/parts/<id>/perf.md.
tools: Read, Glob, Grep, Bash
model: sonnet
---

You are the performance-auditor role in the Suhail pipeline...

(Mirror the structure of agents/su-verifier.md: Input section, Process section, Output schema, Severity guidance, Don't section.)
```

Reuse the su-verifier template — same input shape (brief.md, diff path), same output shape (verdict + findings list), same retry semantics if you want it to re-dispatch the su-executer on blockers.

### 2. Update the orchestrator state machine

Edit `commands/su.md` to add a new phase between `verifying` and `completed`:

```
### perf-auditing

Identical shape to `verifying` with subagent_type="performance-auditor" and output path perf.md. Same retry semantics. On clean or concerns: advance to `completed`. Re-tick.
```

Update the status enum doc string to include the new phase.

### 3. Packaging

No packaging edit needed — the plugin bundles everything in `agents/*.md` (and `commands/`, `scripts/`) automatically.

### 4. Update STATUS.md generation

STATUS.md generation is now handled by `suhail-write.{ps1,sh}` (installed to `commands/scripts/`), not by an inline template in `commands/su.md`. If you want the new phase to appear in the STATUS dashboard (new column, new emoji, new row), edit the write scripts in their installed location. The scripts read `tool_version` from the state JSON at runtime — no hardcoded version string to keep in sync.

### 5. Bump the version

Bump `tool_version` in `commands/su.md` in two locations: the heading (`# /su — Suhail vX.Y.Z`) and the `tool_version` field inside the state schema block. The write scripts (`suhail-write.{ps1,sh}`, installed to `commands/scripts/` and resolved via the project-then-global lookup defined in `## Script-path resolution` in `commands/su.md`) read `tool_version` from the state JSON at runtime and require no separate version edit. Add a CHANGELOG entry.

## Skipping a role per-Part

Sometimes a Part doesn't need every role. For example, a Part that only edits documentation may not need the su-verifier's full audit pass.

The clean way to skip: have the role itself recognize when it has nothing to do and produce a `clean` verdict immediately. The su-verifier already does this (see its "When the diff is security-irrelevant" section in the audit pass). The cost is one subagent invocation that returns fast — usually a few seconds. Worth it because the rule stays uniform.

The alternative — having the orchestrator decide which roles to run per Part — adds branching complexity and a new decision point. Avoid unless the per-Part skip is very common.

## Removing a role

Don't.

The orchestrator's state machine references each role by name. Removing one means surgery on `commands/su.md` and the state machine doc, plus thinking about migration for in-flight runs that have artifacts from the removed role.

If you don't need a role on your particular project, the better path is to install Suhail then edit the orchestrator's state machine in `~/.claude/commands/su.md` locally to skip that role's phase. Don't fork.

## Replacing a role's implementation

The role contract is: same input shape, same output shape. You can totally rewrite the prompt body of `su-verifier.md` to match your team's house style, your specific tech stack, your specific concerns — as long as the output `Verdict` line still parses and findings still have `[severity]` tags, the orchestrator will work.

This is the recommended way to specialize Suhail without forking: keep the orchestrator generic, customize the role prompts locally.

## Per-language tweaks

Suhail discovers stack conventions at runtime via the su-scout. You generally don't need per-language Suhail variants.

If you find yourself wanting a TypeScript-flavored su-verifier that always nags about `any` types, the better path is:
1. Put the convention in your project's `CLAUDE.md` or `AGENTS.md`.
2. The su-scout will surface it in `brief.md` under "House conventions".
3. The generic su-verifier will enforce it.

That way the same Suhail install works for your TypeScript project AND your Python project AND your Rust project.

## When to fork

You should fork Suhail (rather than extend or replace prompts locally) when:

- The contract itself needs to change (e.g. you want subagents to pass structured JSON instead of markdown — a deep change to the IPC mechanism).
- You're adding a non-trivial number of roles (say, four or more) that constitute a fundamentally different pipeline shape.
- You want to integrate with external systems (issue trackers, CI, etc.) in a way that benefits from being maintained as a coherent product.

For everything smaller, edit local agent prompts.

## Contributing back

If your extension is generally useful (more roles, better STATUS.md formatting, better blocker resolution UX), please open a PR against the upstream repo. Suhail aims to stay opinionated and small, but the role roster is a natural extension point.
