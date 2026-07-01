# Northstar Self-Test

This plan is a no-op smoke test. Pointing Northstar at it should walk through ns-scout → ns-executer → ns-verifier cleanly, end-to-end, with no manual follow-ups.

Run after install with:

```
/ns fixtures/test_plan.md
```

Expected outcome:
- `.northstar/state.json` and `.northstar/STATUS.md` created.
- Four artifacts under `.northstar/parts/part-1/` and `.northstar/parts/part-2/` (`brief.md`, `execution.md`, `review.md`, `audit.md`); Part 3 (trivial) skips ns-scout and ns-verifier — expect `brief.md`, `execution.md`, synthetic `review.md`/`audit.md` under `.northstar/parts/part-3/`.
- A new file `.northstar-smoketest.txt` in the working directory containing the single line `northstar smoke ok`.
- A new file `.northstar-smoketest-2.txt` in the working directory containing the single line `northstar smoke ok 2` — created only after the user confirms the Part 2 external-dependency checkpoint.
- After Part 2's ns-scout finishes, Northstar pauses and surfaces the ⚠ external-dependency line (the `NORTHSTAR_SMOKE_TOKEN` env-var reminder) before asking to continue. This pause must fire even though no `run-to` flag is set.
- Each Part's `brief.md` `### Verification` section opens with a verbatim quote of the Part body's `**Verification:**` block.
- Reviewer verdict `clean`. Security auditor verdict `clean` for both Parts.
- After completion, Northstar pauses and asks whether to continue (no further Parts exist; this is the run-complete prompt).

After verifying, you can:
- Delete `.northstar-smoketest.txt` and `.northstar-smoketest-2.txt`
- Delete `.northstar/` (or `/ns-abort` then delete it)

## Smoke

### Part 1 — Append marker line to a test file

Create a file at `.northstar-smoketest.txt` (in the current working directory) containing the single line `northstar smoke ok`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** (none)

**Verification:**
- Manual: open `.northstar-smoketest.txt` and confirm contents.
- Programmatic: the file's contents equal `northstar smoke ok\n`.

### Part 2 — Append second marker line after external action

Create a file at `.northstar-smoketest-2.txt` (in the current working directory) containing the single line `northstar smoke ok 2`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

This Part exists to exercise the orchestrator's external-dependency checkpoint: the ns-scout must surface the manual action below as a ⚠ entry under `## External dependencies`, and the orchestrator must pause after scouting to confirm with the user before the ns-executer runs.

**Depends on:** Part 1

**External dependencies:**
- ⚠ Set an environment variable `NORTHSTAR_SMOKE_TOKEN` to any non-empty value in your shell before continuing. The ns-executer does not actually read this variable; it exists purely to test the checkpoint flow.

**Verification:**
- Manual: open `.northstar-smoketest-2.txt` and confirm contents. Also confirm that the orchestrator paused after Part 2's ns-scout finished and surfaced the ⚠ external-dependency line before asking to continue.
- Programmatic: the file's contents equal `northstar smoke ok 2\n`.

### Part 3 — Add a comment line to the smoke test file

Append the line `# trivial part ran` to `.northstar-smoketest.txt`. If the file does not exist, create it with just that line.

**Depends on:** Part 1

**Verification:**
- Manual: open `.northstar-smoketest.txt` and confirm the comment line is present.
