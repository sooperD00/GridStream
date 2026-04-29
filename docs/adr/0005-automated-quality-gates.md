# ADR 5: Automated Quality Gates & Linting Standards

## Status
Accepted

## Context
Manual code review is inconsistent and prone to human error, especially across distributed teams (US/Denmark). In a high-stakes grid environment, we cannot rely on "best efforts" to ensure code quality and schema compatibility.

## Decision
We will implement "Shift-Left" quality gates:
1. **Local Enforcement:** Developers must use `pre-commit` hooks to prevent non-compliant code from being pushed to the origin.
2. **Standardized Tooling:** We will use `Ruff` (Performance-focused Linter) and `MyPy` (Static Type Checking) as our "Automated Inspectors."
3. **Change Control Automation:** GitHub Actions will enforce that the PULL_REQUEST_TEMPLATE is filled out correctly before a merge is permitted.

## Consequences
*   **Positive:** Reduces "Technical Noise" in PR reviews, allowing the Principal Engineer to focus on logic rather than syntax.
*   **Positive:** Ensures a consistent "Manufacturing Standard" across the codebase.
*   **Negative:** Adds a small amount of friction to the initial developer setup.