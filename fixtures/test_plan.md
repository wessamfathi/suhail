# Suhail Self-Test

This plan is a no-op smoke test. Pointing Suhail at it should walk through su-scout → su-executer → su-verifier end to end, with no manual follow-ups.

Run after install with:

```
/su fixtures/test_plan.md
```

Expected outcome:
- `.suhail/state.json` and `.suhail/STATUS.md` created. Two dependency levels: Part 1 is level 0; Parts 2 and 3 (both depending on Part 1) form level 1 and are scouted together.
- Four artifacts under `.suhail/parts/part-1/` and `.suhail/parts/part-2/` (`brief.md`, `execution.md`, `review.md`, `audit.md`). Part 3 (trivial) skips su-scout — its `brief.md` is a synthetic inline brief — but the su-verifier still runs on its non-empty diff, so expect real `review.md`/`audit.md` under `.suhail/parts/part-3/` too.
- A new file `.suhail-smoketest.txt` in the working directory containing the single line `suhail smoke ok`.
- A new file `.suhail-smoketest-2.txt` in the working directory containing the single line `suhail smoke ok 2` — created only after the user confirms the external-dependency checkpoint.
- After level 1's scouting finishes (before the master plan approval), Suhail pauses and surfaces Part 2's ⚠ external-dependency line (the `SUHAIL_SMOKE_TOKEN` env-var reminder). This pause must fire even though no `run-to` flag is set.
- For the scouted Parts (1 and 2), `brief.md`'s `### Verification` section opens with a verbatim quote of the Part body's `**Verification:**` block. (Part 3's synthetic brief has no Verification section — expected.)
- Reviewer verdict `clean` and security-auditor verdict `clean` for all three Parts.
- After completion, Suhail shows the run-complete card and asks (Show summary / Done).

After verifying, you can:
- Delete `.suhail-smoketest.txt` and `.suhail-smoketest-2.txt`
- Delete `.suhail/` (or `/su-abort` then delete it)

## Smoke

### Part 1 — Create marker file (overwrite if exists)

Create a file at `.suhail-smoketest.txt` (in the current working directory) containing the single line `suhail smoke ok`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** (none)

**Verification:**
- Manual: open `.suhail-smoketest.txt` and confirm contents.
- Programmatic: the file's contents equal `suhail smoke ok\n`.

### Part 2 — Create second marker file after external action

Create a file at `.suhail-smoketest-2.txt` (in the current working directory) containing the single line `suhail smoke ok 2`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

This Part exists to exercise the orchestrator's external-dependency checkpoint: the su-scout must surface the manual action below as a ⚠ entry under `### External dependencies`, and the orchestrator must pause after the level's scouting to confirm with the user before any su-executer runs.

**Depends on:** Part 1

**External dependencies:**
- ⚠ Set an environment variable `SUHAIL_SMOKE_TOKEN` to any non-empty value in your shell before continuing. The su-executer does not actually read this variable; it exists purely to test the checkpoint flow.

**Verification:**
- Manual: open `.suhail-smoketest-2.txt` and confirm contents. Also confirm that the orchestrator paused after Part 2's su-scout finished and surfaced the ⚠ external-dependency line before asking to continue.
- Programmatic: the file's contents equal `suhail smoke ok 2\n`.

### Part 3 — Add a comment line to the smoke test file

Append the line `# trivial part ran` to `.suhail-smoketest.txt`. If the file does not exist, create it with just that line.

**Depends on:** Part 1

**Verification:**
- Manual: open `.suhail-smoketest.txt` and confirm the comment line is present.
