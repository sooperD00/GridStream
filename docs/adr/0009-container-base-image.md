# ADR-0009: Container base image for paved-road services

**Status:** Accepted
**Date:** 2026-04-29
**Sprint:** 1 (Paved Road)

## Context

The paved-road Dockerfile template ships in `charts/standard-service` as the default container build for adopting teams. The final stage of the multi-stage build determines a lot: image size, CVE surface, what tools live alongside the running process, and — most consequentially for a paved road — what debugging affordances adopters inherit for free. The choice is also a statement about what the platform considers "production-shaped."

Three plausible options surveyed: `gcr.io/distroless/python3-debian12`, `python:3.11-alpine`, `python:3.11-slim-bookworm`.

The adopting context matters as much as the technical surface. Adopters are 5–11 teams across 3 geos working on distributed energy management. Today they are not DevOps- or CLI-savvy; their current deploys are non-standardized and big-bang. Leadership has mandated that observability ships *with* the platform, not as a follow-on negotiation. The staff-engineering mandate is adoption: get those teams onto a standard production surface they can join at their own pace, without each team having to invent its own debugging story.

## Decision

The paved-road Dockerfile's final stage is **`gcr.io/distroless/python3-debian12`**.

A companion `Dockerfile.dev` (using `python:3.11-slim-bookworm`) is provided for *local development only*, with a loud `# NOT FOR PRODUCTION` header and exclusion from the default `make build` target.

## Rationale — technical

1. **glibc base.** Python wheels with C extensions install from prebuilt binaries rather than compiling from source. This matters concretely for `confluent-kafka` (librdkafka C dependency, Sprint 2's reference service) and for the broader scientific-Python stack adopters are likely to bring later (`numpy`, `pandas`, `psycopg2`, `cryptography`). Alpine's musl libc is a documented source of "works on my laptop, breaks in CI six months later" failures for exactly this class of dependency.
2. **Minimal CVE surface.** The runtime image carries Python, ca-certs, tzdata, and the application. No shell, no package manager, no userland utilities. Whatever security has to scan or patch, there is dramatically less of it — per service and across the org.
3. **Image size is competitive.** Distroless python3-debian12 is in the same ~50MB neighborhood as alpine and well under slim's ~150MB, without alpine's wheel-compatibility hazards.

## Rationale — behavioral (the paved-road part)

1. **The platform makes the secure default the easy default.** Adopters don't have to choose to be safe; they have to choose to be unsafe (and that choice surfaces in code review). This is the entire point of a paved road.
2. **The absence of a shell is a forcing function for observability investment, not a regression.** Adopters can't `kubectl exec` and `tail -f` their way out of an incident, so they lean on the OpenTelemetry traces, Prometheus metrics, structured logs (ADR-004), and Grafana golden-signals dashboard the chart ships in Sprint 3.
3. **Aligns the technical default with the leadership mandate.** Observability stops being a separate adoption task and becomes the only debugging path that exists. Teams that wanted to skip it can't, and teams that wanted it never had to argue for it.
4. **Strong signal to the adopting org.** "The platform has already thought about attack surface; you don't have to" is the message a paved road should carry. "We picked the standard image" is not.

## Alternatives considered

### `python:3.11-alpine` — rejected

- **Pro:** has `ash` shell, smallest possible base, familiar to some teams.
- **Con:** musl libc. Python wheels with C extensions can fall back to source compilation and fail in late-binding, hard-to-reproduce ways. `confluent-kafka` — required by the Sprint 2 reference service — is a known case. This is a tax adopters would pay forever, and it would surface as platform-team support tickets.
- **Con:** softer security signal. "Small" is not the same as "minimal attack surface"; alpine still ships `apk`, `ash`, BusyBox utilities.
- **Con:** encourages `exec`-based debugging at exactly the moment the platform is trying to redirect that energy toward observability.

### `python:3.11-slim-bookworm` — rejected as default; retained for `Dockerfile.dev`

- **Pro:** glibc, debian-based, has shell + apt, debuggable, the Python community's safe default.
- **Con:** includes `apt`, `bash`, `dpkg`, coreutils — meaningful attack surface for no production-time benefit.
- **Con:** weaker paved-road statement. The platform's job is to make the right choice for adopters, not to ratify the median choice they would have made themselves.
- Reasonable as the local-development base where shell access genuinely helps and the image never ships beyond a developer's laptop.

## Consequences

### Positive

- Adopting teams inherit a hardened production image without making any decisions.
- Security-review burden drops, both per-team and platform-wide.
- Observability adoption is no longer a separate ask — it's the only path. The leadership mandate is satisfied structurally rather than through per-team negotiation.
- Aligns with Sprint 3 deliverables: OTel collector default in the chart, Prometheus ServiceMonitor, Grafana golden-signals dashboard, structured logging from ADR-004. These become the actual debugging surface, not a nice-to-have.
- Aligns with the Sprint 4 adoption playbook: each onboarding stage progressively delivers more observability, so adopters never hit a window where they're stuck without debugging tools.

### Negative

- `kubectl exec -it <pod> -- sh` does not work. Teams accustomed to that workflow will be initially uncomfortable. (Naming this directly because it's the single most predictable adoption complaint.)
- Onboarding cost: each team needs to learn `kubectl debug` (ephemeral debug containers), `kubectl logs --previous`, and the Grafana / Jaeger / Prometheus surfaces.
- The platform team owes adopters first-class documentation and probably office hours during the migration window. This is an organizational commitment as much as a technical one.

### Mitigations

- `docs/paved-road.md` includes a **"Debugging without a shell"** section covering `kubectl logs`, `kubectl describe`, `kubectl debug` ephemeral containers, and the Sprint 3 observability stack.
- `Dockerfile.dev` (slim base) provided for local poking, clearly labeled `# NOT FOR PRODUCTION` and excluded from the default build target.
- The Sprint 4 adoption playbook sequences observability tooling early — by Stage 3 (chart adoption), teams already have OTel and Grafana, so debug-without-shell is never the only option a team has when something breaks.
- Office-hours / pairing budget reserved for the first three teams onboarding. (Staff-eng mandate territory; this ADR records the technical decision but the adoption commitment lives in the playbook.)

## Revisit if

- A class of debugging work emerges that the observability stack genuinely cannot cover (e.g. JIT-only repros requiring live process inspection).
- An adopting team's domain has a hard requirement for in-container shell tooling at runtime (e.g. a sidecar that needs to invoke a CLI against the main container).
- `gcr.io/distroless/python3-debian12` becomes meaningfully harder to maintain — current as of 2026-04, but worth tracking the distroless project's release cadence.

## References

- ADR-004 — Structured logging (provides the log-based debugging surface this decision relies on)
- Sprint 3 plan — OpenTelemetry instrumentation, Prometheus + Grafana, lag-based HPA
- Sprint 4 plan — Adoption playbook sequencing for non-DevOps teams
- [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless)
