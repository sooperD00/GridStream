# Contributing to GridStream

Welcome. This project prioritizes system stability, schema integrity, and observability. Please follow these guidelines to ensure our globally distributed teams maintain a high bar for engineering excellence.

## 🤝 Principles
*   **Contract-First:** Any change to data structures must begin with an Avro schema update.
*   **Observable by Default:** No logic reaches production without OpenTelemetry instrumentation.
*   **Automate Everything:** If you find yourself doing a manual task twice, it belongs in the `Makefile`.

## 🚀 Getting Started
1. **Local Environment:** We use `uv` for Python dependency management. Run `make setup` to initialize your venv.
2. **Branching:** Use `feature/` or `fix/` prefixes. All PRs require a green CI build.

## 🛠 Quality Standards
*   **Testing:** We aim for 80%+ coverage. Run `make test` before pushing.
*   **Linting:** We enforce `ruff` and `mypy` for type safety.
*   **Documentation:** Updates to core logic must be reflected in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## 🏗 Schema Changes
If you are modifying a `.avsc` file:
1. Ensure the change is **backward compatible**.
2. Run the compatibility checker: `make schema-check`.
3. Notify the #platform-standards Slack channel.