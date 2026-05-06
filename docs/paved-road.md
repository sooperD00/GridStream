# Adopting the GridStream Paved Road

> *A ten-minute tutorial. Read this; come out the other side with a service
> that builds in CI, deploys via Helm, and inherits GridStream's defaults
> for security, probes, and labels.*

The paved road is what GridStream's platform team offers to any application
team that wants standardized deployment without inventing it themselves. It
is **opt-in** and **incremental** — the four stages from
[ADR-0006](./adr/0006-gitops-adoption-path.md) are designed so each one
delivers value on its own, and a team can pause between any two of them
without losing what they already gained.

This tutorial walks Stages 1 through 3. Stage 4 (ArgoCD) lands in Sprint 3.
[SPRINT-3-CLEANUP]

---

## What you get

| Stage | What you adopt | Time | What you gain |
| --- | --- | --- | --- |
| 1 | A standardized `Makefile` | ~2 hrs | One command to build/test/deploy. Deploy commands stop being tribal knowledge. |
| 2 | The reusable CI workflow | ~3 hrs | Lint, type-check, test, container build — all standardized, all updated centrally. |
| 3 | The `standard-service` Helm chart | ~1 day | K8s deployment with paved-road defaults. Probes, security context, labels: solved. |
| 4 | ArgoCD `Application` manifest | ~1 day | Pull-based GitOps. Cluster state matches Git. *Sprint 3.* [SPRINT-3-CLEANUP] |

---

## The 10-minute version

```bash
# 0. Prerequisites
#    Python 3.11+, Docker, kind, helm 3, uv (https://docs.astral.sh/uv/)

# 1. Clone, set up, run
git clone https://github.com/sooperD00/gridstream.git
cd gridstream
make setup
make infra-up
make deploy-local

# 2. Hit the deployed stub
kubectl port-forward svc/standard-service-stub 8000:80 &
curl http://localhost:8000/healthz
curl -X POST http://localhost:8000/echo \
    -H 'content-type: application/json' \
    -d '{"message": "first traveler"}'
```

If those curls return 200, the paved road works.

Or skip the manual curls and run `make smoke-test` — same endpoints, plus
an ADR-0004 log-shape check, exits non-zero on any failure (so CI can gate
on it later).

Now read the rest of this document to understand *what* you're inheriting
and *how to adopt it for your own service*.

---

## Stage 1 — The Makefile

Every paved-road repo gets the same target names. Adopters copy the
`Makefile` from this repo, adjust the `STUB_*` variables to their service
name, and they're done. The named targets:

| Target | What it does |
| --- | --- |
| `make setup` | `uv sync` + install pre-commit hooks |
| `make lint` | Ruff check + format check |
| `make typecheck` | Mypy strict |
| `make test` | Pytest with the 80% coverage gate |
| `make build` | Distroless production container ([ADR-0009](./adr/0009-container-base-image.md)) |
| `make build-dev` | Slim local-dev container — **not for production** |
| `make infra-up` / `make infra-down` | Local Kind cluster lifecycle |
| `make deploy-local` | Build, kind-load, helm-install |
| `make help` | The list you're reading |

The point isn't the targets themselves — it's that *every paved-road repo
has the same ones*. A platform engineer onboarding a new team doesn't have
to learn that team's bespoke deploy script. The friction of cross-team
context-switching collapses.

---

## Stage 2 — The reusable CI workflow

The shared workflow lives at
[`.github/workflows/standard-python-service.yml`](../.github/workflows/standard-python-service.yml)
in this repo. Adopters call it from their own CI:

```yaml
# .github/workflows/ci.yml in your repo
name: CI
on: [push, pull_request]

jobs:
  ci:
    uses: sooperD00/gridstream/.github/workflows/standard-python-service.yml@v1
    with:
      image-name: my-team-service
```

That's it. The workflow does:

1. `uv sync` — install workspace deps (or your single-project deps).
2. `ruff check` and `ruff format --check`.
3. `mypy src`.
4. `pytest tests` with `--cov-fail-under=80`.
5. `docker buildx build` — container build (no push yet; see the registry-push
   TODO in the workflow file and [ADR-0006](./adr/0006-gitops-adoption-path.md)
   for why push lands in Sprint 4 or 5).

Inputs you can override:

| Input | Default | When to set |
| --- | --- | --- |
| `python-version` | `"3.11"` | If you've moved to 3.12+. |
| `coverage-threshold` | `80` | Almost never — argue for the change at platform review. |
| `image-name` | (required) | Always. |
| `working-directory` | `"."` | If your service isn't at repo root. |
| `dockerfile-context` / `dockerfile-path` | (default to working-directory) | Workspace-aware builds. Most adopters don't need these. |

When the platform team upgrades the workflow (adds a new lint, tightens a
config, fixes a bug), every adopter's next CI run picks it up. The whole
point of `uses:` versus copy-paste.

---

## Stage 3 — The `standard-service` chart

The chart at [`charts/standard-service/`](../charts/standard-service/)
parameterizes deployment of a Python HTTP service. Read the chart's
[README](../charts/standard-service/README.md) for the values contract;
the short version:

```yaml
# values-myservice.yaml
app:
  name: my-service
image:
  repository: ghcr.io/myorg/my-service
  tag: "1.4.2"
config:
  LOG_LEVEL: INFO
deployment:
  replicas: 3
resources:
  requests: { cpu: 200m, memory: 256Mi }
  limits:   { cpu: 1000m, memory: 1Gi }
```

