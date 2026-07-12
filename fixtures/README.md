# Fixtures

Plan files used to exercise Suhail end-to-end. Each fixture is intentionally small and innocuous (writes only to temporary marker files in the working directory) so it can be run repeatedly.

Run a fixture with:

```
/su fixtures/<fixture-name>.md
```

After the run, clean up:

```powershell
/su-abort
.\scripts\suhail-clean.ps1
# (POSIX: ./scripts/suhail-clean.sh)
```

Or manually:

```powershell
Remove-Item -Recurse -Force .suhail
Remove-Item -Force .suhail-*.txt -ErrorAction SilentlyContinue
# (POSIX: rm -rf .suhail && rm -f .suhail-*.txt)
```

## Fixtures

### `test_plan.md` — happy-path smoke test

Three Parts across two dependency levels. Exercises the full pipeline: level scouting → master-plan approval → su-executer → su-verifier, plus the external-dependency checkpoint (Part 2) and a trivial Part (Part 3) that skips su-scout via a synthetic brief — the verifier still runs on its non-empty diff. Expected verdicts `clean`. Creates `.suhail-smoketest.txt` and `.suhail-smoketest-2.txt`.

This is the canonical post-install smoke test. If this fixture runs to completion with no blockers, the pipeline is wired correctly.

### `multi_part_deps.md` — dependency ordering

Three Parts with declared dependencies (a chain, so each Part is its own level). Tests that:
- Suhail parses `**Depends on:** Part N` correctly.
- Parts execute in dependency order (Part 1 before Part 2 before Part 3, regardless of numeric order vs. dep order).
- After each level, the orchestrator pauses with the level checkpoint (Continue / Pause / Run to end / Abort).
- The status table in STATUS.md shows the expected progression.

### `blocker_research.md` — blocker protocol

A Part that references a deliberately nonexistent file. Tests that:
- The su-scout detects the missing reference and writes `blocker.md` instead of inventing.
- The orchestrator surfaces the blocker via AskUserQuestion with the options the su-scout provided.
- After the user resolves the blocker, the su-scout resumes and the pipeline completes.

This fixture cannot be fully automated. By design, it requires a human (you) to answer the blocker question. Choose any option to see the blocker-resolution flow.

### `discover_sample_plan.md` — example `/su-discover` output

**Not a runnable fixture.** A representative plan file showing what `/su-discover` produces after a successful interview. Use it to sanity-check the discovery command's output shape, or as a learning-by-example reference for the plan-format contract. Do not pass it to `/su` — the Parts reference paths that don't exist in this repo.

### `parallel-verifier-plan.md` — parallel su-verifier dispatch

Three-Part plan that exercises parallel su-verifier dispatch. Part 1 (level 0) runs first: su-scout, su-executer, and su-verifier execute in order. Parts 2 and 3 (both level 1, both depending on Part 1) execute serially as su-executers; then both su-verifiers fire in parallel in the same assistant turn and both return `clean`. Expected artifacts:

- `.suhail-pv-smoketest-base.txt` — created by Part 1.
- `.suhail-pv-smoketest-a.txt` — created by Part 2.
- `.suhail-pv-smoketest-b.txt` — created by Part 3.
- `.suhail/STATUS.md` shows all three Parts as `completed`.

### `skip_flow.md` — /su-skip flow

Two-Part plan that exercises the `/su-skip` command. Part 1 runs normally and creates `.suhail-skip-1.txt`. The contributor then invokes `/su-skip` at the level checkpoint to skip Part 2 (since Part 1 is already terminal, `/su-skip` targets the next eligible Part). Tests that:
- The orchestrator marks the skipped Part as `skipped` in `STATUS.md` without invoking the su-executer.
- The skipped Part's marker file (`.suhail-skip-2.txt`) is never created.
- The run completes normally after the skip.

**Requires a manual step:** at the level checkpoint after Part 1 completes, type `/su-skip` instead of choosing Continue.

## Adding a new fixture

1. Create `fixtures/<name>.md` matching the plan-format contract (see `docs/plan-format.md`).
2. Keep effects local — write to a `.suhail-<name>-*.txt` style file in the working directory, nothing else.
3. Document the expected behavior at the top of the fixture file.
4. Add a section to this README.
5. Mention the fixture in `CONTRIBUTING.md` if it's a release gate.
