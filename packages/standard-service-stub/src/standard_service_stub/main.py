"""FastAPI application for the standard-service stub.

Endpoints:
    GET  /healthz — liveness probe
    GET  /readyz  — readiness probe
    POST /echo    — round-trips a Pydantic-validated message

Logging follows ADR-004: standard ``logging`` library, never ``print()``,
every log line carries operational context. The distroless runtime
(ADR-0009) is the reason logs are the *only* debugging surface in
production — see ``docs/paved-road.md`` §"Debugging without a shell".
"""

from __future__ import annotations

import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

from standard_service_stub.models import (
    SERVICE_NAME,
    EchoRequest,
    EchoResponse,
    HealthStatus,
)

logger = logging.getLogger("standard_service_stub")


def _configure_logging() -> None:
    """Configure root logging once at startup. Honors ``LOG_LEVEL`` env var."""
    level = os.getenv("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Startup/shutdown hook. Logs lifecycle events with service context."""
    _configure_logging()
    logger.info("starting service service=%s", SERVICE_NAME)
    yield
    logger.info("stopping service service=%s", SERVICE_NAME)


app = FastAPI(
    title="GridStream Standard Service Stub",
    version="0.1.0",
    lifespan=lifespan,
    description=(
        "Paved-road exemplar service. Exists to prove the standard-service "
        "chart and the standard-python-service reusable workflow function "
        "end-to-end. See docs/paved-road.md."
    ),
)


@app.get("/healthz", response_model=HealthStatus, tags=["probes"])
async def healthz() -> HealthStatus:
    """Liveness probe.

    Returns 200 when the process is alive. A 5xx here tells Kubernetes
    to *restart the pod* — the process is wedged and can't be saved by
    waiting. Distinct from ``/readyz``: liveness failures are recovery
    actions, not traffic-routing decisions.
    """
    return HealthStatus(status="alive")


@app.get("/readyz", response_model=HealthStatus, tags=["probes"])
async def readyz() -> HealthStatus:
    """Readiness probe.

    Returns 200 when the service can accept traffic. A 5xx here tells
    Kubernetes to *stop sending traffic* (the pod stays alive — maybe a
    downstream dependency is briefly unavailable, or the service is still
    warming caches). The stub has no downstream dependencies so readiness
    collapses to liveness; Sprint 2's consumer will check Kafka and
    Schema Registry availability here.
    """
    return HealthStatus(status="ready")


@app.post("/echo", response_model=EchoResponse, tags=["demo"])
async def echo(req: EchoRequest) -> EchoResponse:
    """Mirror the request back with server-stamped metadata.

    Exists to prove (a) Pydantic v2 validation rejects malformed input
    with 422, (b) the workflow's pytest gate can exercise a real
    request/response pipeline rather than just probing health endpoints.
    """
    logger.info(
        "echo request received service=%s message_length=%d",
        SERVICE_NAME,
        len(req.message),
    )
    return EchoResponse(message=req.message)


def run() -> None:
    """Console entrypoint. Honors ``PORT`` and ``LOG_LEVEL`` env vars."""
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(
        "standard_service_stub.main:app",
        host="0.0.0.0",  # noqa: S104 — container-only; pod NetworkPolicy is the boundary.
        port=port,
        log_level=os.getenv("LOG_LEVEL", "info").lower(),
    )
