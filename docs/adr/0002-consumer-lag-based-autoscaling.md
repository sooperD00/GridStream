# ADR 2: Implement HPA Scaling via Kafka Consumer Lag

## Status
Accepted

## Context
GridCorp's workload is highly "bursty," triggered by grid events or weather changes. Standard Kubernetes Horizontal Pod Autoscalers (HPA) scale based on CPU or Memory. However, our Python-based ingestion services are I/O bound; their CPU remains low while the Kafka partition lag grows. In the energy sector, **stale data is dangerous data.**

## Decision
We will scale the `gridstream-consumer` deployment using the **Prometheus Adapter** to expose `kafka_consumer_group_lag` as a custom metric to the Kubernetes HPA controller.

## Consequences
*   **Positive:** Provides a "leading indicator" for scaling. The system adds replicas *as soon as* work piles up, not when the CPU happens to spike.
*   **Positive:** Ensures we meet our SLO for ingestion latency (< 500ms), which is critical for real-time grid balancing.
*   **Negative:** Requires the deployment and maintenance of Prometheus and the K8s Custom Metrics Adapter.