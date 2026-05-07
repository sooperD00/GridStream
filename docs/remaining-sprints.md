# GridStream Execution Roadmap

This document is the **planning surface** for sprint-by-sprint execution. Each sprint is scoped to fit within a single focused work session — about five hours for a human, or one planning-and-execution context window for an LLM pairing partner — and produces a coherent artifact. Read this document, the relevant ADRs, and the current repo state before generating a sprint commit-plan.

For what's already shipped, see [`completed-sprints.md`](./completed-sprints.md) — the prologue this document continues.

**Cut-off discipline.** Every sprint ends with the project in a defensible state. If you stop after Sprint N, the artifact is shippable as a reference deliverable on its own terms. This is by design — the project is structured to optimize for "I had to stop early but what I have is real" rather than "everything depends on the last commit landing."

**Sequencing logic.** Sprint 1 ships the platform artifact before any service uses it, because a paved road defined by its first user isn't a road — it's a one-off. Sprint 2 exercises the road with a real workload, surfacing parameterization gaps. Sprint 3 layers GitOps and observability into the chart, so they become defaults for any future adopter rather than per-service work. Sprint 4 packages the result for organizational adoption. Each step is the natural prerequisite for the next; reordering them produces an artifact that's harder to adopt, not just one that takes longer to build.

**Sub-sprint splits.** Sprint 2 was originally scoped as one sprint; planning at Sprint-1 close found the workload landed at ~2.5× the cadence above. Split into 2A (the wire contract), 2B (producer + chart Job template), 2C (consumer + safety + DLQ). Same cut-off discipline — each sub-sprint ends with the project in a defensible state on its own terms.

---

## 🟡 Sprint 2A: The Wire Contract

**Goal (Define Before You Use):** Land the Avro schema, the Pydantic mirror, and the local Kafka stack — the contract that 2B and 2C will be built against. This sprint *defines* the wire; producer and consumer come later. A contract that's only validated through its first consumer isn't a contract — it's a coincidence.

### Concepts Exercised
This sprint engages directly with:
- Avro schemas (`.avsc` format), Schema Registry compatibility modes (`BACKWARD`, `BACKWARD_TRANSITIVE`, `FORWARD`, `FULL`)
- Pydantic v2 ↔ Avro coexistence pattern (Pydantic for in-process validation, Avro for the wire)
- `packages/models/` as a workspace member shared by producer and consumer per ADR-0010
- Local Kafka stack via Docker Compose: Kafka (KRaft), Confluent Schema Registry, Kafka UI

### Decisions baked in (no further decision needed at kickoff)
- **Pydantic↔Avro pattern:** hand-write both files; a round-trip test asserts they agree. Codegen deferred — revisit only if drift becomes painful.
- **Kafka topology:** KRaft mode, no Zookeeper. Modern default; fewer moving parts in the dev stack.
- **Compatibility mode:** `BACKWARD_TRANSITIVE` per ADR-0001.

### Tasks

**2A.1 — Avro schema** (`schemas/power_reading.avsc`)
- Fields aligning with SCADA + IoT requirements per ARCHITECTURE.md §2 and §6
- Compatibility set to `BACKWARD_TRANSITIVE` per ADR-0001
- Includes `device_id`, `timestamp`, `voltage`, `frequency`, `priority_level`, `firmware_version`

**2A.2 — Models package** (`packages/models/`)
- Workspace member per ADR-0010, sibling to `standard-service-stub`
- `pyproject.toml` shaped after the stub: hatchling build, `py.typed` marker, `[tool.mypy]` strict block
- `src/gridstream_models/power_reading.py`: Pydantic v2 model mirroring the Avro schema with field validators that catch zero-voltage and null-ID anomalies before serialization
- `__init__.py` with `__version__`; `py.typed` registered in `[tool.hatch.build.targets.wheel]`
- README replaces the Sprint-1 placeholder

**2A.3 — Pydantic↔Avro round-trip + schema/model parity test** (`packages/models/tests/`)
- Round-trip: Pydantic instance → Avro encode → Avro decode → Pydantic instance, assert equality
- Parity: test fails if the Avro schema gains a field the Pydantic model doesn't have, or vice versa (this is the safety net that lets "hand-write both" stay sane)
- Uses the fixture-based test pattern (see Housekeeping below)

