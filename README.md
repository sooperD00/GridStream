# Project GridStream ⚡

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Platform: K8s](https://img.shields.io/badge/platform-kubernetes-blue.svg)](https://kubernetes.io/)

**Project GridStream** is a reference implementation of the **paved-road pattern** for a globally distributed engineering organization. It demonstrates the standards — parameterized Helm, reusable CI workflows, observability defaults, change-control templates, GitOps-ready deployment — that a platform team would roll out to 5+ application teams to enable continuous, defensible, customer-aligned delivery.

The paved road is exercised by a single reference service: a high-volume energy ingestion pipeline. That service was chosen because it stresses every standardization axis at once — cross-region teams, schema evolution across producer/consumer boundaries, regulated SCADA-grade reliability, and bursty load. The reference service is the *seed example*. The value of *this* project is the paved-road pattern implemented as a platform.

The simulated context is **GridCorp**: a post-acquisition integration of three legacy energy-tech platforms with engineering teams distributed across the US, Denmark, and India running disparate ingestion pipelines and disparate deployment styles.

For the system design, see [Architecture](./docs/ARCHITECTURE.md) and the [ADR record](./docs/adr/).

---

## 1. Problem Statement

Three legacy platforms, three deployment styles, no shared observability. Teams "deploy how they want to meet customer needs," and engineering teams cannot honestly answer "yes" to two basic questions:

1. **Do we deploy the way clients want us to?**
2. **Can we ship faster?**

The platform's job is to make "yes" reachable — without halting feature work to get there.

GridStream addresses this on three fronts:

- **The Paved Road.** A shared Helm chart and reusable GitHub Actions workflow that any team can adopt to inherit standardized probes, resource defaults, security context, lint/type/test gates, and signed container builds.
- **The Reference Service.** A working production-grade service that uses the paved road, demonstrating the pattern end-to-end with real data contracts and real failure handling.
- **The Migration Narrative.** A defensible, incremental adoption path that earns trust per team rather than mandating a big-bang switch.

---

## 2. Architecture

The reference service follows a "Standardized Ingestion" pattern:

1. **Synthetic Producer.** Python service streaming real-world energy data (NREL/Pecan Street) validated via Pydantic.
2. **Schema Registry.** Versioned Avro contracts with backward-compatibility enforcement.
3. **Kafka Backbone.** Decouples high-frequency telemetry from downstream processing.
4. **Resilient Consumer.** Containerized Python service deployed via the paved-road Helm chart, featuring circuit breakers and DLQ routing.

All four components are *users* of the paved-road artifacts. Nothing about the reference service requires special-case deployment logic — that's the point.

---

## 3. Sprint Roadmap

Each sprint produces a coherent artifact. Stop after any sprint and the result is reference-quality on its own terms.

| Sprint | Focus | Cut-off Artifact |
|---|---|---|
| **🟢 Sprint 1** | The Paved Road | Shared Helm chart, reusable GHA workflow, service stub. *Stop here = paved road exists.* |
| **🟡 Sprint 2** | The Reference Service | Producer/consumer with Avro/DLQ deployed via Sprint 1's paved road. *Stop here = paved road proven.* |
| **🟠 Sprint 3** | GitOps + Observability | ArgoCD, OpenTelemetry, Prometheus/Grafana, lag-based HPA, SLOs. *Stop here = full technical story.* |
| **🔴 Sprint 4** | The Migration Narrative | ADR record finalized, 5-team adoption playbook, scaffold-a-service script. *Stop here = adoption-ready.* |
| **⚪ Sprint 5 (deferred)** | AWS Deployment | Terraform module for EKS, IRSA, MSK + Glue Schema Registry. *Reference enrichment.* |

Sprint 5 is intentionally deferred. Local Kind/Docker Compose exercises every architectural argument the project needs to make; AWS deployment adds operational complexity without strengthening the technical story. Sprint 5 is reference enrichment scheduled separately from the project's primary sprint window, so the AWS work doesn't compete with the architectural decisions for time. (See [ADR-007](./docs/adr/0007-iac-strategy-with-deferred-aws.md).)

---

## 4. Architectural Highlights (The "Why")

**🛣 The Paved Road, Not the Mandate**

Adoption is voluntary and incremental. Teams keep their existing repos and migrate one piece at a time: first a `Makefile`, then the shared CI workflow, then the Helm chart, then ArgoCD-managed deployment. Each step earns trust for the next. (See [ADR-006: GitOps Adoption Path](./docs/adr/0006-gitops-adoption-path.md).)

**🛡 Data Contracts & Evolution**

Avro over JSON for binary efficiency and strict backward compatibility. A change in the Denmark SCADA team's producer cannot silently break the US analytics consumer. (See [ADR-001](./docs/adr/0001-standardize-on-avro-for-cross-platform-contracts.md).)

**📈 Scaling on Lead Indicators**

Standard HPA scales reactively on CPU. GridStream scales on Kafka consumer lag — a leading indicator that surfaces backpressure *before* queue depth becomes a customer problem. (See [ADR-002](./docs/adr/0002-consumer-lag-based-autoscaling.md).)

**🚦 Error Handling (The DLQ Pattern)**

Faulty IoT firmware can emit malformed telemetry indefinitely. Instead of blocking the partition, GridStream shunts "poison pills" to a Dead Letter Queue for offline inspection — single-message failures don't become pipeline outages.

**🕸 OpenTelemetry as the Standard**

Vendor-neutral instrumentation. Teams can ship traces, metrics, and logs to whatever backend the org standardizes on; the application code never has to change.

**🔒 Safety-Critical Defaults**

Wet-bulb fail-open interlocks, critical-asset tagging, and human-in-the-loop gates for high-impact SCADA actions. *No data* is treated as more dangerous than *bad data*. (See [ADR-003](./docs/adr/0003-fail-open-safety-interlocks.md).)

---

## 5. Local Development

> **Status:** Sprint 1 in progress. Commands below are the *target* state and will be live as sprints land.

### Prerequisites
- Python 3.11+ (managed via `uv` or `poetry`)
- Docker & Docker Compose
- Kind or Minikube
- Helm 3.0+

### Quickstart (post-Sprint 1)
```bash
make setup        # Install deps and pre-commit hooks
make infra-up     # Start Kafka, Schema Registry, Prometheus/Grafana via Docker Compose
make deploy-local # Helm-install the reference service into Kind
```

---

## 6. Repository Structure

```
.
├── .github/
│   ├── workflows/        # Reusable CI workflow templates (Sprint 1)
│   ├── CODEOWNERS
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── ISSUE_TEMPLATE/
├── charts/               # Paved-road Helm chart (Sprint 1)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONTEXT.md
│   ├── CONTRIBUTING.md
│   ├── DISCOVERY.md
│   ├── adr/              # Architectural Decision Records
│   └── remaining_sprints.md
├── infra/
│   └── terraform/        # AWS modules (Sprint 5, stubbed)
├── schemas/              # Avro contracts (Sprint 2)
├── src/
│   ├── producer/         # (Sprint 2)
│   └── consumer/         # (Sprint 2)
├── data/                 # Sample energy CSVs
├── scripts/              # scaffold-a-service, etc. (Sprint 4)
└── Makefile
```

---

## 7. Contact

**Author:** N.L. Rowsey · Platform Engineer · Distributed Systems · Python · PhD EE · [github.com/sooperD00](https://github.com/sooperD00)

**Project Status:** Active development.
