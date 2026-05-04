# GridStream Execution Roadmap

This document is the **planning surface** for sprint-by-sprint execution. Each sprint is scoped to fit within a single focused work session — about five hours for a human, or one planning-and-execution context window for an LLM pairing partner — and produces a coherent artifact. Read this document, the relevant ADRs, and the current repo state before generating a sprint commit-plan.

**Cut-off discipline.** Every sprint ends with the project in a defensible state. If you stop after Sprint N, the artifact is shippable as a reference deliverable on its own terms. This is by design — the project is structured to optimize for "I had to stop early but what I have is real" rather than "everything depends on the last commit landing."

**Sequencing logic.** Sprint 1 ships the platform artifact before any service uses it, because a paved road defined by its first user isn't a road — it's a one-off. Sprint 2 exercises the road with a real workload, surfacing parameterization gaps. Sprint 3 layers GitOps and observability into the chart, so they become defaults for any future adopter rather than per-service work. Sprint 4 packages the result for organizational adoption. Each step is the natural prerequisite for the next; reordering them produces an artifact that's harder to adopt, not just one that takes longer to build.

---

## 🟢 Sprint 1: The Paved Road

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
- Document the call pattern: a team's repo includes this via `uses: <org>/gridstream/.github/workflows/standard-python-service.yml@v1`

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

---

## 🟡 Sprint 2: The Reference Service

**Goal (Reference Implementation):** Build the energy ingestion service and deploy it via Sprint 1's paved road. This sprint *consumes* the paved road; if the chart needed customization for the service, that's a signal the chart was under-parameterized in Sprint 1 — fix the chart, don't fork it.

### Concepts Exercised
This sprint engages directly with:
- Avro schemas (`.avsc` format), Schema Registry compatibility modes (`BACKWARD`, `BACKWARD_TRANSITIVE`, `FORWARD`, `FULL`)
- `confluent-kafka` Python client (Producer/Consumer API basics, `AvroSerializer`, `AvroDeserializer`)
- DLQ routing pattern in Kafka
- Pydantic v2 ↔ Avro coexistence pattern (Pydantic for in-process validation, Avro for the wire)

### Tasks

**2.1 — Schemas** (`schemas/power_reading.avsc`)
- Fields aligning with SCADA + IoT requirements per `ARCHITECTURE.md` §2
- Compatibility set to `BACKWARD_TRANSITIVE` per ADR-001
- Include `device_id`, `timestamp`, `voltage`, `frequency`, `priority_level`, `firmware_version`

**2.2 — Pydantic models** (`src/models/power_reading.py`)
- Mirrors the Avro schema with field validators
- Catches "zero-voltage" / "null-ID" anomalies before serialization
- Type-checked via `mypy` in the shared CI pipeline

**2.3 — Producer** (`src/producer/main.py`)
- Reads CSV (sample energy data in `data/`)
- Pydantic-validates each row
- Avro-serializes via Schema Registry client
- Publishes to `gridstream.readings`
- Circuit breaker on Kafka unavailability (graceful buffer/fail per ADR-003)
- Structured logging with `device_id` and `schema_version` context per ADR-004

**2.4 — Consumer** (`src/consumer/main.py`)
- Subscribes to `gridstream.readings`
- DLQ routing to `gridstream.failed` on schema or business validation failure
- Idempotency check via `msg_id = device_id + timestamp` (in-process dict for now; Redis stub deferred)
- Wet-bulb safety interlock (logs warning, suspends action) per ADR-003

**2.5 — Local Docker Compose for Kafka stack** (`docker-compose.yml`)
- Kafka, Zookeeper (or KRaft), Schema Registry, Kafka UI for debugging
- Wired into `make infra-up`

**2.6 — Deploy via paved road**
- The consumer Helm release uses the Sprint 1 chart, parameterized via `charts/standard-service/values-consumer.yaml`
- The producer is a CronJob (or one-shot Job) using the same chart's job template, or a tiny chart extension if the base chart can't accommodate jobs cleanly

### Definition of Done
- `python src/producer/main.py --source data/sample_energy.csv` publishes 1,000 valid Avro messages
- A poison-pill row in the CSV is routed to `gridstream.failed` without crashing the consumer
- `helm upgrade --install gridstream-consumer charts/standard-service -f values-consumer.yaml` deploys cleanly
- Schema evolution test: add a new optional field to `power_reading.avsc`, verify backward compatibility check passes

### Scope / Anti-scope
- **In:** Producer, consumer, schemas, models, DLQ, idempotency, safety interlock, local Kafka stack.
- **Out:** OpenTelemetry, Prometheus metrics, ArgoCD sync, lag-based HPA (Sprint 3). Distributed Redis idempotency (deferred). Real cloud Kafka (Sprint 5).

