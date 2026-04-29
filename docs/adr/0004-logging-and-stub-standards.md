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
4. **Sprint Cleanup Markers:** Configuration comments and scaffolding code that exists *only because of a sprint's incomplete state* must be tagged  with a `[SPRINT-N-CLEANUP]` marker, where N is the sprint that resolves the obligation. Examples: lint exclusions for empty placeholder directories, stubbed CI steps with TODO targets, temporary `values.yaml` defaults that anticipate a not-yet-built feature. The marker is grep-able (`git grep "SPRINT-.-CLEANUP"`) and provides a definition-of-done check for each sprint: zero remaining markers for that sprint number before close.
   - Example:
    ```toml
        extend-exclude = [
            # [SPRINT-2-CLEANUP] Remove when producer/consumer/models packages
            # land with real source (per ADR-0010).
            "packages/producer",
        ]
    ```

## Consequences
*   **Positive:** Ensures 100% log capture in AWS CloudWatch, enabling proactive alerting on grid anomalies.
*   **Positive:** Transforms technical debt from "hidden comments" into "explicit failure points," preventing accidental execution of unfinished logic.
*   **Positive:** Simplifies an LLM's contribution by forcing it to provide either a working implementation or a clear, documented boundary.
*   **Positive:** Sprint close has a mechanical check (git grep for that sprint's cleanup markers) rather than a vibes-based 'did we tie up loose ends' question.
*   **Negative:** Requires slightly more boilerplate code for initial implementation.