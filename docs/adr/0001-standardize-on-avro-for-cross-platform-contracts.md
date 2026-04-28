# ADR 1: Standardize on Avro for Cross-Platform Data Contracts

## Status
Accepted

## Context
Following the merger of Uplight, AutoGrid, and Octopus Kraken, data is being produced by globally distributed teams in varying formats (JSON, Protobuf, and raw CSV). Inconsistent schemas are causing downstream consumer failures, and JSON payloads are incurring significant overhead at SCADA scale (millions of events per minute).

## Decision
We will standardize on **Apache Avro** for all asynchronous communication via Kafka. We will utilize a central **Confluent Schema Registry** to manage these contracts.

## Consequences
*   **Positive:** Enforces strict schema evolution (backward/forward compatibility), ensuring the Polish SCADA team doesn't break the US Analytics team's pipelines.
*   **Positive:** Significant reduction in network bandwidth and storage costs due to Avro's compact binary format.
*   **Negative:** Adds complexity to the local development environment (requires running a Schema Registry).
*   **Negative:** Slightly higher barrier to entry for teams used to "schema-less" JSON development.