### Cut-off Value
Stopping here yields the paved road plus a working reference service — a complete reference service built on its own platform's standards, demonstrating schema evolution, DLQ handling, and safety-critical defaults.

### Housekeeping
- [ ] number of tests are going to ~quintuple here. Use this pattern and patterns like it (individual TestClients in sprint 1 tests were good for a learning pattern across 4 tests, but we should be more efficient in sprint 2)
	```
	@pytest.fixture
	def client():
	    with TestClient(app) as c:
	        yield c

	def test_healthz_returns_200_with_alive_status(client) -> None:
	    response = client.get("/healthz")
	    # ...
	```
---

## 🟠 Sprint 3: GitOps + Observability

**Goal (DevOps Chops):** Close the platform-engineering half of the project's technical story. Convert the deploy-by-CLI flow into pull-based GitOps; instrument the service with OpenTelemetry; expose metrics and SLO dashboards.

### Concepts Exercised
This sprint engages directly with:
- ArgoCD: `Application` CRD, sync policies, app-of-apps pattern
- OpenTelemetry: traces vs metrics vs logs; OTel collector; W3C trace context propagation through Kafka headers
- Prometheus: scrape config, ServiceMonitor CRD, prometheus-adapter for K8s custom metrics
- Grafana: Golden Signals dashboard pattern (Latency, Traffic, Errors, Saturation)
- SLO math: error budget, burn rate, multi-window multi-burn-rate alerting

### Tasks

**3.1 — ArgoCD setup** (`argocd/`)
- Install ArgoCD via Helm into the local Kind cluster
- App-of-apps root manifest pointing at `argocd/apps/`
- Per-service `Application` manifests for the consumer and producer
- Document the "Git push → ArgoCD detects drift → cluster syncs" flow in `docs/gitops.md`

**3.2 — OpenTelemetry instrumentation**
- `opentelemetry-instrumentation-confluent-kafka` for the consumer
- Manual span creation for `process_message`
- W3C trace context propagation via Kafka headers (so producer → consumer is one trace)
- OTel collector deployed via Helm (sidecar or daemonset)
- Bake OTel as a default in the paved-road chart so Sprint 4 onboarded teams inherit it

**3.3 — Prometheus + Grafana**
- Helm-install kube-prometheus-stack
- ServiceMonitor for the consumer
- Custom metric: `kafka_consumer_group_lag` exposed via prometheus-adapter
- Golden Signals dashboard JSON in `dashboards/gridstream.json`
- SLO panel: ingestion latency 99th percentile

**3.4 — Lag-based HPA** (`charts/standard-service/templates/hpa.yaml`)
- Optional template (gated on `values.hpa.enabled`)
- Target metric: `kafka_consumer_group_lag` from prometheus-adapter
- Min/max replicas, target value documented in `values.yaml`

**3.5 — SLO definition** (`docs/slos.md`)
- Ingestion latency SLO (99% < 500ms)
- Error budget calculation
- Alert rules in `alerts.yml`

### Definition of Done
- Jaeger UI shows a single trace from producer → Kafka → consumer
- Grafana dashboard shows Lag, Error Rate, and Latency in real time
- Burst-load test (10x messages) triggers HPA scale-up via lag, not CPU
- ArgoCD reports `Synced` and `Healthy` for both apps

### Scope / Anti-scope
- **In:** GitOps, OTel, metrics, dashboards, lag-HPA, SLOs.
- **Out:** Production AWS deploy (Sprint 5). Cross-cluster ArgoCD federation. Multi-tenancy in the observability stack.

### Cut-off Value
Stopping here yields the full technical narrative — paved road, reference service, plus the observability and GitOps tooling that makes the platform self-service for application teams. Covers the concepts that complete a credible platform-engineering story: pull-based GitOps as deployment model, OpenTelemetry as the instrumentation standard, observability-driven autoscaling via the chart, and SLO-based reliability investment.

