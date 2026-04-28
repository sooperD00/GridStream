# System Context: GridStream Ingestion Platform

## 1. Business Landscape
GridStream is the foundational integration layer for **GridCorp**. Following the acquisition of three distinct energy-tech platforms (Legacy-Link, HomeSmart, and EuroGrid), the business requires a unified way to ingest, validate, and act upon distributed energy resource (DER) data.

**The Stakeholders:**
*   **Utility Partners:** Require 99.99% reliability for SCADA-grade telemetry.
*   **Data Science:** Require immutable, schema-consistent historical data for load-forecasting models.
*   **Grid Operators:** Require sub-second visibility into grid stress during peak demand.

## 2. Technical Constraints & Environment
*   **Cloud Provider:** **Amazon Web Services (AWS)**.
*   **Orchestration:** **Amazon EKS (Elastic Kubernetes Service)**.
*   **Data Streaming:** Aiming for compatibility with **AWS MSK** (Managed Streaming for Apache Kafka) and **AWS Glue Schema Registry**.
*   **Data Velocity:** 
    *   *Normal:* 2,000 events/sec.
    *   *Grid Event:* 20,000+ events/sec (10x burst).
*   **Regulatory Context:** Must adhere to NERC/CIP-style reliability mindsets; data integrity is a safety concern, not just a feature.
*   **Team Distribution:** Development is split between US (Product/Consumer IoT) and Poland (Platform/SCADA Integration).

## 3. The "Staff" Mandate
The primary goal of this repository is to establish the **"Paved Road"**. This project is not just a feature; it is a **reference architecture** intended to:
1.  **Reduce Cognitive Load:** Standardize how teams move data from edge to cloud.
2.  **Enforce Safety:** Automate the "Fail-Open" protocols for critical loads.
3.  **Ensure Observability:** Eliminate "blind spots" in the distributed trace between the grid and the end-user device.

## 4. LLM Operational Guidelines
When generating code or suggestions for this project, the following priorities must be strictly observed:
1.  **AWS Alignment:** Favor AWS-native integration patterns (e.g., IAM Roles for Service Accounts - IRSA).
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