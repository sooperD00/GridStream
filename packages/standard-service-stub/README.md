# standard-service-stub

A standard-service-stub is a "Hello World" pattern for services. It exists so that
the service can be exercised from end-to-end, but strips out any details (domain
logic), leaving only the minimum viable consumer. Best practice is to build with
this stub first, and to re-run with this stub on any change.

## What this one does

This standard-service-stub (Sprint 1) proves that
[`charts/standard-service/`](../../charts/standard-service/) and
[`.github/workflows/standard-python-service.yml`](../../.github/workflows/standard-python-service.yml)
function end-to-end.

Three simple endpoints accomplish this goal:

| Endpoint | Purpose |
| --- | --- |
| `GET /healthz` | Liveness probe. 200 means "process alive — don't restart me." |
| `GET /readyz` | Readiness probe. 200 means "ready for traffic." |
| `POST /echo` | Round-trips a Pydantic v2 message. Proves the request/response pipeline. |

## What this stub is *not*

The reference service (Sprint 2) is different. It lives alongside this stub as
separate workspace members — producer, consumer, models. It was shaped after the
stub (same layout, Dockerfile pair, pyproject.toml scaffolding) but is an
independent peer (it does not `import` from the stub). The stub stays here as the
minimum viable consumer of this platform — it should be re-run on every chart
change to catch regressions before the services with real domain concerns see
them. That way, if a real service ever needs chart customizations to adopt cleanly,
the chart was under-parameterized and gets fixed, not forked.

## Local dev

From the repo root:

```bash
make setup                              # uv sync + pre-commit install
uv run standard-service-stub            # serves on :8000
# in another shell
curl http://localhost:8000/healthz
curl -X POST http://localhost:8000/echo -H 'content-type: application/json' \
    -d '{"message": "hello"}'
```

Or in a container:

```bash
make build       # distroless production image (ADR-0009)
make build-dev   # slim image for shell-based local poking — NOT FOR PRODUCTION
```

## Layout

```
.
├── Dockerfile          # distroless production image (ADR-0009)
├── Dockerfile.dev      # slim image for local poking only
├── pyproject.toml      # member declaration; workspace root coordinates
├── src/
│   └── standard_service_stub/
│       ├── __init__.py
│       ├── __main__.py
│       ├── main.py     # FastAPI app + lifespan + run()
│       └── models.py   # Pydantic v2 request/response shapes
└── tests/              # smoke surface for the workflow's pytest+coverage gate
```
