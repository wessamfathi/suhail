# Plan format

Northstar parses any markdown file matching this minimal contract. There is no required frontmatter, no YAML, no special section names — just a few conventions on headings and one optional dependency declaration.

## Required

### Parts

Each Part is an H3 heading of the form:

```
### Part <N> — <Title>
```

- `<N>` is a positive integer. It becomes the Part id as `part-<N>` (so `### Part 2 — Foo` → `part-2`).
- The separator is an **em-dash** (`—`, Unicode U+2014) with one space on each side. ASCII hyphen-minus (`-`) is **not** accepted; this disambiguates Part headings from arbitrary H3s that happen to use a hyphen.
- `<Title>` is everything after the em-dash to end of line. Used in STATUS.md and Northstar's prompts.

A plan with no `### Part N —` headings is invalid; INIT will produce an empty parts list and refuse to start.

## Optional

### Groups

Any H2 heading (`## ...`) before the first Part becomes a group label. Parts inherit the most recent H2 above them. Groups are purely cosmetic — they appear as a column in `STATUS.md` and have no execution effect.

Examples that work:
- `## Milestone M023` then several Parts → all show `M023` in the Group column.
- `## Phase 1 — Setup` then Parts → group is `Phase 1 — Setup`.
- No H2s at all → Group column is blank for every Part.

### Dependencies

A Part declares prerequisites by including a line that contains the phrase `Depends on` (case-insensitive). All forms below are accepted:

```
**Depends on:** Part 2, Part 4
**Depends on Part 2** and Part 4
Depends on Parts 2, 4, and 6
Depends on Part 2
```

**Parsing rule:** for each line containing `Depends on`, the orchestrator takes the substring from that phrase to the end of the line and collects every integer immediately preceded by the word `Part` or `Parts` (case-insensitive). The collected integers, deduplicated, form the Part's `depends_on` list.

This means dependencies are scoped to a single line. If you want to elaborate on the dependency, do it on the same line:

```
**Depends on Part 2** (suggests images via image-search) and Part 4 (controlled vocabulary).
```

Both `Part 2` and `Part 4` are captured.

If you put commentary on subsequent lines, those lines are not parsed for dependencies — only the line with `Depends on` is. This is intentional: it prevents accidental capture of `Part N` references in unrelated prose.

A Part is eligible for execution when all its `depends_on` entries are either `completed` or `skipped`. Parts without explicit dependencies are eligible immediately, in numeric order.

Cycles are not detected automatically at parse time — if you write a cycle, INIT will set `current_part_id` to the first Part with no listed dependencies (possibly none, in which case the run gets stuck). Don't write cycles.

### Verification

A `Verification` subheading or paragraph inside a Part is treated like any other body content — it's passed verbatim to the scout. The scout is expected to translate it into concrete commands the executer can run.

The downstream Northstar pipeline does not parse Verification content — it's a hint to the scout, not a directive to the orchestrator.

## Body content

A Part's body is the content from its H3 heading down to **whichever comes first**: the next `### Part N —` heading, the next H2 heading, or end of file. This means **plan-level trailing sections** (`## Critical files reference`, `## Verification`, `## Open questions`, an `## Appendix`, anything similar that comes after the final Part) are NOT absorbed into the last Part's brief. They are plan-level metadata and ignored by the orchestrator.

Anything inside a Part section that isn't the heading itself or a dependency declaration is the **brief**. It's handed verbatim to the scout. The scout is expected to read it and act on it — write the brief like you're handing a task to an engineer who has not read the rest of the plan.

The brief can include:
- Prose context (what + why).
- File paths to touch (the scout will read them).
- Reusable helpers to consider (the scout will confirm they exist).
- Code skeletons or migration SQL (the scout will reflect them in the step list).
- ASCII diagrams, tables, anything else markdown supports.

There is no upper bound on a Part's body size, but the scout will skim files rather than copy them — pointers to existing code are more efficient than re-quoting it.

## Example

```markdown
# My Big Migration

## Phase 1 — Database

### Part 1 — Add user_preferences table

Goal: a new table to store per-user feature toggles. Schema:

```sql
create table user_preferences (
  user_id uuid primary key references users(id),
  prefs jsonb not null default '{}'
);
```

**Depends on:** (none)

**Verification:**
- Run the migration locally.
- Insert a test row.
- Confirm RLS policy denies cross-user reads.

### Part 2 — Migrate existing settings

Backfill `user_preferences.prefs` from the legacy `users.settings` column. After the migration, `users.settings` is removed.

**Depends on:** Part 1

## Phase 2 — API

### Part 3 — Read endpoint

Expose `GET /me/preferences`. Depends on Part 1.
```

After INIT this parses to:

| id | group | title | depends_on |
|---|---|---|---|
| part-1 | Phase 1 — Database | Add user_preferences table | [] |
| part-2 | Phase 1 — Database | Migrate existing settings | [1] |
| part-3 | Phase 2 — API | Read endpoint | [1] |

Northstar will start with Part 1. Once it completes, both Part 2 and Part 3 become eligible (only Part 1 was their prerequisite); Northstar picks the lower number (Part 2) next.

## Things Northstar does NOT parse

- Tables — markdown tables in the body are content for the scout, not structured data.
- Frontmatter — any YAML/JSON frontmatter at the top of the file is ignored. (Reserved for future use.)
- H4+ headings — H4 and below are body content.
- Code fences — pass-through to subagents.
- HTML — pass-through.
- Mermaid diagrams — pass-through.
- Cross-Part links (`[Part 2](#part-2)`) — body content; not used for dependency inference.

## Compatibility with existing plan files

If you already have a plan file using a different separator (e.g. `### Part 1: Foo` with a colon, or `### Part 1 - Foo` with an ASCII hyphen), edit it once to use the em-dash form: `### Part 1 — Foo`. This is intentional — without a distinguishing separator, plain H3 headings would collide with the Part detector.

## Validation

To check whether a plan parses cleanly without starting a run, you can `/ns <plan-path>` then choose "Show parsed structure" at the INIT prompt, then `/ns abort`. This is a non-destructive way to validate.

A future release may add `/ns validate <plan-path>` as a dedicated read-only check.
