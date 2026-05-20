---
description: Print the current Northstar run's status dashboard. Read-only — never advances state.
---

# /ns-status — Northstar status dashboard

You are printing the current Northstar run's status. This command takes no arguments. It reads `.northstar/STATUS.md` and emits it verbatim. It is strictly read-only: it never advances state, dispatches a subagent, or writes any file.

## On every invocation

1. **No active run.** Attempt to Read `.northstar/state.json`. If it does not exist, end with one sentence: "No active Northstar run found — run `/ns <plan-path>` to start one."
2. **Status not yet rendered.** If `.northstar/state.json` exists but `.northstar/STATUS.md` does not, end with one sentence: "A run exists but `STATUS.md` has not been rendered yet — run `/ns` to advance one tick and regenerate it."
3. **Emit.** Read `.northstar/STATUS.md` and emit its contents verbatim to the user. Do not summarize, reformat, or annotate. End the turn.

## Don't

- Do not advance state, dispatch any subagent, or write any file. This command is read-only.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not regenerate `STATUS.md` yourself — that is `northstar-write`'s job, triggered by `/ns`. If it is stale or missing, point the user at `/ns`.
- Do not echo `state.json` instead of `STATUS.md`. `STATUS.md` is the human-readable view.
