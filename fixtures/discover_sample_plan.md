# Sample plan emitted by `/ns-discover`

This file is **not a runnable Northstar fixture** — it is a representative output of `/ns-discover`, shown so you can see what a successful discovery interview produces. The plan describes a small, plausible feature (adding a `/health` endpoint to a hypothetical web service) and is formatted exactly the way `/ns` expects.

Use this file to:

- Sanity-check what `/ns-discover` is supposed to produce before you run it.
- Hand-edit a discovery output and learn the plan-format contract by example.
- Diff against your own discovery runs to spot drift.

Do **not** run it directly — there is no target project for it to execute against, and several Parts reference paths that don't exist in this repo. It's documentation by example.

For the actual contract see [`docs/plan-format.md`](../docs/plan-format.md).

---

# Add a `/health` endpoint and surface dependency status

## Vision

Operators currently have no quick way to confirm the service is up and that its downstream dependencies (Postgres, Redis, the upstream auth API) are reachable. Add a single HTTP `/health` endpoint that reports the service's own liveness plus a per-dependency status block, and wire it into the existing monitoring config so the on-call dashboard picks it up automatically.

## Phase 1 — Endpoint and dependency probes

### Part 1 — Add the `/health` route and a liveness probe

Register a new `GET /health` route on the existing HTTP router. The handler should return `200 OK` with a JSON body of the form `{ "status": "ok", "version": "<build-version>", "dependencies": { ... } }`. For this Part, the `dependencies` block can be empty `{}` — Part 2 fills it.

The route must be unauthenticated and exempt from the existing rate-limit middleware (operators behind firewalls poll it every few seconds).

**Depends on:** (none)

**Verification:**
- `curl localhost:<port>/health` returns `200` with the documented body shape.
- Existing test suite still passes.

### Part 2 — Per-dependency probes (Postgres, Redis, auth API)

Extend the `/health` handler from Part 1 to probe each declared dependency with a short timeout (250ms each) in parallel and report per-dependency `{ "status": "ok" | "degraded" | "down", "latency_ms": <int> }`.

If any dependency is `down`, the overall `status` field flips to `degraded` (not `down`) — the service itself is still up.

**Depends on:** Part 1

**Verification:**
- All three probes return `ok` against a normally-running stack.
- Simulating a downed Redis returns `degraded` overall with Redis marked `down`.
- The endpoint still responds within ~500ms even with one dependency timing out.

## Phase 2 — Operator surface

### Part 3 — Wire `/health` into the monitoring config

Add the new endpoint to the existing monitoring configuration so the on-call dashboard picks it up without manual setup. The exact path and format depend on what the project's monitoring stack already uses — the researcher should discover this from `monitoring/` or equivalent before the planner commits to a shape.

**Depends on:** Part 2

**Verification:**
- The dashboard shows a green tile for this service within one scrape interval after deploy.
- An induced dependency outage (e.g. blocking Redis) flips the tile to amber within one scrape interval.

## Critical files reference

- Existing HTTP router registration: the researcher should locate this — likely `src/server.<ext>` or a `routes/` directory.
- Existing monitoring config: `monitoring/` directory, format TBD.
- Existing dependency config: where Postgres / Redis / auth API URLs are read.

## Open questions

- Should the auth API probe use the auth API's own `/health`, or a cheap authenticated call? The discoverer left this to the researcher / planner.
- Is there an existing convention for status-string vocabulary (`ok` vs. `healthy` vs. `up`)? Researcher should match it.
