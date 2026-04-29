# ADR 7: Infrastructure-as-Code Strategy with Deferred AWS Deployment

## Status
Accepted (deferred implementation — see Sprint 5)

## Context
The target deployment environment for GridCorp is AWS — specifically EKS for orchestration, MSK for managed Kafka, and Glue Schema Registry for Avro contracts. CONTEXT.md states this explicitly. However, the priority for the project's near-term sprints is to demonstrate **architectural decisions and platform engineering judgment**, not cloud operational depth.

Two pressures are in tension:

1. **Signal density.** Local Kind / Docker Compose exercises every architectural decision in this project — Helm parameterization, GitOps, lag-based HPA, OpenTelemetry, schema evolution, DLQ routing. None of these arguments are strengthened by running on real AWS.
2. **Completeness.** A reference platform that *only* runs locally has a credibility ceiling. Real cloud deployment is what separates *"I designed a paved road"* from *"I shipped a paved road."*

The decision must satisfy the architectural argument first while preserving a credible path to the cloud-deployed reference outcome.

## Decision

1. **Terraform / OpenTofu is the canonical IaC tool** for any cloud infrastructure this project produces. No Pulumi, no CDK, no AWS Console clicks not preceded by a Terraform plan.
2. **Local development uses no IaC.** Kind cluster config (`kind/cluster.yaml`) and `docker-compose.yml` are sufficient for the local case. Adding Terraform for local infrastructure is overkill and creates maintenance burden without strengthening any argument.
3. **AWS deployment is deferred to Sprint 5.** It is intentionally not a blocker for Sprints 1–4. Sprint 5 produces:
   - VPC + EKS cluster + managed node group
   - MSK cluster + Glue Schema Registry
   - IRSA wiring (IAM Roles for Service Accounts)
   - ArgoCD installation on EKS
4. **The directory structure reserves space for it now.** `infra/terraform/` exists as a stub with a README explaining the deferred status, so Sprint 5 has a clear landing zone and no Sprint 1–4 artifact has to be retrofitted later.

## Consequences

### Positive
- Sprints 1–4 are not blocked on AWS account setup, IAM debugging, or cost-management overhead.
- The architectural argument stands on its own without requiring cloud access to validate.
- Sprint 5 has a clear, bounded scope rather than being smeared across the project.
- The deferral itself is a Staff-level signal: explicitly identifying which work strengthens the argument vs. which work is enrichment, and choosing accordingly.

### Negative
- The technical evaluation cannot include *"let me show you my running EKS cluster."* Mitigation: detailed Terraform module review + walkthrough of the deferred-but-planned design; treat the absence as an explicitly-articulated scope decision rather than an oversight.
- Real-world AWS gotchas (IRSA edge cases, MSK IAM auth quirks, Glue compatibility differences from Confluent Schema Registry) won't surface until Sprint 5. Discovering them during Sprint 5 may invalidate small assumptions made during Sprints 1–3 — which is acceptable since Sprint 5 is explicitly the integration test.

### Neutral
- The choice of OpenTofu vs. Terraform proper is left to Sprint 5 implementation, dependent on whether the deploying organization has a HashiCorp licensing position. The IaC code itself is portable between the two for the resource set this project uses.

## References
- [`docs/CONTEXT.md`](../CONTEXT.md) §2 — AWS as target environment
- [`docs/remaining_sprints.md`](../remaining_sprints.md) §5 — Sprint 5 scope
- [`infra/terraform/README.md`](../../infra/terraform/README.md) — stub directory documentation (Sprint 1 deliverable)
