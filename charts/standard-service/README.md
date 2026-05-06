# `charts/standard-service/`

`charts/standard-service` — yes, the whole directory: Chart.yaml + values.yaml +
templates/ — is GridStream's paved-road Helm chart. It's a single, parameterized
package that any team's Python service can install via `values.yaml` overrides —
no fork, no copy-paste, preserving single-source-of-truth, enforcing
standardization, and preventing drift.

This README explains the contract implemented when you adopt the paved road, and
provides instructions for adoption. Specifically, it explains what `values.yaml`
accepts, what adopters must override, what they should configure, and what they
should not touch.

> The chart's templates encode platform opinions: liveness/readiness probes,
> security context, label conventions. The `values.yaml` is where adopters
> express service-specific shape. If a service needs a chart-template change,
> that's a signal the paved road chart here was under-parameterized — we will fix
> the chart, don't fork it!

---

## Adopting the chart

```bash
helm upgrade --install <release-name> oci://ghcr.io/sooperD00/charts/standard-service \
    --version 0.1.0 \
    -f values-myservice.yaml
```

> The OCI registry path above is the published location. The chart isn't
> published yet (see [remaining_sprints.md] — publishing is scheduled with
> Sprint 4). Until then, install the chart directly from this repo: `make deploy-local`.
> [SPRINT-4-CLEANUP] When the chart publishes to OCI, remove the "isn't
> published yet" qualifier; keep `make deploy-local` as the local-development
> path.

A minimal `values-myservice.yaml` to get you started:

```yaml
app:
  name: my-service
image:
  repository: ghcr.io/myorg/my-service
  tag: "1.4.2"
config:
  LOG_LEVEL: "INFO"
```

Everything else inherits paved-road defaults.

---

## The contract

The contract this README describes lives in three places:

- `values.schema.json` — machine-enforced. `helm install` rejects values that
  violate it. This is what fails the build when an adopter overrides
  `runAsNonRoot: false` or omits `app.name`.
- `templates/_helpers.tpl` — enforced by absence. The label scheme and naming
  helpers aren't exposed as values, so adopters can't override them without
  forking the chart.
- This README — explains what the schema and helpers do, why, and how an
  adopter is expected to interact with them. The schema fails fast; the README
  tells you why it failed and what to do instead.

If the README and the schema disagree, the schema wins and the README has
a bug.

### MUST override

These have no sensible default. Helm fails fast if missing.

| Field | Why required |
| --- | --- |
| `app.name` | Container name and identification surface. Logs and dashboards rely on this being explicit per service. |
| `image.repository` | The chart can't guess where your image lives. |

> The empty strings in `values.yaml` defaults aren't placeholders to fill
> in — they're the schema's rejection trigger. Tooling that runs against
> bare defaults (e.g. plain `helm lint charts/standard-service`) will
> fail; pass placeholder values to exercise chart behavior. See
> `scripts/check-chart-behavior.sh` for the canonical pattern.

### SHOULD configure

These have safe defaults, but a production-shaped service usually wants its
own values:

| Field | Default (local dev settings) | When to override |
| --- | --- | --- |
| `image.tag` | `latest` | Always override. `latest` is for local dev; production uses pinned tags. |
| `deployment.replicas` | `1` | Production services running in HA need ≥2. |
| `resources.requests` / `resources.limits` | Stub-shaped (100m/128Mi req, 500m/512Mi lim) | Always override. Size to your measured behavior. |
| `config` | empty | Anything env-var-shaped: `LOG_LEVEL`, broker addresses, feature flags. |
| `env` | empty | Anything secret-shaped (`secretKeyRef`) or downward-API-shaped (`fieldRef`). |
| `service.targetPort` | `8000` | Override if your application listens on a different port. The Helm chart's `port: http` binding follows this. |

### SHOULD NOT override

These encode platform-wide opinions. Overriding them is allowed but should
require justification at code review.

