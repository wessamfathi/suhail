# Fixtures

Plan files used to exercise Northstar end-to-end. Each fixture is intentionally small and innocuous (writes only to temporary marker files in the working directory) so it can be run repeatedly.

Run a fixture with:

```
/ns fixtures/<fixture-name>.md
```

After the run, clean up:

```powershell
/ns abort
Remove-Item -Recurse -Force .northstar
Remove-Item -Force .northstar-smoketest*.txt -ErrorAction SilentlyContinue
Remove-Item -Force .northstar-deps-*.txt -ErrorAction SilentlyContinue
```

## Fixtures

### `test_plan.md` — happy-path smoke test

Single Part. Exercises the full pipeline: researcher → planner → executer → reviewer → security-auditor. Expected verdicts `clean`. Creates `.northstar-smoketest.txt`.

This is the canonical post-install smoke test. If this fixture runs to completion with no blockers, the pipeline is wired correctly.

### `multi_part_deps.md` — dependency ordering

Three Parts with declared dependencies. Tests that:
- Northstar parses `**Depends on:** Part N` correctly.
- Parts execute in dependency order (Part 1 before Part 2 before Part 3, regardless of numeric order vs. dep order).
- After each Part, the orchestrator pauses with a Continue/Pause prompt.
- The status table in STATUS.md shows the expected progression.

### `blocker_research.md` — blocker protocol

A Part that references a deliberately nonexistent file. Tests that:
- The researcher detects the missing reference and writes `blocker.md` instead of inventing.
- The orchestrator surfaces the blocker via AskUserQuestion with the options the researcher provided.
- After the user resolves the blocker, the researcher resumes and the pipeline completes.

This fixture cannot be fully automated — by design, it requires a human (you) to answer the blocker question. Choose any option to see the blocker-resolution flow.

### `discover_sample_plan.md` — example `/ns-discover` output

**Not a runnable fixture.** A representative plan file showing what `/ns-discover` produces after a successful interview. Use it to sanity-check the discovery command's output shape, or as a learning-by-example reference for the plan-format contract. Do not pass it to `/ns` — the Parts reference paths that don't exist in this repo.

## Adding a new fixture

1. Create `fixtures/<name>.md` matching the plan-format contract (see `docs/plan-format.md`).
2. Keep effects local — write to a `.northstar-<name>-*.txt` style file in the working directory, nothing else.
3. Document the expected behavior at the top of the fixture file.
4. Add a section to this README.
5. Mention the fixture in `CONTRIBUTING.md` if it's a release gate.
