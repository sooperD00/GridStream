# ADR 3: Fail-Open Logic for Critical Load Safety

## Status
Accepted

## Context
The platform automates Demand Response (DR) events that turn off non-essential loads. However, during extreme weather (e.g., high wet-bulb temperatures) or when dealing with critical assets (hospitals), an automated "Off" command can become a life-safety risk. Legacy systems often "fail-closed" (maintaining the last commanded state) when telemetry is lost.

## Decision
We will implement **"Fail-Open" safety interlocks** within the ingestion and dispatch logic. If the platform detects a "Safety Event" (e.g., heatwave threshold met or telemetry loss for a critical circuit), it will automatically suspend automated control and return devices to their default, customer-controlled state.

## Consequences
*   **Positive:** Prioritizes human life and asset safety over grid-saving efficiency.
*   **Positive:** Protects the company from massive liability and regulatory (NERC/FERC) violations.
*   **Negative:** May result in higher grid costs or missed decarbonization targets during a safety event.
*   **Negative:** Requires real-time integration with external weather and "Critical Customer" APIs.