### Housekeeping
- [ ] Install an admission-policy engine (Kyverno or OPA Gatekeeper — pick during sprint) and ship a baseline policy that rejects pods without `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and `capabilities.drop` containing `ALL`. Server-side defense-in-depth complementing ADR-0011's `values.schema.json`: the schema catches misconfiguration at `helm install`; admission policy catches anything that bypasses the chart. Pairs with the Sprint 3 observability stack — policy violations should surface in Grafana alongside the golden-signals dashboards.

---

## 🔴 Sprint 4: Migration Narrative + Polish

**Goal (Staff-Level Wrapper):** Document the multi-team migration story and provide tooling that makes onboarding cheap. This is what makes the platform layer adoptable by an organization, not just usable by a team.

### Concepts Exercised
This sprint engages directly with:
- Cookiecutter or shell-based scaffolding patterns
- Adoption sequencing as a change-management discipline (per-stage opt-in, rollback granularity)
- Stakeholder narrative writing (this sprint is more documentation-heavy than code-heavy)

### Tasks

**4.1 — Scaffold-a-service script** (`scripts/scaffold-service.sh` or `cookiecutter/`)
- One command generates a new service skeleton wired to the paved road
- Pre-populated with `values.yaml`, workflow inclusion (`uses:` line), basic tests, Pydantic model template
- Smoke test: scaffolded service passes CI on first push

**4.2 — 5-team adoption playbook** (`docs/adoption-playbook.md`)
- Stage 1: `Makefile` adoption (Week 1, ~2 hours per team)
- Stage 2: shared workflow inclusion (Week 2–3)
- Stage 3: paved-road chart adoption (Week 4–6)
- Stage 4: ArgoCD opt-in (Week 7+)
- Per-stage success criteria, common objections, mitigation patterns
- Rollback plan for each stage

**4.3 — ADR sweep**
- Read through ADR-001 through ADR-007; update any that drifted from implementation
- Add ADR-008 (or higher) if any significant decision arose during execution that's not yet recorded

**4.4 — ARCHITECTURE.md sync**
- Reflect what's actually built (vs. originally proposed)
- Add a "What I'd do differently" section for honesty

**4.5 — Demo recording**
- 5-minute screencast: scaffold a service → push to Git → ArgoCD syncs → service appears in Grafana

### Definition of Done
- A new team could adopt the paved road end-to-end in under one working day using the playbook
- The scaffold script generates a working service that passes CI on first push
- ARCHITECTURE.md and ADRs accurately describe the as-built system
- Demo is recorded and linkable from README

### Cut-off Value
Stopping here yields the complete platform story. The migration narrative is what differentiates "a thing was built" from "an organization adopted a thing." The technical artifact alone doesn't bridge that gap; the playbook and scaffolding tooling do.

### Housekeeping
- [ ] Decide in Sprint 4 whether clock skew defensive coding belongs in the ADR record or just in the playbook. Could be something like: "ADR-0011: Server-stamped timestamps for cross-service writes" would record: the problem (clock skew), the decision (always server-stamp on the receiver), the consequences (slightly more code, no clock-drift bugs), references to ADRs 0001 and 0003.
- [ ] Scaffold template includes:
  - src/<package>/py.typed (PEP 561 marker)
  - src/<package>/__init__.py with __version__
  - src/<package>/__main__.py for python -m invocation
  - tests/__init__.py + tests/test_<package>.py smoke tests
  - pyproject.toml shaped after standard-service-stub
  - py.typed marker registered in [tool.hatch.build.targets.wheel]
---
- [ ] Add a recommendation to the Sprint 4 adoption playbook that adopting teams configure CODEOWNERS on their `values-*.yaml` files, requiring platform-team review for any change that touches `podSecurityContext` or `containerSecurityContext`. Social enforcement complementing the schema (ADR-0011); puts a human in the loop on the override path the schema can't pin without breaking legitimate use cases.

### CI workflow follow-ups deferred from Sprint 1

When registry push lands (per ADR-0006, Stage 4):

- [ ] Wire registry push in `.github/workflows/standard-python-service.yml`
      build job — replace the `[SPRINT-4-CLEANUP]` comment block with the
      actual push step. Tag with both `${{ github.sha }}` (immutable, what
      ArgoCD pins to) and a moving tag (`:main` or `:latest`) for human
      convenience.
- [ ] Add job-level `permissions:` to the build job:
```yaml
      build:
        permissions:
          contents: read    # checkout still needs this
          packages: write   # registry push
