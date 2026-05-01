"""Tests for the standard-service stub.

These tests exist as the smoke surface for the standard-python-service
reusable workflow's pytest+coverage gate. Without them, the 80% coverage
threshold is theatrical and the green-CI Definition of Done item proves
nothing about the workflow itself. They are deliberately minimal — exercising
endpoints, validation, and request/response shape — and stay in place
permanently as the smoke test the workflow re-runs on every change.

Sprint 2 adds domain-driven tests in the producer, consumer, and models
packages; they are peers to these tests, not replacements.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from standard_service_stub.main import app


def test_healthz_returns_200_with_alive_status() -> None:
    """Liveness probe responds with 200 and reports the service alive."""
    with TestClient(app) as client:  # trigger FastAPI lifespan startup and shutdown
        response = client.get("/healthz")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "alive"
    assert body["service"] == "standard-service-stub"


def test_readyz_returns_200_with_ready_status() -> None:
    """Readiness probe responds with 200 and reports the service ready."""
    with TestClient(app) as client:
        response = client.get("/readyz")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["service"] == "standard-service-stub"


def test_echo_round_trips_message_with_metadata() -> None:
    """POST /echo mirrors the message and stamps server-side metadata."""
    with TestClient(app) as client:
        response = client.post("/echo", json={"message": "ping"})
    assert response.status_code == 200
    body = response.json()
    assert body["message"] == "ping"
    assert body["service"] == "standard-service-stub"
    assert "received_at" in body  # server-stamped; we don't pin its value


def test_echo_rejects_empty_message_with_422() -> None:
    """Pydantic v2 validation rejects empty strings — proves the gate is real.

    422 (Unprocessable Entity) is FastAPI's contract for Pydantic validation
    failures, distinct from 400 (general bad request).
    """
    with TestClient(app) as client:
        response = client.post("/echo", json={"message": ""})
    assert response.status_code == 422
