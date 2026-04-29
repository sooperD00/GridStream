# System Context: GridStream Ingestion Platform

## 1. Business Landscape
GridStream is the foundational integration layer for **GridCorp**. Following the acquisition of three distinct energy-tech platforms (Legacy-Link, HomeSmart, and EuroGrid), the business requires a unified way to ingest, validate, and act upon distributed energy resource (DER) data.

**The Business — "Flex":** GridCorp's primary product line is **demand flexibility** — software that aggregates and dispatches Distributed Energy Resources (DERs: smart thermostats, EVs, batteries, solar+storage, heat pumps) to balance grid load in real time. This is the the DERMS-heritage platform plus consumer-facing demand-response programs. When the grid is stressed, the Flex platform decides which devices to nudge or directly control, at what magnitude, and reports the resulting load shift back to the utility partner.

**The Flex Teams:** Eleven engineering teams own pieces of this product line — five in North America, six in Pune. Each team owns one or more services that participate in the Flex pipeline (device telemetry ingestion, eligibility evaluation, dispatch decisioning, settlement reporting, customer-facing UI). Each team has historically built its own deployment surface. Standardizing across them — without halting feature work on the Flex roadmap — is the platform team's mandate.

**The Stakeholders:**
*   **Utility Partners:** Require 99.99% reliability for SCADA-grade telemetry; pay for grid-balancing outcomes.
*   **End Customers:** Receive thermostat nudges, EV-charging schedule adjustments, and bill-credit settlements. Trust degrades fast if device control feels arbitrary.
*   **Data Science:** Require immutable, schema-consistent historical data for load-forecasting and dispatch-optimization models.
*   **Grid Operators:** Require sub-second visibility into grid stress and dispatch capacity during peak demand events.
*   **Flex Application Teams (Internal):** Require a paved road that reduces time-to-deploy without imposing a single deployment style.
*   **Platform Team (this project):** Owns the road, not the traffic. Earns adoption rather than mandates it.

> **Note on simulation fidelity:** GridCorp is a fictional composite — a post-acquisition energy-tech company integrating a DERMS-heritage flexibility platform, a consumer-platform-heritage system, and a North American utility-programs business. The "Flex teams build the demand-flexibility product line" framing is the project's working assumption for the simulation, chosen because demand flexibility is the highest-leverage product surface in modern grid software. The architecture is robust to specifics; this project is a reference implementation, not a proposal for any particular organization.

## 2. Technical Constraints & Environment

### Target Environment (Production)
*   **Cloud Provider:** **Amazon Web Services (AWS)**.
*   **Orchestration:** **Amazon EKS (Elastic Kubernetes Service)**.
*   **Data Streaming:** Aiming for compatibility with **AWS MSK** (Managed Streaming for Apache Kafka) and **AWS Glue Schema Registry**.
*   **Continuous Delivery:** **ArgoCD** on EKS for pull-based GitOps.
*   **IaC:** **Terraform / OpenTofu** for all cloud resources.

### Development Environment (Sprints 1–4)
*   **Local Cluster:** **Kind** (Kubernetes-in-Docker).
*   **Local Streaming:** Self-hosted Kafka + Confluent Schema Registry via Docker Compose.
*   **Why local-first:** Every architectural decision in this project — Helm parameterization, GitOps sync, lag-based HPA, OpenTelemetry trace propagation, schema evolution, DLQ routing — can be exercised and demonstrated locally. AWS deployment is targeted but deferred to Sprint 5 so the AWS work doesn't compete with the architectural decisions for time. See [ADR-007](./adr/0007-iac-strategy-with-deferred-aws.md).

### Workload Characteristics
*   **Data Velocity:** 
    *   *Normal:* 2,000 events/sec.
    *   *Grid Event:* 20,000+ events/sec (10x burst).
*   **Regulatory Context:** Must adhere to NERC/CIP-style reliability mindsets; data integrity is a safety concern, not just a feature.
*   **Team Distribution:** Development is split between US (Product/Consumer IoT), Denmark (Platform/SCADA Integration), and India (Flex teams).

## 3. The "Staff" Mandate
The primary goal of this repository is to establish the **"Paved Road"**. This project is not just a feature; it is a **reference architecture** intended to:
1.  **Reduce Cognitive Load:** Standardize how teams move data from edge to cloud.
2.  **Enforce Safety:** Automate the "Fail-Open" protocols for critical loads.
3.  **Ensure Observability:** Eliminate "blind spots" in the distributed trace between the grid and the end-user device.
4.  **Earn Adoption:** Make the paved road *cheaper to use* than each team's bespoke deployment, so adoption is rational rather than mandated.

## 4. LLM Operational Guidelines
When generating code or suggestions for this project, the following priorities must be strictly observed:
1.  **AWS-Compatible Where Cheap:** Favor AWS-native integration patterns when they're equally easy locally (e.g., IRSA-style service accounts, environment-variable config). Defer AWS-specific work to Sprint 5.
2.  **Safety First:** Prioritize "Fail-Open" logic and data validation over pure performance.
3.  **Contract-First:** All data movement must be backed by the Avro schemas in `/schemas`.
4.  **Production-Ready:** Use modern Python (3.11+), static typing (`mypy`), and robust error handling.
5.  **Specific "TODO" and logging instructions**
    *   **Production Logic:** Avoid generic `# TODO` or `print()` statements. All logic must be "closed-loop"—if a failure point exists, it must be handled with a proper `logger.error` or a raised exception.
    *   **Structured Stubs:** If a feature is out of scope for the current sprint, use a "Structured Stub":
        *   Include a clear docstring explaining what is missing.
        *   Raise a `NotImplementedError` with a descriptive message.
        *   Example: `def rotate_credentials(): raise NotImplementedError("Pending AWS Secrets Manager integration in Sprint 5")`
    *   **Explicit Logging:** Use the standard Python `logging` library. Log messages must include context (e.g., `device_id`, `schema_version`) to ensure observability.
