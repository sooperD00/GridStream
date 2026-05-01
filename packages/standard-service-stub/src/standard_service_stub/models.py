"""Pydantic v2 models for the stub service.

Kept deliberately minimal — just enough to prove the request/response
contract that adopting teams' models will follow. Sprint 2's reference
service exercises the full SCADA + IoT model surface (see
``schemas/power_reading.avsc`` and ``src/models/power_reading.py``); these
are a structured stand-in.
"""

from __future__ import annotations

from datetime import UTC, datetime

from pydantic import BaseModel, Field

SERVICE_NAME = "standard-service-stub"


class EchoRequest(BaseModel):
    """Inbound message to ``POST /echo``."""

    message: str = Field(
        ...,
        min_length=1,
        max_length=1024,
        description="Free-form text to mirror back. Empty strings are rejected.",
    )


class EchoResponse(BaseModel):
    """Outbound mirror of the request, plus server-side metadata.

    ``received_at`` is server-stamped, not client-trusted, so the workflow's
    pytest gate can assert the field exists without committing to its value.
    """

    message: str
    # Server-stamped (UTC). Producer-provided timestamps would be subject to
    # clock skew across writers; explicit server stamping is the SCADA-grade default.
    # default_factory takes a callable so the timestamp is fresh per instance —
    # a literal datetime.now() would freeze at module-import time.
    server_received_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    service: str = SERVICE_NAME


class HealthStatus(BaseModel):
    """Response shape for both ``/healthz`` and ``/readyz``.

    The two probes share a shape but mean different things; see ``main.py``
    for the liveness-vs-readiness commentary.

    No timestamp — keep it cheap for human curls.
    """

    status: str
    service: str = SERVICE_NAME
