# syntax=docker/dockerfile:1.7
#
# Production image for gridstream-standard-service-stub.
# Final stage is gcr.io/distroless/python3-debian12 per ADR-0009 —
# no shell, no package manager, no userland, just python + ca-certs + app.
#
# Build context MUST be the workspace root
# (`make build` cmd runs from gridstream repo root where pyproject.toml and uv.lock must exist):
#     docker build -f packages/standard-service-stub/Dockerfile -t … .

# Default for standalone `docker build`. `make build` overrides from .python-version
# (the canonical source). Must stay in sync with the distroless image's Python
# version below — a venv built on 3.X won't run on a 3.Y runtime.
ARG PYTHON_VERSION=3.11

# ─── Build stage ─────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION}-slim-bookworm AS builder

# uv via the official distroless installer image (pinned by tag).
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /usr/local/bin/

# UV_COMPILE_BYTECODE=1       precompile .py→.pyc at build time so cold starts don't pay it
# UV_LINK_MODE=copy           cache mount lives on a different filesystem; uv's default
#                             is hardlinks, which don't cross filesystem boundaries
# UV_PYTHON_DOWNLOADS=never   refuse to download a Python interpreter; we picked the base
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /workspace

# Workspace metadata — copy first so dep resolution caches by manifest, not source.
COPY pyproject.toml uv.lock ./
COPY packages/standard-service-stub/pyproject.toml \
     packages/standard-service-stub/README.md \
     packages/standard-service-stub/

# Resolve and install this workspace member's deps. Two-step pattern: deps
# first, project second, so the (slow) deps layer stays Docker-cached when
# only source changes. Cache mount holds uv's downloaded-package cache across
# builds so we don't re-fetch wheels every time.
#   --frozen           require uv.lock (created by `make setup`)
#   --no-install-project   skip installing the project itself; next RUN does that
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --package gridstream-standard-service-stub \
            --frozen --no-dev --no-install-project

# Now copy source and install the project into the venv.
COPY packages/standard-service-stub/src packages/standard-service-stub/src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --package gridstream-standard-service-stub --frozen --no-dev



# ─── Final stage: distroless ─────────────────────────────────────────────────
FROM gcr.io/distroless/python3-debian12

# Re-declare to inherit the global ARG inside this stage.
ARG PYTHON_VERSION

WORKDIR /app

# Copy the resolved venv and source from the builder. The venv path here
# matches uv's workspace convention (.venv at workspace root).
COPY --from=builder --chown=nonroot:nonroot \
    /workspace/.venv /app/.venv
COPY --from=builder --chown=nonroot:nonroot \
    /workspace/packages/standard-service-stub/src /app/src

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH="/app/.venv/lib/python${PYTHON_VERSION}/site-packages:/app/src" \
    PYTHONUNBUFFERED=1 \
    PORT=8000

EXPOSE 8000

# nonroot is a distroless built-in (UID 65532). Pairs with the chart's
# securityContext: runAsNonRoot: true (gates pod start if this line is missing)
USER nonroot

# distroless has no shell — exec form only. Module form so it works
# regardless of console-script wiring.
ENTRYPOINT ["python", "-m", "standard_service_stub"]
