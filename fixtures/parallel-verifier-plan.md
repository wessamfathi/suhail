# Suhail Parallel-Verifier Smoke Test

This plan exercises parallel su-verifier dispatch. Running it with `/su fixtures/parallel-verifier-plan.md` should demonstrate the following sequence:

1. Part 1 (level 0) executes first: su-scout, su-executer, su-verifier in order.
2. Part 2 and Part 3 (both level 1, both depending on Part 1) execute serially as executers.
3. After both level-1 Parts complete execution, both verifiers fire in parallel in the same assistant turn.
4. Both verifiers return `clean`. The run completes.

Expected artifacts:
- `.suhail-pv-smoketest-base.txt` — created by Part 1.
- `.suhail-pv-smoketest-a.txt` — created by Part 2.
- `.suhail-pv-smoketest-b.txt` — created by Part 3.
- `.suhail/STATUS.md` showing all three Parts as `completed`.

After verifying, clean up:
- Delete the three `.suhail-pv-smoketest-*.txt` files.
- Delete `.suhail/` (or `/su-abort` then delete it).

## Parallel Verifier

### Part 1 — Create base marker file

Create a file at `.suhail-pv-smoketest-base.txt` (in the current working directory) containing the single line `pv base ok`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** (none)

**Verification:**
- Manual: open `.suhail-pv-smoketest-base.txt` and confirm contents.
- Programmatic: the file's contents equal `pv base ok\n`.

### Part 2 — Create branch-A marker file

Create a file at `.suhail-pv-smoketest-a.txt` (in the current working directory) containing the single line `pv branch-a ok`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** Part 1

**Verification:**
- Manual: open `.suhail-pv-smoketest-a.txt` and confirm contents.
- Programmatic: the file's contents equal `pv branch-a ok\n`.

### Part 3 — Create branch-B marker file

Create a file at `.suhail-pv-smoketest-b.txt` (in the current working directory) containing the single line `pv branch-b ok`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** Part 1

**Verification:**
- Manual: open `.suhail-pv-smoketest-b.txt` and confirm contents.
- Programmatic: the file's contents equal `pv branch-b ok\n`.
