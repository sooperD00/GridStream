# ADR 8: Build a Custom Paved Road vs. Adopt an Existing IDP Framework

## Status
Accepted

## Context
"Paved road" / "Internal Developer Platform" (IDP) is a recognized pattern with active industry development. A reasonable reader of this repository will ask: why build custom rather than adopt an existing framework?

The relevant prior art:

- **Backstage** (Spotify, CNCF Incubating) — developer portal with software templates, service catalog, and plugin ecosystem.
- **CNOE** (Cloud Native Operational Excellence, CNCF working group) — opinionated reference IDPs combining ArgoCD, Backstage, Crossplane, and related projects.
- **Score** (score.dev) — workload specification format for portable service definitions.
- **Helm chart libraries** (Bitnami, the `common` library chart pattern) — base-chart inheritance for K8s resources.
- **GitHub `actions/starter-workflows`** — official reusable CI templates by language.

Platform engineering as a named discipline is recent. Team Topologies (2019) formalized "platform team" as an organizational pattern; Gartner began tracking platform engineering as a category in 2022; PlatformCon ran its first event in 2022. The components are increasingly standardized; integrated reference platforms for specific organizational contexts are not.

## Decision
We will **build a custom paved road for GridCorp**, composed of off-the-shelf components (Helm, GitHub Actions, ArgoCD, OpenTelemetry, Prometheus/Grafana) wired together with organization-specific opinions. We will not adopt Backstage or CNOE wholesale at this stage.

The components are off-the-shelf. The integration, the opinions, and the migration path are custom.

## Consequences

### Positive
- Opinions match constraints. The road can encode GridCorp-specific decisions — regulated SCADA fail-open defaults (ADR-003), Avro contracts with backward-transitive compatibility (ADR-001), lag-based autoscaling for I/O-bound consumers (ADR-002) — without contorting around a generic framework's assumptions.
- Migration path is bounded. Stage 1 (Makefile) → Stage 4 (ArgoCD) per ADR-006 fits eleven Flex teams in their current state. A Backstage adoption would impose a developer portal on teams that don't yet have a deployment story, sequencing the harder problem before the easier one.
- Vendor and framework risk stays low. Each component is independently swappable. ArgoCD can be replaced with Flux, GitHub Actions with GitLab CI, Helm with Kustomize, without rewriting the whole platform. Adopting Backstage as the integrating layer would couple all of them to Backstage's lifecycle and roadmap.
- The artifact is teachable. A platform built from named components with documented ADRs is one a successor engineer can audit and modify. A platform built on a framework requires the successor to learn the framework's idioms first.

### Negative
- Reinvention cost. Backstage's software-template feature solves the "scaffold a new service" problem out of the box; we will rebuild a smaller version of it in Sprint 4. We accept the build cost in exchange for opinion control.
- No service catalog UI. Backstage offers a polished catalog and discovery surface; this project does not, and will not in the planned sprints. If the org later needs a developer portal, it can be added on top — Backstage is designed to be additive to an existing platform.
- Less community gravity. A team adopting Backstage benefits from a public plugin ecosystem and shared patterns; a team adopting this paved road benefits only from what we document. Mitigated by ADR rigor and adoption playbook (Sprint 4).

### Neutral
- This decision is reversible at low cost. The components chosen (Helm charts, GitHub Actions workflows, ArgoCD applications) are exactly the inputs Backstage software templates would produce. If the org later adopts Backstage, the existing artifacts become its templates.

## Alternatives Considered

### Adopt Backstage as the integrating layer
Backstage would provide a developer portal, software-template scaffolding, and a service catalog. Rejected for this stage because (a) it solves the *discovery* problem the org doesn't yet have — eleven teams, all known to leadership — before solving the *deployment standardization* problem the org explicitly does have; (b) Backstage's value compounds with org size and is highest at hundreds of services, not eleven; (c) introducing a developer portal alongside a deployment migration doubles the change-management surface during the same window. Worth revisiting once the paved road is adopted by 5+ teams and discovery friction becomes the next bottleneck.

### Adopt CNOE reference architecture
CNOE provides an opinionated stack (ArgoCD + Backstage + Crossplane + others) with reference deployments. Rejected for the same reason as Backstage, plus: CNOE's opinions are designed for greenfield platforms, not for migration-from-existing. The "deploy how you want to meet customer needs" starting state is not what CNOE's reference deployments assume.

### Adopt Score as the workload specification format
Score is a portable service-definition format that abstracts away the underlying deployment target. Rejected as premature. Score is most valuable when teams need to deploy the same workload to multiple substrates (local + staging + multiple clouds); GridCorp's substrate is EKS, full stop. Adding Score now would be abstraction without a payoff. Worth revisiting if multi-cloud or hybrid-cloud becomes a real requirement.

### Use only Helm chart libraries (no custom integration)
Bitnami-style base charts solve the K8s-resource standardization problem but not the CI, GitOps, or observability standardization problems. Insufficient as a complete paved road; partially incorporated as a pattern within `charts/standard-service/`.

## Revisit Conditions
This decision should be revisited if:
- The org grows beyond ~25 services and discovery becomes a real bottleneck (→ consider Backstage atop the existing road).
- A second cloud or substrate enters scope (→ consider Score for portability).
- A successor platform team prefers framework-mediated work over component-mediated work as a stylistic choice (→ consider migrating onto CNOE).

The first two are concrete signals. The third is a judgment call and should not by itself drive a rewrite.

## References
- [ADR-006: Incremental GitOps Adoption Path](./0006-gitops-adoption-path.md)
- [Backstage](https://backstage.io/) — developer portal, CNCF Incubating
- [CNOE](https://cnoe.io/) — Cloud Native Operational Excellence
- [Score](https://score.dev/) — workload specification
- *Team Topologies* (Skelton & Pais, 2019) — platform team as organizational pattern
- [PlatformCon](https://platformcon.com/) — annual platform engineering conference
