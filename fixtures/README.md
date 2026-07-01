# Fixtures

Plan files used to exercise Northstar end-to-end. Each fixture is intentionally small and innocuous (writes only to temporary marker files in the working directory) so it can be run repeatedly.

Run a fixture with:

```
/ns fixtures/<fixture-name>.md
```

After the run, clean up:

```powershell
/ns-abort
.\scripts\northstar-clean.ps1
# (POSIX: ./scripts/northstar-clean.sh)
```

Or manually:

```powershell
Remove-Item -Recurse -Force .northstar
Remove-Item -Force .northstar-*.txt -ErrorAction SilentlyContinue
# (POSIX: rm -rf .northstar && rm -f .northstar-*.txt)
```

## Fixtures

### `test_plan.md` — happy-path smoke test

Three Parts. Exercises the full pipeline: ns-scout → ns-executer → ns-verifier, plus the external-dependency checkpoint (Part 2) and a trivial Part that skips ns-scout/ns-verifier (Part 3). Expected verdicts `clean`. Creates `.northstar-smoketest.txt` and `.northstar-smoketest-2.txt`.

This is the canonical post-install smoke test. If this fixture runs to completion with no blockers, the pipeline is wired correctly.

### `multi_part_deps.md` — dependency ordering

Three Parts with declared dependencies. Tests that:
- Northstar parses `**Depends on:** Part N` correctly.
- Parts execute in dependency order (Part 1 before Part 2 before Part 3, regardless of numeric order vs. dep order).
- After each Part, the orchestrator pauses with a Continue/Pause prompt.
- The status table in STATUS.md shows the expected progression.

### `blocker_research.md` — blocker protocol

A Part that references a deliberately nonexistent file. Tests that:
- The ns-scout detects the missing reference and writes `blocker.md` instead of inventing.
- The orchestrator surfaces the blocker via AskUserQuestion with the options the ns-scout provided.
- After the user resolves the blocker, the ns-scout resumes and the pipeline completes.

This fixture cannot be fully automated — by design, it requires a human (you) to answer the blocker question. Choose any option to see the blocker-resolution flow.

### `discover_sample_plan.md` — example `/ns-discover` output

**Not a runnable fixture.** A representative plan file showing what `/ns-discover` produces after a successful interview. Use it to sanity-check the discovery command's output shape, or as a learning-by-example reference for the plan-format contract. Do not pass it to `/ns` — the Parts reference paths that don't exist in this repo.

### `parallel-verifier-plan.md` — parallel ns-verifier dispatch

Three-Part plan that exercises parallel ns-verifier dispatch. Part 1 (level 0) runs first — ns-scout, ns-executer, and ns-verifier execute in order. Parts 2 and 3 (both level 1, both depending on Part 1) execute serially as ns-executers; then both ns-verifiers fire in parallel in the same assistant turn and both return `clean`. Expected artifacts:

- `.northstar-pv-smoketest-base.txt` — created by Part 1.
- `.northstar-pv-smoketest-a.txt` — created by Part 2.
- `.northstar-pv-smoketest-b.txt` — created by Part 3.
- `.northstar/STATUS.md` shows all three Parts as `done`.

### `skip_flow.md` — /ns-skip flow

Two-Part plan that exercises the `/ns-skip` command. Part 1 runs normally and creates `.northstar-skip-1.txt`. The contributor then invokes `/ns-skip` at the orchestrator's Continue prompt to skip Part 2. Tests that:
- The orchestrator marks the skipped Part as `skipped` in `STATUS.md` without invoking the ns-executer.
- The skipped Part's marker file (`.northstar-skip-2.txt`) is never created.
- The run completes normally after the skip.

**Requires a manual step:** after Part 1 completes, type `/ns-skip` instead of confirming Continue.

## Adding a new fixture

1. Create `fixtures/<name>.md` matching the plan-format contract (see `docs/plan-format.md`).
2. Keep effects local — write to a `.northstar-<name>-*.txt` style file in the working directory, nothing else.
3. Document the expected behavior at the top of the fixture file.
4. Add a section to this README.
5. Mention the fixture in `CONTRIBUTING.md` if it's a release gate.
