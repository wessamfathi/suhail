---
description: Auto-detect the most recent plan and run it in autorun mode.
---

# /su-auto — Suhail auto-runner

You are running the most recent Suhail plan in autorun mode. If a plan path is supplied as `$ARGUMENTS`, use it directly. Otherwise scan `.suhail/plans/` for candidate plans and ask the user which one to run.

## On every invocation

### If `$ARGUMENTS` is non-empty

Treat `$ARGUMENTS` as the explicit plan path. Skip the auto-detection section entirely and jump to **Locating `su.md`** below, using `$ARGUMENTS` as `<plan-path>`.

### Auto-detection (only when `$ARGUMENTS` is empty)

1. Scan `.suhail/plans/` for files matching `*.md`, sorted by last-modified descending. If the directory does not exist, treat it as empty.
2. Branch on the number of results:
   - **None found** — end with: "No plans found in `.suhail/plans/` — run `/su-discover` to draft one or pass a plan path directly."
   - **One found** — present an AskUserQuestion:
     - Prompt: "Found one plan: `<filename>`. Run it in autorun mode?"
     - Options: "Yes", "Pick a different plan", "Cancel"
     - If **Yes**: proceed to **Locating `su.md`** with that plan's path.
     - If **Pick a different plan**: ask the user to type a path, then proceed to **Locating `su.md`** with the typed path.
     - If **Cancel**: end with: "Cancelled."
   - **Multiple found** — present an AskUserQuestion:
     - Prompt: "Select a plan to run in autorun mode:"
     - Options: the 3 most recent filenames (basenames), plus "Other (type a path)"
     - If a filename is selected: proceed to **Locating `su.md`** with the full path for that file.
     - If **Other (type a path)**: ask the user to type a path, then proceed to **Locating `su.md`** with the typed path.

## Locating `su.md`

Check these paths in order:

1. Plugin install: `${CLAUDE_PLUGIN_ROOT}/commands/su.md` — resolves only when installed as a Claude Code plugin (token substituted inline before this file is read); otherwise the token is left literal and the path will not exist, so it falls through.
2. The same directory as this command file (sibling).
   - Project install: `<repo>/.claude/commands/su.md`.
   - User install: `~/.claude/commands/su.md`.
3. If no path is found, end with: "Cannot locate `su.md` — reinstall Suhail."

Do not duplicate or summarize the orchestrator logic here. The canonical state machine lives in `su.md`.

## Execute

Once `su.md` is located:

1. Read `su.md` into memory.
2. Follow its instructions as if the user had typed `/su autorun <plan-path>`, where `<plan-path>` is the plan path resolved above.

Do NOT call `/su` as a slash command. Read the file content and follow it directly, the same way `/su-next` dispatches to the orchestrator.

## Don't

- Do not loop. Delegate all looping to the orchestrator inside `su.md`; this command's job is only to resolve the plan path and hand off.
- Do not mutate state directly. All state transitions belong to the orchestrator in `su.md`.
- Do not error on a missing `.suhail/plans/` directory — treat it as empty and follow the "none found" branch.
