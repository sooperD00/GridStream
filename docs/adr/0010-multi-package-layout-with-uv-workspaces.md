# ADR-0010: Multi-package layout with uv workspaces

**Status:** Accepted
**Date:** 2026-04-29
**Sprint:** 1 (Paved Road)

## Context

GridStream is a multi-service repository. Sprint 1 ships a stub service. Sprint 2 adds a producer, a consumer, and shared Pydantic/Avro models that both consume. The future-scope list contemplates a second reference service in a different domain to prove the paved road generalizes. Each of these has different runtime dependencies, different container builds, and (eventually) different release cadences.

The decision is how to organize *this* repository's Python packages internally. It is **not** a decision about how adopting teams structure their own repos — each adopting team has one service in one repo with one `pyproject.toml`, regardless of what GridStream does internally. That separation is worth naming because the temptation is to optimize this layout for "easier to teach in `paved-road.md`," and the teaching surface for adopters never includes this layout.

Two viable shapes:

1. **Single-root.** One `pyproject.toml` at repo root. All packages (`standard_service_stub`, future `producer`, `consumer`, `models`) live under `src/` and share one venv and one dep list.
2. **uv workspace.** Root `pyproject.toml` declares workspace members. Each member has its own `pyproject.toml` with its own dependency declaration. One shared lockfile resolves all members together; each member builds independently.

This decision pairs with ADR-0009 (distroless final stage). The layout choice determines whether each service's Dockerfile can copy *only that service's* dependency closure into the builder stage, which determines whether the distroless final image stays minimal by construction or by careful policing of extras.

## Decision

Adopt **uv workspaces**. Root `pyproject.toml` declares the workspace; each member package has its own `pyproject.toml`. Sprint 1 ships a single member (`standard_service_stub`) under the workspace shape. Sprint 2 adds `producer`, `consumer`, and `models` as additional members; the latter is a workspace-internal dependency referenced via `[tool.uv.sources]` from the other two.

## Rationale — technical

1. **Dependency divergence is real and starts in Sprint 2.** Producer and consumer pull in `confluent-kafka` (librdkafka C dep), Avro libraries, and the schema-registry client. The stub doesn't. Under single-root, every service container ships the union of all dependencies — directly degrading the distroless minimization story from ADR-0009.
2. **Shared models package becomes first-class.** Sprint 2's Pydantic models are imported by both producer and consumer. As a workspace member (`gridstream-models`), this is a one-line declaration in each importing member's `pyproject.toml`. Under single-root, models live as a top-level `src/` directory whose import paths get progressively more brittle as the project grows.
3. **Per-member lockfile slices.** Each member's Dockerfile builder stage copies only the relevant member's resolved deps. The distroless final image carries only what that service needs — minimal by construction, not by hygiene. This is the cleanest possible expression of ADR-0009's intent.

## Rationale — structural

4. **The future-scope second reference service is anticipated, not retrofitted.** A second service is on the roadmap to prove the paved road generalizes. Workspaces want to be in place from Sprint 1; bolting them on later is a touch-everything migration that hits every Dockerfile and every CI job.
5. **Sprint 4's scaffold-a-service script gets a cleaner template.** A workspace member's `pyproject.toml` shape is closer to what an adopting team's repo will actually look like (one `pyproject.toml` per service) than a slice carved out of a single-root setup. The scaffold output and the workspace-member shape end up roughly isomorphic.
6. **Teaching cost in `paved-road.md` is zero either way.** Adopting teams never see this layout. The "easier to teach" framing of the single-root option is asking the wrong question.

## Alternatives Considered

### Single-root `pyproject.toml` — rejected

- **Pro:** Leaner setup, fewer files, simpler initial mental model for someone reading the repo cold.
- **Con:** Union-of-all-deps in every service container. Producer's image carries FastAPI it doesn't run; stub's image carries `confluent-kafka` it doesn't import. Direct conflict with ADR-0009's distroless minimization.
- **Con:** Shared models become a top-level `src/` directory with import paths that get harder to keep clean across services. No declared boundary between what's shared and what's per-service.
- **Con:** Retrofitting workspaces in Sprint 2 (when divergent deps actually arrive) is a refactor that touches every Dockerfile and CI job during a sprint that already has a full plate (schemas, producer, consumer, DLQ, idempotency, deploy via paved road).
- The "easier to teach" argument doesn't survive the disambiguation — adopters' repos look like single workspace members, not like the workspace root.

### One repo per service — rejected

- **Pro:** Maximum isolation. Each service builds, releases, and evolves on its own cadence. Closest to what adopting teams will actually have.
- **Con:** Shared models become a published package on a private registry (CodeArtifact / private PyPI), adding infrastructure and release-coordination cost mid-Sprint-2.
- **Con:** Cross-service refactors (evolving a shared schema, adjusting a shared interlock) require coordinated PRs across repos. For an organization that doesn't yet have this discipline (per ADR-0006), introducing it inside the platform repo is premature.
- **Con:** The project loses its function as a single artifact a successor engineer or hiring committee can read end-to-end.
- Workspaces capture ~90% of the isolation benefit at ~10% of the coordination cost, which is the right tradeoff for a platform repo of this size.

## Consequences

### Positive
- Per-service container builds carry only the dependencies that service actually needs. Pairs cleanly with ADR-0009 — distroless minimization is structural, not policed.
- Shared models package (`gridstream-models`) is a first-class citizen with explicit boundaries, not an import hack.
- Sprint 4's scaffold-a-service script models itself on the member shape, which is closer to what adopting teams will produce in their own repos.
- Future second-service expansion is additive (declare a new member) rather than transformative (split a monolithic root).

### Negative
- Slightly more ceremony at Sprint 1: a root `pyproject.toml` with a `[tool.uv.workspace]` declaration plus a member `pyproject.toml` for the stub. One-time platform-team cost, paid once.
- Marginally more for a reader to parse on first open. Mitigated by a short `README.md` note: *"This is the platform's internal layout. An adopting team's repo is one workspace member's worth of files, not the whole tree."*

### Neutral
- The workspace decision is independent of the build tool. uv is the install/lock tool by ADR-0005; workspaces work analogously in Hatch or Poetry if CI tooling ever changes.

## Revisit If

- Workspace dependency resolution starts producing genuinely incompatible constraints between members (rare in a small single-org repo; common in big polyglot monorepos).
- A service's deployment cadence diverges so far from the rest that release coordination across the workspace becomes a bottleneck (→ promote that member to its own repo).
- uv's workspace semantics change in a way that re-opens the comparison with single-root.

## References

- [ADR-0005: Automated Quality Gates](./0005-automated-quality-gates.md) — uv as the CI install/lock tool
- [ADR-0009: Container Base Image](./0009-container-base-image.md) — per-member lockfile slices keep the distroless final image minimal by construction
- [uv workspaces documentation](https://docs.astral.sh/uv/concepts/projects/workspaces/)
