# Architecture Design: Project GridStream

## 1. System Philosophy
GridStream is designed to solve the "Post-Acquisition Chaos" common in tech mergers. We prioritize **decoupling** and **contract enforcement** to allow legacy SCADA-heritage and consumer-platform-heritage systems to coexist while moving toward a unified data platform.

## 2. Component Diagram



### 2.1 Ingestion Layer (The "Producers")
*   **SCADA Adapters (Industrial):** High-frequency, high-reliability streams. These require fixed-interval processing.
*   **IoT Bridge (Consumer):** High-volume, bursty traffic (e.g., millions of thermostats reacting to a weather event).
*   **Validation:** Every producer uses **Pydantic** models to cast raw data into a strictly typed Python object before it touches the network.

### 2.2 Orchestration Layer (The "Backbone")
*   **Kafka:** Acts as the persistent buffer. 
*   **Schema Registry:** The "Single Source of Truth." We utilize **Avro** to enforce schema compatibility.
    *   *Strategic Choice:* We use `BACKWARD_TRANSITIVE` compatibility to ensure new consumers can always read old data—crucial for replaying historical grid events for AI training.

### 2.3 Processing Layer (The "Consumers")
*   **Deployment:** Managed via **Helm** on Kubernetes.
*   **Resiliency Patterns:**
    *   **Dead Letter Queues (DLQ):** Prevents a single malformed packet from a faulty EV charger from stalling the entire ingestion partition.
    *   **Idempotency:** Consumers use a `msg_id` (derived from `device_id` + `timestamp`) to ensure that even if a pod restarts and re-processes a message, the grid state remains consistent.

---

## 3. The "Staff" Pillars

### 3.1 Standardization (The "Paved Road")
To manage globally distributed teams (USA, EU, and India), we provide a **Shared Helm Library**. 
*   Instead of each team writing their own Kubernetes YAML, they inherit a template that includes pre-configured **Liveness/Readiness probes**, **Resource Limits**, and **Security Contexts**.
*   This reduces "Configuration Drift" and ensures a Danish developer's service behaves identically to a US developer's service in production.

### 3.2 Observability & SLIs
We implement **OpenTelemetry** as the universal instrumentation layer. We track the following "Staff-level" metrics:
1.  **Ingestion Latency (SLI):** Time from device-emit to Kafka-commit.
2.  **Processing Lag (SLI):** The delta between Kafka High-Watermark and Consumer Offset.
3.  **Schema Violation Rate:** Monitoring the DLQ to identify faulty firmware rollouts before they impact the grid.

### 3.3 Scalability Strategy: Consumer Lag HPA
Standard HPA scales on CPU/Memory. In the energy sector, a service might be idle but have a massive backlog (e.g., during a grid "Demand Response" event). 
*   **Decision:** We use a `Custom Metrics API` to scale based on `kafka_consumergroup_lag`. If the lag exceeds 10,000 messages, Kubernetes spins up additional pods to "drain the swamp."

### 3.4 Automated Quality Gates
To minimize cognitive load and prevent "unforced errors," the platform enforces the following gates:
*   **Static Analysis (The Inspector):** Use `Ruff` and `MyPy` to enforce type safety and catch logical errors before they reach the human review stage.
*   **Schema Validation:** Automated CI checks to ensure no PR introduces a breaking Avro schema change (checked against the Glue/Confluent Schema Registry).
*   **PR Metadata Enforcement:** A GitHub Action that validates the PR header for "Safety Impact" and "Grid Impact" fields, preventing merges that bypass the Change Control process.

---

## 4. Security & Compliance (Regulated Context)
*   **Data at Rest:** All Kafka topics are encrypted using AES-256.
*   **Least Privilege:** Kubernetes ServiceAccounts are restricted using RBAC to only read/write to their specific namespaces and topics.
*   **Audit Trail:** Every message schema change in the Registry is versioned and attributed to a specific CI/CD deployment.

---

## 5. Potential Failure Modes & Mitigations
| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Schema Mismatch** | Consumer Crash | Schema Registry enforcement + CI-integrated `avro-lint`. |
| **Kafka Outage** | Data Loss | Producer-side buffering (Circuit Breaker) + Persistent Volumes. |
| **Traffic Spike** | System Saturation | HPA based on Consumer Lag + Priority-based rate limiting. |

---

## 6. Safety-Critical Design & Failure Modes

### 6.1 Ethical Load Management (The "Wet Bulb" Protocol)
GridCorp's role in grid stability involves high-stakes trade-offs. The platform must distinguish between "discretionary" load (e.g., a pool pump) and "life-sustaining" load (e.g., medical equipment or cooling during extreme heat).

*   **Critical Asset Tagging:** Our Pydantic data models include a `priority_level` attribute derived from the Utility’s Customer Information System (CIS). 
*   **Safety Interlocks:** The ingestion engine is designed with "Fail-Open" logic. If the platform loses connectivity or cannot guarantee a safe dispatch state during a heatwave (defined by local weather API integration), it is programmed to default to "Grid-Follow" mode rather than "Aggressive Load Shed."

### 6.2 Fail-Safe State Management
In SCADA and IoT, "No Data" can be more dangerous than "Bad Data."
*   **State Persistence:** We use Redis to cache the "Last Known Good State" of the grid. If the Kafka pipeline experiences a latency spike (Lag > Threshold), the system triggers a **Safety Freeze**, preventing any new "Off" commands from being sent to devices until the observability gap is closed.
*   **Human-in-the-Loop (HITL):** For high-impact SCADA switches, the platform serves as a recommendation engine requiring manual operator sign-off, whereas low-risk consumer IoT is fully automated.

### 6.3 Resilience vs. Efficiency
| Scenario | Platform Action | Safety Justification |
| :--- | :--- | :--- |
| **High Wet-Bulb Temp** | Suspend Demand Response | Preventing heat-stroke in vulnerable populations overrides grid-saving credits. |
| **Hospital Circuit Detected** | Hard-Exclusion | Automated tagging prevents the platform from ever requesting a load-drop on registered life-safety circuits. |
| **Telemetry Loss** | Stop Automation | We cannot control what we cannot see. The system defaults to the safest physical state. |