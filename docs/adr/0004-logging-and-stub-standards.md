# ADR 4: Standards for Observability (Logging) vs. Technical Debt (TODOs)

## Status
Accepted

## Context
In high-concurrency, regulated environments like GridStream, "silent" failures or untracked technical debt pose significant operational risks. 
1. **The Danger of `print()`:** In containerized EKS environments, `stdout` via `print()` is often unbuffered or improperly captured by log aggregators (CloudWatch/Fluentbit), leading to "lost" debug information during grid events. Furthermore, `print` lacks severity levels (INFO, WARN, ERROR), making automated alerting impossible.
2. **The Risk of "Silent" TODOs:** Undocumented `# TODO` comments often become permanent technical debt that is invisible to project management and only discovered during a system failure.

## Decision
1. **Prohibition of `print()`:** All diagnostic output must use the standard Python `logging` library.
2. **Contextual Logging:** Logs must be structured to include operational context (e.g., `device_id`, `schema_version`) to facilitate Distributed Tracing in Jaeger/OpenTelemetry.
3. **Structured Stubs:** Generic `# TODO` comments are prohibited in production-path code. Out-of-scope logic must be handled via **Structured Stubs**:
   - Use a `NotImplementedError` for code paths that should not be reached.
   - Include a docstring referencing the specific Sprint or Ticket ID (e.g., `[GRID-102]`).
   - Example: 
     ```python
     def validate_grid_frequency():
         # [GRID-102]: To be implemented in Sprint 5
         raise NotImplementedError("Frequency validation requires SCADA-API integration.")
     ```

## Consequences
*   **Positive:** Ensures 100% log capture in AWS CloudWatch, enabling proactive alerting on grid anomalies.
*   **Positive:** Transforms technical debt from "hidden comments" into "explicit failure points," preventing accidental execution of unfinished logic.
*   **Positive:** Simplifies an LLM's contribution by forcing it to provide either a working implementation or a clear, documented boundary.
*   **Negative:** Requires slightly more boilerplate code for initial implementation.