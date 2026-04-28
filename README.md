# Project GridStream ⚡

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Platform: K8s](https://img.shields.io/badge/platform-kubernetes-blue.svg)](https://kubernetes.io/)

**Project GridStream** is a reference implementation of a high-scale, resilient energy data ingestion platform. It was designed to address the integration challenges of **GridCorp** (a simulated entity representing the post-acquisition state of Uplight, AutoGrid, and Octopus Kraken).

The project demonstrates how to standardize globally distributed telemetry (SCADA & IoT) using **Kafka**, **Kubernetes**, and **OpenTelemetry**.

---

## 1. Problem Statement
GridCorp currently operates three disparate ingestion pipelines with inconsistent data formats, varying reliability standards, and siloed observability. 

**GridStream solves this by providing:**
*   **A Unified Schema:** Enforcing data contracts via Avro and a central Schema Registry.
*   **Infrastructure-as-Code:** Standardized Helm charts for rapid, consistent service deployment.
*   **Grid-Aware Scaling:** Horizontal Pod Autoscaling (HPA) driven by Kafka consumer lag rather than generic CPU metrics.
*   **Proactive Observability:** Native OpenTelemetry instrumentation for distributed tracing across cross-functional services.

---

## 2. Architecture

The system follows a "Standardized Ingestion" pattern:
1.  **Synthetic Producer:** A Python service that streams real-world energy data (NREL/Pecan Street) validated via Pydantic.
2.  **Schema Registry:** Ensures all messages adhere to versioned Avro contracts.
3.  **Kafka Backbone:** Decouples high-frequency telemetry from downstream processing.
4.  **Resilient Consumer:** A containerized Python service deployed via Helm, featuring circuit breakers and DLQ routing for malformed data.

---

## 3. Getting Started

### Prerequisites
*   **Python 3.11+** (managed via `uv` or `poetry`)
*   **Docker & Docker Compose**
*   **Kind** or **Minikube** (for K8s exercises)
*   **Helm 3.0+**

### Local Quickstart
1. **Clone and Initialize:**
   ```bash
   git clone [https://github.com/your-repo/GridStream.git](https://github.com/your-repo/GridStream.git)
   cd GridStream
   make setup  # Installs dependencies and pre-commit hooks
   ```
2. **Spin up Infrastructure:**

   ```bash
   make infra-up  # Starts Kafka, Schema Registry, and Prometheus/Grafana
   ```

3. **Run the Producer:**
   ```bash
   python src/producer/main.py --source data/sample_energy.csv
   ```

4. **Staff Engineer Highlights (The "Why")**

   **🛡️ Data Contracts & Evolution**

   We use Avro over JSON to ensure binary efficiency and strict backward compatibility. This prevents a deployment in the Poland-based SCADA team from breaking the US-based analytics dashboard.

   **📈 Scaling on Lead Indicators**

   Unlike standard HPA which is a proportional-only feedback controller, GridStream uses the prometheus-adapter to scale pods based on Consumer Lag. In an energy grid context, processing delay (lag) is a critical failure mode that CPU usage would fail to capture.

   **🚦 Error Handling (The DLQ Pattern)**

   Faulty IoT device firmware often sends malformed telemetry. Instead of blocking the partition, VoltStream uses a Dead Letter Queue (DLQ) pattern to shunt "poison pills" into a separate topic for offline inspection.

   **🕸️ OpenTelemetry Integration**

   The platform implements a "Standardized Trace Context." Every message carries trace headers, allowing us to visualize the journey of a single "Load Shift" command from the API through the grid controller.

5. **Project Roadmap (20-Hour Sprint)**
- [ ] **Phase 1:** Core Producer/Consumer with Pydantic & Avro validation.
- [ ] **Phase 2:** Local K8s deployment with Readiness/Liveness probes.
- [ ] **Phase 3:** Helm chart parameterization and CI/CD workflow simulation.
- [ ] **Phase 4:** OTel instrumentation and Grafana SLO dashboards.

6. **Repository Structure**
- `/charts`: The "Paved Road" Helm template for all GridCorp services.
- `/src`: Python source code (Producer/Consumer).
- `/schemas`: Centralized Avro .avsc definitions.
- `/scripts`: Automation wrappers (Makefiles).
- `ARCHITECTURE.md`: Deep dive into SCADA vs. IoT integration patterns.

7. **Contact**
**Architect:** N.L. Rowsey | Platform Engineer | Distributed Systems | Python | PhD EE | [github.com/sooperD00](https://github.com/sooperD00)
**Project Status:** Active Simulation / Interview Preparation