```
      **Footgun:** job-level permissions *replace* workflow-level, they do
      not merge. Dropping `contents: read` here will break `actions/checkout`
      with a permissions error. The workflow-level `contents: read` does
      not flow down once a job declares its own `permissions:` block.
- [ ] Add a smoke-test step after build: `docker run --rm <image> --version`
      (or equivalent health check). Catches "image built but won't start"
      before it ships to the registry.
- [ ] Revisit the `coverage-threshold` input. Has any adopter exercised
      the override? If yes, are the cases legitimate, and should the
      threshold be tuned? If no, the input is dead weight on the public
      contract and worth removing at v2. **Trigger:** post-first-adopter,
      same window as the version-pin audit.
- [ ] Audit adopter version pins: run the GitHub code-search query for
      `uses: sooperD00/gridstream/.github/workflows/standard-python-service.yml`
      and confirm no adopter is still on a pre-push version that would
      break when push lands. Coordinate cutover timing in #platform-standards.



## ⚪ Sprint 5: AWS Deployment (Deferred / Stretch)

**Goal (Cloud Substrate Validation):** Migrate the local Kind deployment to a real AWS EKS cluster. This sprint is deferred — it does not need to be complete to validate the platform's design.

**Why deferred, not omitted:** The architectural argument stands without AWS. But there's a meaningful difference between *"the design targets AWS"* and *"the design has been validated against AWS."* This sprint exists to close that loop, scheduled separately from the rest so the AWS work doesn't compete with the architectural decisions for sprint-window attention.

### Concepts Exercised
This sprint engages directly with the AWS-native substrate the project's design targets:
- AWS account setup, IAM basics, billing alerts
- Terraform / OpenTofu fundamentals: providers, resources, modules, state, `plan` vs `apply`
- EKS architecture: node groups, IAM Roles for Service Accounts (IRSA), aws-auth ConfigMap
- AWS MSK (managed Kafka) vs. self-managed Kafka tradeoffs
- AWS Glue Schema Registry (alternative to Confluent's; compatibility shim if needed)
- ArgoCD on EKS (mostly the same as local, but with proper TLS and OAuth)

### Tasks (high level — to be detailed in sprint planning)

**5.1 — Terraform module** (`infra/terraform/`)
- VPC + public/private subnets + NAT gateway
- EKS cluster + managed node group
- MSK cluster (smallest possible — `kafka.t3.small`)
- Glue Schema Registry
- IAM roles for IRSA

**5.2 — IRSA wiring**
- Service accounts in K8s mapped to IAM roles
- Document the OIDC trust policy pattern
- Update the paved-road chart to support service-account specification

**5.3 — MSK + Glue migration**
- Producer/consumer config switch from local Kafka to MSK
- Schema Registry switch from Confluent to Glue (or document compatibility shim)
- Verify the same Avro schemas work against Glue

**5.4 — ArgoCD on EKS**
- ArgoCD Helm install on the EKS cluster
- Repo connection via GitHub PAT or OAuth app
- Same `argocd/apps/` manifests work unchanged (this is the test of GitOps portability)

**5.5 — Cost guardrails**
- Document monthly burn rate
- `terraform destroy` runbook to avoid surprise bills
- Tag everything for cost attribution
- AWS Budgets alarm at e.g. $50/month

### Definition of Done
- `terraform apply` from a clean account produces a working cluster running the reference service
- The service produces and consumes from MSK, validating against Glue
- ArgoCD `Application` syncs from GitHub
- `terraform destroy` returns the account to baseline cleanly (verified with the AWS bill)

### Cut-off Note
This sprint is **explicitly deferred**. It does not block any Sprint 1–4 deliverable. The architecture in CONTEXT.md and ARCHITECTURE.md *targets* AWS, but the local Kind environment exercises every architectural decision. AWS deployment validates the design against the real substrate; the design itself stands without it.

---

## 📝 Future Scope (Beyond Sprint 5)

- Distributed idempotency via Redis (replacing the in-process dict from Sprint 2)
- Hardware-in-the-loop testing with real smart-meter hardware
- Multi-region MSK federation
- Feature flags (LaunchDarkly or Unleash) for production deploy/release decoupling
- SOC 2 / NERC-CIP compliance documentation pass
- A second reference service (different language? different domain?) to prove the paved road generalizes


---

## Housekeeping

Cross-cutting items not tied to a sprint. Promote to a sprint commit when
convenient.

- [ ] CHANGELOG.md scaffolded with `[Unreleased]` section. Pre-@v1.
- [ ] Semver policy documented in paved-road.md (patch/minor/major
      contract for adopters pinning @v1). Pre-@v1.

## Tech debt

Things we'd do differently if we were starting over, or know we'll have
to revisit. Triggers usually internal — pain accumulating in CI, refactor
opportunities, deferred SPRINT-N-CLEANUP markers coming due.

*(empty for now)*

## Post-adoption

Items waiting on external triggers — adopters arriving, scale crossing
a threshold, a second cloud entering scope. Each item names its trigger.
Promote when the trigger fires; delete from here when promoted.

- [ ] Document the adopter-version code-search query in paved-road.md
      under a new "Platform team operations" section.
      **Trigger:** first external adopter merges a `uses:` line.
- [ ] Scripted adopter audit (GitHub API → weekly CSV → manager report).
      **Trigger:** ≥2 external adopters. Worth a dedicated ADR at build
      time — "how the platform team monitors adoption" is architectural.
      Backstage's service catalog is the prebuilt alternative to revisit
      per ADR-0008 at this point.
- [ ] Regex-validate `image-name` input in standard-python-service.yml
      to reject registry-prefixed or tagged values (currently caught
      only by build-step failure). Cheap to add — a single shell step
      with a regex check before the build job runs.
      **Trigger:** first adopter who hits the double-tag failure and
      asks "why didn't you just check this?" If nobody hits it, the
      documentation in the input description is sufficient.
