# GridStream Execution Roadmap

This document outlines the phased implementation of the GridStream reference platform. Each sprint is designed to be a 4-5 hour block of high-intensity development.

---

## 🟢 Sprint 1: The Secure Contract (Hours 1-5)
**Goal:** Establish the data "Source of Truth" and local ingestion backbone.

### Tasks
- [ ] **Data Modeling:** Implement Pydantic models in `src/models/` using NREL/Pecan Street data attributes.
- [ ] **Schema Definition:** Create `schemas/power_reading.avsc` ensuring alignment with ADR-0001.
- [ ] **The Producer:** Build `producer.py` to stream CSV data into Kafka with Avro serialization.
- [ ] **Safety Check:** Implement basic Pydantic validation to catch "Zero-Voltage" or "Null-ID" anomalies before they hit the wire.

**Definition of Done:** A script that reads 1,000 rows of CSV data and successfully produces 1,000 Avro-encoded messages to a local Kafka topic.

---

## 🟡 Sprint 2: The Resilient Consumer (Hours 6-10)
**Goal:** Build the processing logic with built-in error handling and state awareness.

### Tasks
- [ ] **The Consumer:** Build `consumer.py` using `confluent-kafka` to read from the GridStream topic.
- [ ] **The DLQ Pattern:** Implement logic to route malformed or "Safety-Violating" messages to `gridstream.failed`.
- [ ] **Idempotency:** Implement a simple local state check (e.g., SQLite or Redis) to prevent duplicate processing of the same timestamp/device pair.
- [ ] **Safety Interlock:** Add logic to "Log a Safety Warning" if the telemetry indicates a Wet-Bulb temperature > 35°C.

**Definition of Done:** Consumer processes messages, handles a "poison pill" message without crashing, and routes errors to the DLQ.

---

## 🟠 Sprint 3: The Paved Road (Hours 11-15)
**Goal:** Transition from Docker-Compose to Kubernetes with Staff-level infrastructure patterns.

### Tasks
- [ ] **Containerization:** Write a multi-stage Dockerfile for the consumer (distroless or alpine for security).
- [ ] **Helm Charting:** Create the `charts/gridstream-consumer` template.
- [ ] **K8s Health:** Define Liveness/Readiness probes that check Kafka connectivity, not just the process.
- [ ] **Lag-Based HPA:** Configure the HPA manifest to target custom metrics (per ADR-0002).
- [ ] **Pre-commit Configuration:** Implement .pre-commit-config.yaml to run ruff and black on every local commit.
- [ ] **CI Pipeline:** Create .github/workflows/lint.yml to run these same checks in GitHub.
- [ ] **Metadata Linter:** Add a custom script (or use a GitHub Action) that fails the build if the PR description doesn't follow the template.

**Definition of Done:** Application is deployed to `kind`/`minikube` via `helm install` and successfully consumes messages from the K8s-internal Kafka. Change process is defined and enforced.

---

## 🔴 Sprint 4: The Observable Grid (Hours 16-20)
**Goal:** Standardize visibility and document the final system state.

### Tasks
- [ ] **Instrumentation:** Add OpenTelemetry SDK to the consumer to track `process_message` spans.
- [ ] **Dashboarding:** Create a basic Grafana dashboard (JSON) tracking Lag, Error Rate, and "Safety-Event" counts.
- [ ] **The "Staff" Audit:** Run a final pass on ADRs, update `ARCHITECTURE.md` with any implementation deviations, and close the final "Integration" PR.
- [ ] **Clean up:** Ensure the `Makefile` has a single `make help` command that works for a new developer.

**Definition of Done:** A Jaeger trace shows a message journey from Producer -> Kafka -> Consumer, and a Grafana chart displays real-time ingestion lag.

---

## 📝 Deferred Decisions / Future Scope
- **Production CI/CD:** Real GitHub Actions runners (simulated in this project via `make`).
- **Distributed State:** Migrating local idempotency checks to a distributed Redis cluster.
- **Hardware-in-the-loop (HIL):** Integration with actual smart-meter hardware.