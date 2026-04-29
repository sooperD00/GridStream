# Project GridStream: A Paved-Road Reference Implementation
**Simulation Scenario for GridCorp — Post-Acquisition Multi-Team Integration**

## 1. Project Context
The Senior Director of Engineering inherited five Flex teams in North America, six in Pune, and a "big bang" deployment culture from a recently dissolved monolithic VP organization. Teams "deploy how they want to meet customer needs." Enginering teams cannot answer:

1. *Do you deploy the way clients want you to?*
2. *Can you deploy faster?*

The 2026/2027 mandate is to migrate at least 5 teams onto a defensible, automated, observable continuous-integration pattern — without halting feature work to get there.

This project is a **reference implementation of the paved road** that platform team would roll out. It includes:

- The paved road itself (shared Helm chart, reusable CI workflow, change-control templates).
- A reference service that *uses* the paved road (energy data ingestion — chosen because it stresses every standardization axis: distributed teams, schema evolution, regulated reliability, bursty load).
- The migration narrative (incremental adoption path, per-team opt-in, ADR-recorded decisions).

**The reference service is a seed example. The value of *this* project is the paved road pattern.**

---

## 2. Core Objectives

- **Standardization:** A shared Helm chart and reusable CI workflow that other teams adopt by reference, not copy-paste.
- **Reliability:** Resilient Kubernetes patterns (probes, lag-based HPA, DLQ) baked into the paved-road defaults.
- **Observability:** OpenTelemetry as the universal instrumentation standard, exported to Prometheus/Grafana with vendor-neutral semantics.
- **GitOps Readiness:** Incremental migration from manual deploys (Makefile) → CI-automated deploys (GitHub Actions) → pull-based GitOps (ArgoCD).
- **Defensible Adoption:** Every standard is documented in an ADR with a migration path that respects existing team velocity.

---

## 3. Architecture Overview

The system has two layers, built in that order:

### Platform Layer (Sprint 1 — the paved road)
- A parameterized Helm chart (`charts/standard-service/`) that any team's service can use as its deployment artifact.
- A reusable GitHub Actions workflow (`.github/workflows/standard-python-service.yml`) callable from any Python service repo via `uses:`.
- Pre-commit configuration, Makefile entry points, change-control templates.
- A trivial service stub that exists only to prove the chart and workflow function end-to-end.

### Reference Service Layer (Sprint 2 — exercises the paved road)
- Pydantic-validated synthetic producer reading energy CSV (NREL/Pecan Street).
- Confluent Schema Registry with Avro contracts.
- `confluent-kafka` consumer with DLQ routing and idempotency.
- Wet-bulb / fail-open safety interlock per ADR-003.

The reference service deploys via the platform layer's artifacts. No bespoke deployment logic. If the chart needs a special case for the reference service, that's a design failure of the chart — not a feature of the service.

### Technical Stack
- **Language:** Python 3.11+ (Pydantic v2, `confluent-kafka`, `uv`, `mypy`, `ruff`)
- **Stream:** Kafka, Confluent Schema Registry (Avro)
- **Orchestration:** Kubernetes (local: Kind / Minikube; AWS EKS deferred to Sprint 5)
- **Automation:** Helm, Makefile, GitHub Actions reusable workflows
- **Continuous Delivery:** ArgoCD (Sprint 3)
- **Observability:** OpenTelemetry, Prometheus, Grafana
- **IaC:** Terraform / OpenTofu (Sprint 5)

---

## 4. Sprint Roadmap

See [`remaining_sprints.md`](./remaining_sprints.md) for the per-sprint task breakdown, prerequisites, and Definition of Done.

| Sprint | Focus | Coherent Cut-off Artifact |
|---|---|---|
| 1 | Paved Road | Shared chart + reusable workflow + service stub |
| 2 | Reference Service | Producer/consumer deployed via Sprint 1 chart |
| 3 | GitOps + Observability | ArgoCD + OTel + Grafana + lag-based HPA |
| 4 | Migration Narrative | Adoption playbook + scaffold-a-service script |
| 5 (deferred) | AWS Deployment | Terraform/EKS/MSK |

Each sprint is scoped to a single development session (~5 hours) and produces a coherent artifact. Stopping after any sprint leaves a defensible reference deliverable.

---

## 5. Defensible Design Decisions

| Decision | Staff-Level Reasoning |
|---|---|
| **Build custom paved road, not adopt Backstage** | The IDP pattern is recognized but no off-the-shelf framework integrates the components for this organizational context. Components are off-the-shelf; the opinions and migration path are custom. (ADR-008) |
| **Paved road first, service second** | The role's mandate is multi-team adoption, not building one more service. The platform artifact has to exist before the reference service can be presented as "an example of." |
| **Reusable GHA workflow, not copy-paste** | Teams that copy CI configs drift in 3 months. Teams that `uses:` a shared workflow inherit security and quality updates automatically. |
| **Helm chart parameterized, not forked** | Same principle. A `values.yaml` is a contract; a forked chart is technical debt. |
| **Avro over JSON** | Compact binary; enforced backward compatibility; cross-team contract enforcement. |
| **Lag-based HPA over CPU** | I/O-bound services have low CPU and high backpressure. Lag is the leading indicator; CPU is reactive. |
| **OpenTelemetry as standard** | Vendor neutrality. The cost of switching observability backends becomes a config change, not a code rewrite. |
| **Incremental GitOps adoption** | Big-bang migrations halt feature work. Per-step opt-in (Makefile → CI → ArgoCD) earns trust without trading velocity. |
| **AWS deferred to Sprint 5** | Local Kind exercises every architectural argument. AWS adds 6+ hours of plumbing without changing the technical story. Real cloud deploy is reference enrichment, deliberately scheduled outside the project's primary sprint window. |
| **Fail-open safety interlocks** | In a regulated SCADA context, "no data" is more dangerous than "bad data." The platform defaults to the safest physical state when telemetry is uncertain. |

---

## 6. Repository Structure

```
.
├── .github/workflows/       # Reusable CI templates (Sprint 1)
├── charts/                  # Paved-road Helm chart (Sprint 1)
├── data/                    # Sample energy CSVs
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONTEXT.md
│   ├── CONTRIBUTING.md
│   ├── DISCOVERY.md
│   ├── adr/
│   └── remaining_sprints.md
├── infra/
│   └── terraform/           # AWS modules (Sprint 5, stubbed)
├── schemas/                 # Avro contracts (Sprint 2)
├── scripts/                 # scaffold-a-service, etc. (Sprint 4)
├── src/
│   ├── producer/            # (Sprint 2)
│   └── consumer/            # (Sprint 2)
└── Makefile
```
