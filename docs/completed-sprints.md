# GridStream Completed Sprints

In reverse chronological order.

---

## 🟢 Sprint 1: The Paved Road — DONE 5/6/2026

**Goal (The Platform Itself):** Build the platform artifact that other teams will adopt. The reference service does not exist yet — that's intentional. A paved road is defined by its shape, not by what travels on it.

### Concepts Exercised
This sprint engages directly with:
- Helm chart anatomy: `Chart.yaml`, `values.yaml`, `templates/`, `_helpers.tpl`
- GitHub Actions reusable workflows: `workflow_call` trigger, inputs, secrets passing, `uses:` syntax from a calling repo
- Liveness vs. readiness probes (when each fails, what K8s does next)
- Pre-commit hook configuration with `ruff` and `mypy`
- Multi-stage Dockerfile patterns (distroless or alpine base)

### Tasks

**1.1 — Paved-road Helm chart** (`charts/standard-service/`)
- `Chart.yaml` (name: `standard-service`, version: `0.1.0`)
- `values.yaml` with documented defaults: replica count, image, resource requests/limits, probe paths, service port, environment variables, optional sidecar slot
- `templates/deployment.yaml` with liveness + readiness probes (overridable but defaulted to `/healthz` and `/readyz`)
- `templates/service.yaml`
- `templates/_helpers.tpl` for label/selector consistency (every team's chart inherits the same `app.kubernetes.io/*` labels)
- `templates/configmap.yaml` for non-secret config
- `charts/standard-service/README.md` documenting the contract: what `values.yaml` accepts, what teams must override, what they should not touch

**1.2 — Reusable GitHub Actions workflow** (`.github/workflows/standard-python-service.yml`)
- Trigger: `workflow_call`
- Inputs: `python-version` (default 3.11), `coverage-threshold` (default 80), `image-name` (required)
- Steps: checkout → setup Python → install deps via `uv` → `ruff check` → `mypy` → `pytest` with coverage gate → build container → push (registry push can be stubbed for now with a clear TODO that points to Sprint 4 or 5)
- Document the call pattern: a team's repo includes this via `uses: <org>/GridStream/.github/workflows/standard-python-service.yml@v1`

**1.3 — Service stub** (`src/standard_service_stub/`)
- Minimal FastAPI service with `/healthz` and `/readyz` endpoints
- Pydantic v2 models for request/response
- One dummy endpoint that returns a structured response (e.g. `/echo`)
- This service exists *to prove the chart and workflow function*. It is not the reference service (that's Sprint 2).

**1.4 — Local dev plumbing**
- `Makefile` with targets: `setup`, `lint`, `test`, `build`, `infra-up`, `infra-down`, `deploy-local`, `help`
- `.pre-commit-config.yaml` with ruff and mypy
- `pyproject.toml` for the stub service (using `uv` for deps)
- `Dockerfile` (multi-stage; final stage distroless or alpine)
- `kind/cluster.yaml` config for the local cluster

**1.5 — Documentation**
- `docs/paved-road.md`: 10-minute tutorial format — "How to adopt the paved road for your service"
- Update `README.md` Quickstart to reflect what's actually runnable after Sprint 1
- A short `make help` output that scans cleanly

### Definition of Done
- `make infra-up && make deploy-local` brings up Kind and deploys the stub service via `helm install`
- `kubectl get pods` shows the stub service in `Ready` state with both probes green
- The reusable workflow file is callable; CI is green on a dummy PR
- A teammate could read `docs/paved-road.md` and adopt the chart for their own service in under an hour

### Scope / Anti-scope
- **In:** Chart, workflow, stub, Makefile, pre-commit, Dockerfile, local Kind setup, paved-road docs.
- **Out:** Avro, Kafka producer/consumer logic, OTel instrumentation, lag-based HPA, ArgoCD (Sprints 2–3). Real AWS deploy (Sprint 5).

### Cut-off Value
Stopping here yields a *paved road without traffic* — a parameterized service chart and reusable CI workflow that any team in a 5+ team org could adopt to standardize their deployment surface.

### Reflections

**What shipped.** Kind cluster up, stub deployed via Helm with both probes green, the reusable workflow runs CI clean on every push, the chart README documents the four-tier values contract, and `paved-road.md` is the ten-minute adoption read. Definition of Done above is satisfied — that's what Sprint 1 ending means.

**Decisions that emerged mid-sprint.** Four ADRs landed while Sprint 1 was in flight, beyond what the planning doc anticipated:

- [ADR-0009](./adr/0009-container-base-image.md) (2026-04-29) — distroless over Alpine.
- [ADR-0010](./adr/0010-multi-package-layout-with-uv-workspaces.md) (2026-04-29) — uv workspaces over single-root pyproject.
- [ADR-0011](./adr/0011-enforce-values-contract-via-json-schema.md) (2026-05-01) — `values.schema.json` makes the chart's contract machine-enforced.
- [ADR-0012](./adr/0012-sha-pin-third-party-actions.md) (2026-05-04) — SHA-pin third-party Actions; Dependabot keeps them moving.

Each one came from hitting the issue while building, not from foresight. The ADR record is honest about that — decisions get written down when the problem is concrete, not pre-emptively.

**Forcing functions in place for next sprints.** Per [ADR-0004](./adr/0004-logging-and-stub-standards.md), every spot where Sprint 1 stopped short of a future sprint's scope carries a grep-able SPRINT N CLEANUP marker. Sprint close becomes a mechanical check (zero remaining markers for that sprint number) instead of a vibes-based "did we tie up loose ends" question.

**What I'd do differently.** *[Placeholder — what came together easily, what fought back, what surprised me, what I'd revisit if I were starting Sprint 1 fresh.]*

---

## Sprint 0: Discovery, Requirements, Architecture, Planning — DONE 4/29/2026 11:15a
