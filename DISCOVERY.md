# Project GridStream: Unified Energy Ingestion Platform
**Simulation Scenario for GridCorp (Uplight-Style Integration)**

## 1. Project Context
Following the acquisition of multiple utility-tech entities, GridCorp requires a standardized, scalable ingestion platform. This project demonstrates a Staff-level approach to integrating high-frequency SCADA data (Industrial) and low-latency IoT telemetry (Consumer) into a unified, observable pipeline.

### Core Objectives
*   **Standardization:** Enforce data contracts across globally distributed teams using Avro and Schema Registry.
*   **Reliability:** Implement resilient Kubernetes patterns (HPA, Probes, DLQs).
*   **Observability:** Standardize cross-team visibility using OpenTelemetry and Prometheus.
*   **DevOps Excellence:** Move from manual deployments to a "GitOps-ready" Helm-based workflow.

---

## 2. Architecture Overview
The system consists of a Python-based **Synthetic Producer**, a **Kafka Backbone** for message orchestration, and a **Containerized Consumer** managed by Kubernetes.



### Technical Stack
*   **Language:** Python 3.11+ (Pydantic, `confluent-kafka`, `uv`)
*   **Stream:** Kafka, Confluent Schema Registry (Avro)
*   **Orchestration:** Kubernetes (Local: Kind/Minikube)
*   **Automation:** Helm, Makefile, GitHub Actions (simulated)
*   **Observability:** OpenTelemetry (OTel), Prometheus, Grafana

---

## 3. Implementation Roadmap (20-Hour Sprint)

### Phase 1: The Data Contract (Hours 1-5)
*   **Task 1.1:** Design an Avro schema (`power_reading.avsc`) that balances SCADA requirements (timestamp, voltage, frequency) with IoT requirements (device_id, firmware_version).
*   **Task 1.2:** Build a Python "Producer" using **Pydantic** to validate local CSV data (from NREL/Pecan Street) before serializing it to Avro.
*   **Staff Focus:** Implement a **Circuit Breaker** pattern—if Kafka is unreachable, the producer should buffer or fail gracefully rather than crashing.

### Phase 2: The Stream Backbone (Hours 6-10)
*   **Task 2.1:** Deploy a local Kafka + Schema Registry stack using Docker Compose.
*   **Task 2.2:** Implement a **Dead Letter Queue (DLQ)**. Messages that fail schema validation or business logic processing are routed to a `GridStream.failed` topic.
*   **Staff Focus:** Schema Evolution. Perform a "Live Upgrade" where you add a field to the schema and ensure the consumer doesn't break (Backward Compatibility).

### Phase 3: The Platform & GitOps (Hours 11-16)
*   **Task 3.1:** Containerize the Consumer. Create a multi-stage Dockerfile optimized for size and security.
*   **Task 3.2:** Develop a **Helm Chart** for the consumer. Parameterize resource limits, environment variables, and replicas.
*   **Task 3.3:** Configure **Liveness and Readiness Probes** that actually check Kafka connectivity.
*   **Staff Focus:** Horizontal Pod Autoscaling (HPA). Configure the consumer to scale up based on **Kafka Consumer Lag** rather than just CPU usage.

### Phase 4: Observability & Standardization (Hours 17-20)
*   **Task 4.1:** Instrument the Python consumer with **OpenTelemetry**. Capture traces for every message processed and export metrics to Prometheus.
*   **Task 4.2:** Build a "Standardized Service Dashboard" in Grafana showing the **Golden Signals**: Latency, Traffic, Errors, and Saturation.
*   **Staff Focus:** Define an **SLO (Service Level Objective)** for ingestion latency (e.g., 99% of messages processed in < 500ms) and create an alert for it.

---

## 4. Defensible Design Decisions (Interview Talking Points)

| Decision | Staff-Level Reasoning |
| :--- | :--- |
| **Avro over JSON** | Reduces payload size for massive IoT volumes and enforces strict data contracts between Polish and US engineering teams. |
| **Helm Templates** | Provides a "paved road" for other teams. Instead of writing YAML, they just provide a `values.yaml` to the GridCorp standard chart. |
| **Consumer Lag HPA** | In energy grids, data freshness is critical. Scaling by CPU is a "lagging indicator"; scaling by lag is a "leading indicator" of grid state visibility. |
| **OpenTelemetry** | Ensures vendor neutrality. If GridCorp moves from Datadog to New Relic, the application code never has to change. |

---

## 5. Repository Structure
```text
.
├── .github/workflows/   # CI/CD Standardized Templates
├── charts/              # Helm Chart for GridStream Consumer
├── data/                # Sample Energy CSVs (Pecan Street/NREL)
├── scripts/             # Makefile for dev-flow automation
├── src/
│   ├── producer/        # Validation & Ingestion logic
│   └── consumer/        # Processing & OTel Instrumentation
├── schemas/             # Avro/Pydantic contract definitions
├── ARCHITECTURE.md      # Detailed system design
└── README.md            # Quickstart guide