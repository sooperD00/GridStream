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
> note: The 80% floor is calibrated as "high enough to catch most regressions, low enough that contributors aren't gaming coverage by writing tests against trivial getters" and is a backstop, not a target. Coverage measures *exercised* code, not *correct* code — a 95% covered codebase with shallow tests is worse than an 80% covered codebase with tests that assert behavior. Aim for the latter. Calibration is in the range Google's testing team describes as "acceptable" (60%) to "commendable" (75%); we picked the upper end of that band as our standard. See [References](#references) below.
*   **Linting:** We enforce `ruff` and `mypy` for type safety.
*   **Lockfile hygiene:** CI runs `uv sync --frozen` and will fail if `uv.lock` is stale relative to `pyproject.toml`. If you edit dependencies, run `uv sync` locally and commit the regenerated `uv.lock` alongside your `pyproject.toml` change. CI's error message (`The lockfile at uv.lock needs to be updated...`) means exactly this — not a CI bug.
*   **Documentation:** Updates to core logic must be reflected in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## 🏗 Schema Changes
If you are modifying a `.avsc` file:
1. Ensure the change is **backward compatible**.
2. Run the compatibility checker: `make schema-check`.
3. Notify the #platform-standards Slack channel.

### Tool version pinning

Tool versions shared between CI and Dockerfiles are pinned to a `major.minor`
floor — e.g. `uv@0.11`, not `uv@0.11.8`. This allows automatic patch updates
(security and bugfix releases) without manual bumps, while breaking-version
moves remain explicit PRs that touch this floor and the lockfile in the same
diff.

The same floor string appears in both `version:` inputs to GitHub Actions
(`astral-sh/setup-uv@... { version: "0.11" }`) and `:major.minor` Docker
image tags (`COPY --from=ghcr.io/astral-sh/uv:0.11 ...`), so CI and local
builds resolve to the same family on every run. Drift between the two is
the failure mode this convention is designed to prevent.

---

## References

- Arguelles, C., Ivanković, M., and Bender, A. ["Code Coverage Best
  Practices."](https://testing.googleblog.com/2020/08/code-coverage-best-practices.html)
  Google Testing Blog, August 7, 2020. — Source for the 60%/75%/90%
  coverage guideline tiers and the "exercised vs. correct" framing.