```bash
helm upgrade --install my-service oci://ghcr.io/sooperD00/charts/standard-service \
    --version 0.1.0 \
    -f values-myservice.yaml
```

What you inherit without configuring:

- Liveness `/healthz` and readiness `/readyz` probes — your service implements
  these endpoints; the chart wires the probes.
- Pod-level security context (`runAsNonRoot`, `nonroot` UID, `RuntimeDefault`
  seccomp).
- Container-level security context (`readOnlyRootFilesystem`, all caps
  dropped, no privilege escalation).
- `app.kubernetes.io/*` labels including `part-of: gridstream`. Observability
  selectors and ArgoCD selectors will rely on these in Sprint 3.

What you don't get yet, with sprint pointers:

- HPA — Sprint 3, lag-based per [ADR-0002](./adr/0002-consumer-lag-based-autoscaling.md).
- Ingress — Sprint 3.
- ServiceAccount with IRSA — Sprint 5.
- Job/CronJob template — added in Sprint 2 if needed.

---

## Debugging without a shell

The production container is distroless ([ADR-0009](./adr/0009-container-base-image.md)).
That means **`kubectl exec -it <pod> -- sh` does not work** — there is no
shell in the image. This is deliberate: the image is hardened against an
entire class of attack, and the absence of an exec path forces investment
in observability instead of `tail -f`-driven debugging.

Here are the debugging affordances that *do* work, in roughly the order
you'll reach for them.

### 1. Logs — your primary debugging surface

```bash
# Live logs from the pod's running container:
kubectl logs -f deploy/my-service

# Logs from the pod that just crashed and got replaced:
kubectl logs deploy/my-service --previous

# Logs from a specific container in a multi-container pod:
kubectl logs <pod> -c <container>
```

Logs follow [ADR-0004](./adr/0004-logging-and-stub-standards.md) — every line
is structured Python `logging` output with operational context (`device_id`,
`schema_version`, etc.). No `print()`, no unbuffered stdout, every level
filterable.

### 2. `kubectl describe` — the pod's autobiography

```bash
kubectl describe pod <pod-name>
```

Shows the events leading up to the current state: image pulls, probe
failures, OOM kills, scheduling waits. When a pod is in `CrashLoopBackOff`,
this is where you find the *why*. The events surface failures the logs
might not — e.g. the container's process never started because the image
couldn't pull.

### 3. `kubectl debug` — ephemeral debug containers

When you need shell-shaped tools against a running pod (without baking
them into the production image), attach an ephemeral debug container:

```bash
# Drop a busybox sidecar sharing the target container's process namespace:
kubectl debug -it <pod> --image=busybox --target=<container>

# Or use a debug image that mirrors your app's environment:
kubectl debug -it <pod> --image=python:3.11-slim --target=<container> -- bash
```

The ephemeral container is destroyed when you exit. The production image
stays clean. This is the right tool for "I need to inspect the network
namespace from inside the pod" or "I need to verify the mounted ConfigMap
contents from the container's perspective."

### 4. Sprint 3 — observability stack

When Sprint 3 lands, the debugging surface widens:

- **Jaeger** — distributed traces from producer → Kafka → consumer. Track a
  message through the whole pipeline by trace ID.
- **Grafana** — golden-signals dashboard (latency, traffic, errors,
  saturation) per service.
- **Prometheus** — raw metrics, ad-hoc queries, alert rule evaluation.
- **OpenTelemetry collector** — sidecar in the chart, ships traces and
  metrics without per-team code changes.

The pattern is: *logs tell you what happened, traces tell you what's slow,
metrics tell you what's broken.* No shell needed for any of them.

### Migration tip

If your team is currently doing exec-based debugging, the transition isn't
a flag-day rewrite. The local-dev image (`Dockerfile.dev`) keeps the slim
base with shell — use it locally during the transition while you build
fluency with `kubectl logs` and `kubectl debug`. The production image
goes distroless from the start.

---

## This repo's layout vs. yours

[ADR-0010](./adr/0010-multi-package-layout-with-uv-workspaces.md) chose
**uv workspaces** for the GridStream platform repo because it ships
multiple services (stub, producer, consumer, models) that need divergent
dependencies and per-service container builds.

**Your repo is one workspace member's worth of files.** Specifically:

```
your-service-repo/
├── Makefile                # copy from gridstream, adjust STUB_* vars
├── pyproject.toml          # single-project (no [tool.uv.workspace] block)
├── Dockerfile              # distroless final stage; no `--package` flag
├── .github/workflows/ci.yml  # 5-line caller of the reusable workflow
├── src/
│   └── your_service/
└── tests/
```

The workspace shape in the GridStream repo is for the platform repo's
benefit — it doesn't propagate to adopters. Your `Dockerfile` is simpler
than GridStream's stub Dockerfile because there's no workspace root to
reach for. Your `pyproject.toml` is one file at root, not a root + member
pair.

If you ever grow into running multiple services from one repo, you can
adopt the workspace pattern then — it's additive.

---

## What to read next

- [`charts/standard-service/README.md`](../charts/standard-service/README.md) —
  the chart's full values contract.
- [`docs/ARCHITECTURE.md`](./ARCHITECTURE.md) — system-level design context.
- [`docs/adr/`](./adr/) — every decision the road encodes, with the
  reasoning preserved.
- [`docs/remaining_sprints.md`](./remaining_sprints.md) — what's coming
  next; in particular, when Stage 4 (ArgoCD) and the observability stack
  arrive.

---

*Questions, gaps, or "this should work differently for my service" — open
a chart PR or drop into #platform-standards. The road improves by
adopters telling the platform team where it bumps.*