**2A.4 — Local Kafka stack** (`docker-compose.yml` at repo root)
- Kafka (KRaft mode), Confluent Schema Registry, Kafka UI (provectus or equivalent)
- Topics created at startup: `gridstream.readings`, `gridstream.failed`
- Wired into `make infra-up` alongside the existing Kind cluster (composite target — Kind for the chart's runtime, Compose for the messaging substrate)

**2A.5 — Schema-evolution smoke test**
- Add a new optional field to `power_reading.avsc`, register against the local Schema Registry, verify the `BACKWARD_TRANSITIVE` compatibility check passes
- Distinct from 2A.3: this validates *the registry is doing its job*, not that the Pydantic model agrees with the Avro file. Both matter.
- Lives as a script under `scripts/` (callable from a Make target) so it runs against any environment with a Schema Registry

**2A.6 — Workspace-root cleanup for the models package**
- `pyproject.toml`: add `packages/models` to `[tool.uv.workspace] members`
- Remove `packages/models` from `[tool.ruff] extend-exclude`
- Add `gridstream_models` to `[tool.ruff.lint.isort] known-first-party`
- Add models test path to `[tool.pytest.ini_options] testpaths`
- (Producer/consumer cleanups stay marked — they belong to 2B/2C.)

### Definition of Done
- `make infra-up` brings up Kind + Kafka + Schema Registry + Kafka UI
- `kafka-topics --list` shows `gridstream.readings` and `gridstream.failed`
- Pydantic↔Avro round-trip test passes; schema/model parity test passes
- Schema-evolution test: registering an Avro schema with one new optional field returns a compatible response from the Schema Registry
- `git grep "SPRINT-2-CLEANUP"` shows no models-related markers remaining (producer/consumer markers expected to remain)

### Scope / Anti-scope
- **In:** Avro schema, Pydantic models package, Pydantic↔Avro pattern, local Kafka stack, schema-evolution smoke test.
- **Out:** Producer (2B), consumer (2C), DLQ logic, idempotency, safety interlock, deploy via paved road, chart Job template.

### Cut-off Value
Stopping here yields the wire contract — Avro schema, Pydantic mirror, and a running local Kafka + Schema Registry stack that proves both. 2B and 2C have something concrete to build against; the contract is independently testable without traffic on it yet.

### Housekeeping
- [ ] Adopt the fixture-based test pattern as the convention from this sprint forward — Sprint 1's "individual TestClient per test" worked as a learning shape across 4 tests but doesn't scale through 2A → 2C's quintupled test count:
    ```python
    @pytest.fixture
    def client():
        with TestClient(app) as c:
            yield c

    def test_healthz_returns_200_with_alive_status(client) -> None:
        response = client.get("/healthz")
        # ...
    ```

---

## 🟡 Sprint 2B: Producer + Chart Job Template

**Goal (First Real Adopter):** Build the synthetic producer and add the Job/CronJob template to the paved-road chart. This is the sprint where the chart's parameterization gets stress-tested against a non-long-running workload. If the chart can't accommodate a Job cleanly, that's a parameterization gap the chart needs to close — fix the chart, don't fork it.

### Concepts Exercised
This sprint engages directly with:
- `confluent-kafka` Python client (Producer API basics, `AvroSerializer`, Schema Registry client)
- Circuit breaker pattern on Kafka unavailability per ADR-0003
- Helm chart Job/CronJob templates: different probe semantics, different completion semantics, different `restartPolicy` than a Deployment
- Per-member Dockerfile shape (multi-stage distroless from ADR-0009)

### Decisions to make at kickoff (deferred from planning)
- [ ] **Producer deployment shape.** Three options, each with different chart consequences:
  - (a) one-shot Job that runs the CSV through and exits
  - (b) CronJob that runs on a schedule
  - (c) long-running Deployment that loops the CSV indefinitely (in which case the producer also needs `/healthz` and `/readyz` per the chart's const-pinned probe paths)
- [ ] **If Job/CronJob:** values shape for the new `job:` block in the chart. The chart README's Sprint-2-CLEANUP entry already commits to the values being "namespaced under `deployment:` so a sibling `job:` block can be added without breaking changes" — this is where that sibling block actually lands. `values.schema.json` will need a corresponding branch.
- [ ] **Sample data origin.** Three options:
  - (a) synthesize on the fly in producer code — fastest, but the data shape is whatever the producer says it is
  - (b) vendor a small (~1k-row) CSV in `data/` — most reproducible
  - (c) download-in-script from NREL/Pecan Street as a `make data` target — most honest about the data source
  Whichever option lands, the dataset must include at least one poison-pill row for 2C's DLQ test.

### Tasks (concrete after decisions above)

**2B.1 — Producer package** (`packages/producer/`)
- Workspace member; `pyproject.toml` shaped after the stub
- Depends on `gridstream-models` via `[tool.uv.sources]` per ADR-0010
- `src/gridstream_producer/main.py`:
  - Reads CSV from `data/`
  - Pydantic-validates each row using `gridstream-models`
  - Avro-serializes via Schema Registry client
  - Publishes to `gridstream.readings`
  - Circuit breaker on Kafka unavailability (graceful buffer/fail per ADR-0003)
  - Structured logging with `device_id` and `schema_version` context per ADR-0004
- Replaces the Sprint-1 placeholder README

**2B.2 — Producer Dockerfile** (`packages/producer/Dockerfile`)
- Multi-stage distroless per ADR-0009, modeled on the stub's Dockerfile
- `Dockerfile.dev` slim variant for local debugging

**2B.3 — Chart Job template** (`charts/standard-service/templates/job.yaml`)
- Renders Job or CronJob based on the values selector chosen above
- Shares `_helpers.tpl` labels/naming with the Deployment template
- `values.schema.json` updated with the `job:` branch
- Chart README updated: clear what's a Deployment-shaped service vs. a Job-shaped service, what each tier (must override / should configure / should not override) means in each shape

**2B.4 — Producer values file** (`charts/standard-service/values-producer.yaml`)
- Wires the producer image, Kafka broker config, Schema Registry URL, sample CSV path
- The first real exercise of the chart's Job branch

**2B.5 — Sample data** (`data/sample_energy.csv` or generator/downloader)
- Per the decision above
- At least one poison-pill row for 2C's DLQ test

**2B.6 — Tests** (`packages/producer/tests/`)
- Fixture pattern from 2A
- CSV-read happy path
- Kafka-unavailable → circuit breaker exercises (no crash, structured log line, graceful fail)
- Pydantic validation failure on a bad row → row skipped, logged, doesn't crash the producer
- Avro serialization edge case → handled per the producer's documented contract

**2B.7 — Deploy via paved road**
- `helm upgrade --install gridstream-producer charts/standard-service -f values-producer.yaml` deploys cleanly into Kind
- Cross-stack networking: producer running in Kind talks to Kafka running in Compose. Document the connection string convention in `charts/standard-service/README.md` or `docs/paved-road.md` if it isn't obvious from the values file.

**2B.8 — Workspace-root cleanup for the producer package**
- `pyproject.toml` updates analogous to 2A.6 but for `packages/producer`

### Definition of Done
- `python -m gridstream_producer --source data/sample_energy.csv` publishes 1,000 valid Avro messages to local Kafka
- `helm upgrade --install gridstream-producer ...` deploys cleanly via the chart's new Job template
- Circuit-breaker test passes (Kafka stopped → producer retries gracefully, doesn't crash)
- `helm template` of the chart's Job branch validates against `values.schema.json`; misuse (wrong shape, missing required) fails fast at install time
- `git grep "SPRINT-2-CLEANUP"` shows no producer-related markers remaining

### Scope / Anti-scope
- **In:** Producer service, Dockerfile, chart Job/CronJob template, values-producer.yaml, sample data, deploy via paved road.
- **Out:** Consumer logic (2C — producer publishes; routing decisions are the consumer's job), DLQ routing (2C), idempotency (2C), safety interlock (2C), OTel (Sprint 3).

### Cut-off Value
Stopping here yields a working synthetic producer on the paved road, exercising the chart's Job template — the first non-long-running workload to deploy via the standard chart, validating the values-shape generalization. Messages pile up in `gridstream.readings` waiting for a consumer, which is fine; the producer half of the contract is provably satisfied.

### Housekeeping
- [ ] Idempotency dict for 2C is "in-process for now; Redis stub deferred." Per ADR-0004's silent-TODO ban, when the dict lands in 2C it needs either a `NotImplementedError`-style structured stub at the swap-point OR a SPRINT CLEANUP marker in the consumer code with the future-Redis sprint reference. Note here so 2C remembers.

---

## 🟡 Sprint 2C: Consumer + Safety + DLQ

**Goal (Safety-Critical Pillars Made Real):** Build the resilient consumer with DLQ routing, idempotency, and the wet-bulb safety interlock. This is the sprint where the safety pillars from ADR-0003 become code and not just prose, and where the Sprint-1 stub's `[SPRINT-2-CLEANUP] Sprint 2's consumer will check Kafka and Schema Registry availability here` finally has somewhere to land.

### Concepts Exercised
This sprint engages directly with:
- `confluent-kafka` Python client (Consumer API, `AvroDeserializer`, manual offset commits)
- DLQ routing pattern in Kafka — route, don't crash; single-message failures don't become pipeline outages
- Idempotency via in-process dict (`msg_id = device_id + timestamp`)
- Wet-bulb safety interlock per ADR-0003
- Long-running process with HTTP health endpoints (chart-compliance: probes are const-pinned per ADR-0011)

### Decisions to make at kickoff (deferred from planning)
- [ ] **Consumer's HTTP surface architecture.** The chart const-pins `/healthz` and `/readyz`, so the consumer must expose them. Three options:
  - (a) FastAPI app with the Kafka consumer as a background task — single process, async coordination, matches the stub's shape
  - (b) Kafka consumer in main thread, HTTP server on a side thread — explicit decoupling, less framework
  - (c) Sidecar pattern: Kafka consumer in the main container, separate health-check container in `deployment.extraContainers` — most isolation, most chart complexity
- [ ] **`/readyz` semantics on dependency loss.** What does the readiness probe return when Kafka or Schema Registry are unavailable? 503 (matches the stub's foreshadowing comment) makes the readiness probe genuinely meaningful — Kubernetes pulls the pod out of service rotation while keeping it alive, which is the right behavior. Confirm before implementation.

### Tasks (concrete after decisions above)

**2C.1 — Consumer package** (`packages/consumer/`)
- Workspace member; depends on `gridstream-models` via `[tool.uv.sources]`
- `src/gridstream_consumer/main.py`:
  - Subscribes to `gridstream.readings`
  - Avro-deserializes via Schema Registry
  - DLQ routing to `gridstream.failed` on schema or business validation failure
  - Idempotency check via `msg_id = device_id + timestamp` (in-process dict; carries the SPRINT CLEANUP marker per the 2B housekeeping note)
  - Wet-bulb safety interlock per ADR-0003 — the *interlock* (when triggered, log and suspend) lands in this sprint; the *safety-event detection* (weather API integration) and the *dispatch action being suspended* (downstream SCADA call) are explicitly stubbed via `NotImplementedError` per ADR-0004 with the relevant future-sprint reference
  - HTTP `/healthz` and `/readyz` per the architecture decision above
  - `/readyz` returns 503 when the Kafka client or Schema Registry client report disconnected
- Structured logging with `device_id`, `schema_version`, and `msg_id` context per ADR-0004
- Replaces the Sprint-1 placeholder README

**2C.2 — Consumer Dockerfile** (`packages/consumer/Dockerfile`)
- Multi-stage distroless per ADR-0009; same shape as producer
- `Dockerfile.dev` slim variant

**2C.3 — Consumer values file** (`charts/standard-service/values-consumer.yaml`)
- Wires the consumer image, Kafka broker, Schema Registry URL
- Stays on the chart's existing Deployment branch (long-running process, both probes)

**2C.4 — Tests** (`packages/consumer/tests/`)
- Fixture pattern throughout
- Happy path: message consumed, processed, offset committed
- Poison pill: malformed message routes to `gridstream.failed`, consumer doesn't crash, partition isn't blocked
- Idempotency: duplicate `msg_id` → second occurrence skipped
- Safety event simulated: interlock fires, dispatch suspended, log line emitted
- `/healthz` returns 200 when alive
- `/readyz` returns 503 when the Kafka client is disconnected

**2C.5 — Deploy via paved road**
- `helm upgrade --install gridstream-consumer charts/standard-service -f values-consumer.yaml` deploys cleanly
- Both probes go green
- End-to-end smoke: producer (from 2B) publishes 1,000 messages including the poison pill → consumer processes valid messages, DLQs the poison pill, doesn't double-process anything

**2C.6 — Workspace-root cleanup for the consumer package**
- `pyproject.toml` updates analogous to 2A.6 but for `packages/consumer`

**2C.7 — Final repo-wide [SPRINT-2-CLEANUP] sweep**
- Per ADR-0004, this is the sprint-close mechanical check
- `git grep "SPRINT-2-CLEANUP"` returns zero matches
- Future SPRINT CLEANUP markers (Redis idempotency, weather API integration, downstream dispatch) are explicitly retained — they belong to a different cycle and should not be cleared here

### Definition of Done
- Consumer deployed via paved road; both probes green
- Poison-pill row from 2B's CSV routes to `gridstream.failed` without crashing the consumer
- Duplicate-message idempotency test passes
- Safety-event simulation fires the interlock with the right log line
- End-to-end: `make infra-up && helm install gridstream-producer ... && helm install gridstream-consumer ... && producer publishes 1,000 messages` → consumer processes them, DLQs the poison pill, doesn't double-process anything
- `git grep "SPRINT-2-CLEANUP"` returns no matches; Future SPRINT CLEANUP markers documented and intentional

### Scope / Anti-scope
- **In:** Consumer service, DLQ routing, idempotency, wet-bulb interlock, deploy via paved road, end-to-end smoke.
- **Out:** OTel instrumentation (Sprint 3), Prometheus metrics (Sprint 3), lag-based HPA (Sprint 3), Redis idempotency (future), real cloud Kafka (Sprint 5), weather API integration for safety-event detection (future), downstream SCADA dispatch (future).

### Cut-off Value
Stopping here yields the complete reference service: paved road plus producer plus consumer with safety-critical defaults (DLQ, idempotency, wet-bulb interlock) on a working local stack. Schema evolution, defensive error handling, and the safety pillars from ADR-0003 are all proven in code, not just in prose.

### Housekeeping
- [ ] (Anything that surfaces during 2C lands here. Empty at planning time.)

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
- [ ] Image-tag SHA discipline. Today's `:dev` tag mutation required `helm uninstall + make deploy-local` to force a rollout because helm sees the manifest as unchanged. ArgoCD reconciliation + content-addressed image refs (or imagePullPolicy: Always with digests) makes this a non-issue.
- [ ] Wire `make smoke-test` into the post-deploy verification path. Can't run in plain CI without a deployed cluster; ArgoCD post-sync hooks or a kind-in-CI job is the right home. The script already exits non-zero on failure, so it's gate-ready.

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

- [ ] Wire registry push in `.github/workflows/standard-python-service.yml` build job — replace the `[SPRINT-4-CLEANUP]` comment block with the actual push step. Tag with both `${{ github.sha }}` (immutable, what ArgoCD pins to) and a moving tag (`:main` or `:latest`) for human convenience.
- [ ] Add job-level `permissions:` to the build job:
```yaml
      build:
        permissions:
          contents: read    # checkout still needs this
          packages: write   # registry push
```
**Footgun:** job-level permissions *replace* workflow-level, they do not merge. Dropping `contents: read` here will break `actions/checkout` with a permissions error. The workflow-level `contents: read` does      not flow down once a job declares its own `permissions:` block.
- [ ] Add a smoke-test step after build: `docker run --rm <image> --version` (or equivalent health check). Catches "image built but won't start" before it ships to the registry.
- [ ] Revisit the `coverage-threshold` input. Has any adopter exercised the override? If yes, are the cases legitimate, and should the threshold be tuned? If no, the input is dead weight on the public contract and worth removing at v2. **Trigger:** post-first-adopter, same window as the version-pin audit.
- [ ] Audit adopter version pins: run the GitHub code-search query for `uses: sooperD00/GridStream/.github/workflows/standard-python-service.yml` and confirm no adopter is still on a pre-push version that would break when push lands. Coordinate cutover timing in #platform-standards.


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

- Distributed idempotency via Redis (replacing the in-process dict from Sprint 2C)
- Hardware-in-the-loop testing with real smart-meter hardware
- Multi-region MSK federation
- Feature flags (LaunchDarkly or Unleash) for production deploy/release decoupling
- SOC 2 / NERC-CIP compliance documentation pass
- A second reference service (different language? different domain?) to prove the paved road generalizes
- Weather-API integration for the wet-bulb safety-event detection stubbed in 2C
- Downstream SCADA dispatch action stubbed in 2C's safety interlock
- Avro-lint CI step for breaking-change detection on schema PRs (referenced in ARCHITECTURE.md §3.4)


---

## Housekeeping

Cross-cutting items not tied to a sprint. Promote to a sprint commit when
convenient.

- [ ] CHANGELOG.md scaffolded with `[Unreleased]` section. Pre-@v1.
- [ ] Semver policy documented in paved-road.md (patch/minor/major contract for adopters pinning @v1). Pre-@v1.
- [ ] CONTRIBUTING.md note on script-mode discipline: new scripts in scripts/ need `chmod +x` so the executable bit is committed (mode 100755). Today's debugging burned 10 minutes on a permission- denied for check-chart-behavior.sh that was committed as 100644.
- [ ] CONTRIBUTING.md or paved-road.md note on Python upgrade coordination: .python-version, the Dockerfile's builder FROM, and the distroless image's bundled Python must all agree. The ARG pattern centralizes the *string* but not the underlying coupling.
- [ ] Watch Dependabot PRs for Node-24-compatible action bumps (checkout, setup-uv, docker/* still on Node 20). Forced switch June 2, 2026; removal Sept 16. Existing weekly cadence should catch each action's release; merge as they arrive.
- [ ] When a second script wants `PY_STRIP_DOCSTRINGS` or `PY_CANONICALIZE` (the inline Python heredocs in `check-no-code-changes.sh`), extract them to `scripts/lib/diff-helpers.sh` rather than copy-paste. Two real consumers will tell you the right interface; one consumer can only guess. Trigger phrases: a new `scripts/check-*.sh` that needs to canonicalize structured config, or any script that needs to compare Python ASTs.
- [ ] Refactor `check_no_code_changes.py` to batch git operations: replace per-file `git show` calls with one `git cat-file --batch` invocation (~22 subprocesses → 1). Trigger: the script feels slow on Windows, or you want it usable in CI on a runner with cold-start subprocess overhead.
- [ ] Add `.gitattributes` with `*.sh text eol=lf` to enforce LF endings on shell scripts regardless of platform autocrlf settings. Pre-empts the "mysterious '\r': command not found errors" rabbit hole the next Windows contributor would otherwise fall into.
- [ ] README.md roadmap table (§3) still lists Sprint 2 as one row. Either expand to 2A/2B/2C or leave as nominal "Sprint 2" for the marketing surface and let this doc be the execution detail. Decide before the README is read by an outside audience.

## Tech debt

Things we'd do differently if we were starting over, or know we'll have to revisit. Triggers usually internal — pain accumulating in CI, refactor opportunities, deferred SPRINT-N-CLEANUP markers coming due.

*(empty for now)*

## Post-adoption

Items waiting on external triggers — adopters arriving, scale crossing a threshold, a second cloud entering scope. Each item names its trigger. Promote when the trigger fires; delete from here when promoted.

- [ ] Document the adopter-version code-search query in paved-road.md under a new "Platform team operations" section. **Trigger:** first external adopter merges a `uses:` line.
- [ ] Scripted adopter audit (GitHub API → weekly CSV → manager report). **Trigger:** ≥2 external adopters. Worth a dedicated ADR at build time — "how the platform team monitors adoption" is architectural. Backstage's service catalog is the prebuilt alternative to revisit per ADR-0008 at this point.
- [ ] Regex-validate `image-name` input in standard-python-service.yml to reject registry-prefixed or tagged values (currently caught only by build-step failure). Cheap to add — a single shell step with a regex check before the build job runs. **Trigger:** first adopter who hits the double-tag failure and asks "why didn't you just check this?" If nobody hits it, the documentation in the input description is sufficient.
