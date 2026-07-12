<!-- One logical change per PR. What does this change, and why? -->

## Checklist

- [ ] `CHANGELOG.md` updated under `## [Unreleased]` (one line).
- [ ] `./tests/run-all.sh` passes; behavior changes were also walked through the relevant `fixtures/*.md` in Claude Code.
- [ ] If the plan format or state machine changed: `docs/plan-format.md` + the parser in `commands/su.md` + both `scripts/suhail-tick.*` updated together, with new harness cases.