| Field | Default | Why fixed |
| --- | --- | --- |
| `probes.liveness.path` | `/healthz` | Convention. Every paved-road service exposes `/healthz`. |
| `probes.readiness.path` | `/readyz` | Same. |
| `podSecurityContext` | `runAsNonRoot: true`, `nonroot` UID, `RuntimeDefault` seccomp | Matches the distroless production image (ADR-0009). |
| `containerSecurityContext` | `readOnlyRootFilesystem: true`, all caps dropped | Same. |

### MUST NOT touch

The label scheme is enforced at the template level — you can't accidentally
emit a service without `app.kubernetes.io/part-of: gridstream`. This is by
design: observability and ArgoCD selectors depend on these labels being
present and consistent across every adopter.

| Concern | Where it lives |
| --- | --- |
| `app.kubernetes.io/*` labels | `templates/_helpers.tpl` `standard-service.labels` |
| Selector labels | `templates/_helpers.tpl` `standard-service.selectorLabels` |
| Resource naming | `templates/_helpers.tpl` `standard-service.fullname` |

If you genuinely need to extend the label set (cost-attribution tags, team
ownership labels), open a chart PR. Don't add labels in a fork.

---

### How each tier is enforced

| Tier | Mechanism |
| --- | --- |
| MUST override | `values.schema.json` requires the field; `templates/deployment.yaml` also calls Helm's `required` function. Both fail at install time. |
| SHOULD configure | `values.schema.json` enforces type, range, and `additionalProperties: false`. Catches typos (`replicass: 3`) but allows any legitimate value. |
| SHOULD NOT override | `values.schema.json` pins the field with `const`. Overriding `runAsNonRoot: false` or `probes.liveness.path: /custom` fails `helm install` with the file path that caused it. |
| MUST NOT touch | The field isn't exposed as a value at all — lives in `templates/_helpers.tpl`. Adopter would have to fork the chart to change it. |

This is the *reason* the four tiers above are real tiers and not aspirational ones. See ADR-0011 for the design rationale.

---

## Sidecars

`deployment.extraContainers` is a free-form list of full container specs,
default empty. The shape was chosen over a typed `sidecar:` block because
Sprint 3 will inject both an OTel collector *and* (potentially) a
kafka-lag exporter, and a list scales more cleanly than two specific blocks.

```yaml
deployment:
  extraContainers:
    - name: otel-collector
      image: otel/opentelemetry-collector:0.95.0
      args: ["--config=/conf/otel-collector.yaml"]
      ports:
        - containerPort: 4317
          name: otlp
```

---

## What this chart does NOT do (yet)

| Concern | Sprint |
| --- | --- |
| ServiceAccount creation (with IRSA support) | [SPRINT-5-CLEANUP] Sprint 5 (AWS) |
| Job / CronJob template (for the producer) | [SPRINT-2-CLEANUP] Sprint 2 — added as `templates/job.yaml` if needed; the values shape is namespaced under `deployment:` so a sibling `job:` block can be added without breaking changes. |
| HorizontalPodAutoscaler | [SPRINT-3-CLEANUP] Sprint 3 (lag-based, per ADR-0002) |
| Ingress | [SPRINT-3-CLEANUP] Sprint 3 |
| NetworkPolicy | Future |
| ServiceMonitor (Prometheus) | [SPRINT-3-CLEANUP] Sprint 3 |

These are deliberately deferred per the [sprint roadmap](../../docs/remaining_sprints.md).
The chart is *small on purpose* in Sprint 1 — adding more before adopters
exercise the basics produces parameterization that's wrong in invisible ways.

---

## Local install (smoke test)

```bash
make infra-up        # kind cluster
make deploy-local    # builds the stub image, kind-loads it, helm-installs

kubectl get pods -l app.kubernetes.io/instance=standard-service-stub
kubectl port-forward svc/standard-service-stub 8000:80
curl http://localhost:8000/healthz
```

See [`docs/paved-road.md`](../../docs/paved-road.md) for the full ten-minute
adoption tutorial.
