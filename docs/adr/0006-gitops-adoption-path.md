# ADR 6: Incremental GitOps Adoption Path

## Status
Accepted

## Context
The platform's mandate is to migrate at least 5 application teams from "deploy how you want to meet customer needs" onto a defensible, automated continuous-integration pipeline by 2026/2027. Two failure modes are equally bad:

1. **Big-bang migration:** Halts feature work, generates resistance, and the effort dies politically before completion.
2. **Indefinite drift:** Each team makes a partial improvement, no two teams end up at the same destination, and the standardization effort produces no measurable result.

Managers and Leadership have been explicit: success looks like teams answering *"yes"* to **do you deploy the way clients want you to** and **can you deploy faster**. Both questions require visible, defensible deployment infrastructure — but the path there must respect existing team velocity.

The technical destination (pull-based GitOps with ArgoCD) is the right answer. The question is how to get there.

## Decision
We will adopt **GitOps with ArgoCD** (Git as source of truth, pull-based sync into the cluster) as the *destination* deployment model, and reach it via four explicitly-staged steps. Each stage is independently valuable. Each stage earns trust for the next.

| Stage | Team Action | Platform Provides | Time Investment per Team |
|---|---|---|---|
| 1. Versioned dev flow | Adopt a `Makefile` / `Taskfile` for build/test/deploy commands | Standard Makefile template | ~2 hours |
| 2. Standardized CI | Reference the shared GitHub Actions reusable workflow via `uses:` | `standard-python-service.yml` (lint, type, test, build) | ~3 hours |
| 3. Paved-road chart | Deploy via the shared Helm chart, parameterized via `values.yaml` | `charts/standard-service/` | ~1 day |
| 4. GitOps sync | Add an ArgoCD `Application` manifest pointing at the team's repo | ArgoCD installation, app-of-apps root | ~1 day |

Stages are **opt-in per team, in order**. Teams may pause between stages. The platform team does not pull a team forward against their will, but does not allow stages to be skipped (Stage 3 without Stage 2 produces unverified container images in the cluster).

## Consequences

### Positive
- Each stage produces a measurable improvement that survives if subsequent stages stall.
- Teams retain ownership of their deploy surface throughout. The platform reduces optionality, not autonomy.
- The platform team can publish accurate adoption metrics ("4 of 5 teams at Stage 2; 2 at Stage 4") rather than binary on/off claims.
- The migration narrative is defensible to leadership: every stage is justifiable on its own, regardless of whether the next one happens.
- Per-stage rollback is trivial — each stage adds one capability without removing anything.

### Negative
- The full benefit (pull-based GitOps) takes ~1–2 quarters per team to realize.
- During the transition, the cluster contains a mix of CI-pushed and ArgoCD-pulled deployments; observability tooling must accommodate both.
- Teams at Stage 1 still have manual deployments, which means leadership's two questions still answer "no" for those teams during the transition. The platform team must report adoption-stage data, not collapsed yes/no answers.

## Alternatives Considered

### Flux (CNCF graduated; Kustomization + HelmRelease CRDs)
Flux is technically excellent — lighter footprint, more compositional resource model, very Unix-y. In a homogeneous, expert-operated platform team, Flux is arguably the more elegant choice.

We chose **ArgoCD** for this specific context on three grounds:

1. **Adoption is the job, not the tool.** Stage 4 of this ADR's adoption path moves teams from CI-pushed deploys onto pull-based GitOps for the first time. ArgoCD's web dashboard makes "what is deployed, and does it match Git?" visible to engineers who haven't built that mental model yet. With Flux, the equivalent visibility requires a third-party UI (Weave GitOps, Capacitor) or comfort with `kubectl` + CLI introspection — fine for the platform team, friction for the application teams we're trying to onboard.
2. **Multi-tenancy out of the box.** ArgoCD ships with Projects, RBAC, and SSO integration. With 5+ application teams plus the platform team plus eventual auditor access, multi-tenant access control is a Day-1 requirement, not a Day-100 one. Flux can do this, but more of it is on the operator to assemble.
3. **`Application` CRD maps to the team mental model.** "Each team has one Application, pointing at their repo, synced into their namespace" is a one-sentence onboarding story. Flux's `Kustomization` + `HelmRelease` split is more powerful but harder to teach.

### Other GitOps approaches
- **Jenkins X / Spinnaker:** Heavier, less Kubernetes-native, more legacy weight than benefit for a greenfield platform.
- **CI-pushed deploys (e.g., GitHub Actions running `kubectl apply`):** This is Stage 2 of the adoption path, intentionally a step on the way rather than the destination. Push-based deploys couple the cluster's state to credentials held by CI, which is a security and audit posture we want to graduate out of.

### Revisit conditions
This decision should be revisited if (a) the org adopts a service mesh or controller stack with first-party Flux integration, (b) operational experience reveals ArgoCD's resource footprint as a meaningful cost on smaller clusters, or (c) the application-team population shifts toward CLI-first operators for whom the dashboard is overhead rather than scaffolding.

## References
- [ADR-005: Automated Quality Gates](./0005-automated-quality-gates.md) — Stage 2 mechanics
- [ADR-007: IaC Strategy with Deferred AWS](./0007-iac-strategy-with-deferred-aws.md) — infrastructure substrate for GitOps
- [`docs/adoption-playbook.md`](../adoption-playbook.md) — per-stage rollout playbook (Sprint 4 deliverable)
