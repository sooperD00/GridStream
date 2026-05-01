# ADR-0011: Enforce the chart's values contract via JSON Schema

**Status:** Accepted
**Date:** 2026-05-01
**Sprint:** 1 (Paved Road)

## Context

The paved-road chart's README describes a four-tier values contract:
**MUST override**, **SHOULD configure**, **SHOULD NOT override**, and
**MUST NOT touch**. The README is prose; the chart was, before this ADR,
relying on the prose to do enforcement work.

Audit of which tiers were *mechanically* enforced before this decision:

| Tier | Where it was supposed to live | Actually enforced? |
| --- | --- | --- |
| MUST override | `values.yaml` empty defaults | ✅ partial — Helm `required` template function fails the install |
| SHOULD configure | `values.yaml` safe defaults | (correctly unenforced — defaults are allowed) |
| SHOULD NOT override | `values.yaml` safe defaults | ❌ **none — identical to SHOULD configure** |
| MUST NOT touch | `templates/_helpers.tpl` (no value exposed) | ✅ enforced by absence — no knob exists |

The gap is the third row. An adopter could set `podSecurityContext.runAsNonRoot: false`
or `probes.liveness.path: /api/something-else` in their `values-myservice.yaml`
and `helm install` would accept it without complaint. The README told them not
to; nothing stopped them.

This pairs directly with [ADR-0009](./0009-container-base-image.md). The
distroless production image's whole point is "the platform makes the secure
default the easy default — adopters have to choose to be unsafe, and that
choice surfaces in code review." A README that *describes* `runAsNonRoot: true`
without enforcing it leaves the platform half-paved: secure at the image
layer, advisory at the chart layer.

The relevant prior art:

- **Helm's `required` template function.** Already used for MUST-override
  tier. Per-field, runs at template-rendering time, error message points at
  the template line not the values file.
- **`values.schema.json`.** Helm picks up a JSON Schema file sibling to
  `values.yaml`, validates merged values against it before rendering, and
  fails the install with structured errors.
  [Helm docs reference](https://helm.sh/docs/topics/charts/#schema-files).
- **Admission-time policy engines** (Kyverno, OPA Gatekeeper). Server-side,
  cluster-level, language-rich. Reject pods regardless of what chart they
  came from.

## Decision

Ship `charts/standard-service/values.schema.json` enforcing the README
contract mechanically. Specifically:

| README tier | Schema mechanism |
| --- | --- |
| MUST override | `required` + `minLength: 1` + format `pattern` where applicable |
| SHOULD configure | `additionalProperties: false` + type/enum bounds (no value pinning) |
| SHOULD NOT override | `const` pinning on the load-bearing fields (e.g. `runAsNonRoot: true`, probe paths) |
| MUST NOT touch | (unchanged — stays in `_helpers.tpl`, not exposed as a value) |

The schema is committed alongside the README change that promotes "the
schema is the contract; the README describes it."

## Rationale — technical

1. **Failures move from runtime to install time, with the right error
   message.** Without the schema, `runAsNonRoot: false` rolls out, the pod
   schedules, and the failure surface is whatever K8s admission controllers
   the cluster happens to run — which varies per environment. With the
   schema, `helm install` itself rejects with `podSecurityContext.runAsNonRoot:
   True was expected` and the file path that caused it. Faster feedback,
   identical-across-environments error.
2. **`additionalProperties: false` catches typos.** `replicass: 3` silently
   defaults to `1` without a schema. With the schema, Helm errors out. This
   is unrelated to the four-tier contract but is a real adopter-pain win
   that comes free with the schema.
3. **Pattern validation catches K8s-API-rejection-class errors earlier.**
   `app.name` must be DNS-1123-label-compatible. The schema rejects
   `app.name: My_Service` at install time with a regex hint instead of at
   apply time with a confusing K8s API error.
4. **Asymmetric strictness on security contexts.** The load-bearing fields
   (`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation`,
   `capabilities.drop` containing `ALL`) are pinned with `const`. The
   surrounding object stays `additionalProperties: true` because K8s
   security contexts have many legitimate optional fields
   (`fsGroupChangePolicy`, `supplementalGroups`, `windowsOptions`) that
   adopters might need. Pin the contract, not the shape.

## Rationale — behavioral (the paved-road part)

5. **The paved-road philosophy from ADR-0009 generalizes one layer up.**
   ADR-0009: the platform makes the secure default the easy default at the
   image layer. ADR-0011: same, at the chart-values layer. The two layers
   were inconsistent before this ADR; they're consistent after.
6. **Code-review burden drops.** "Why are you overriding `runAsNonRoot`?"
   moves from a question a reviewer has to remember to ask, to a question
   the schema asks automatically. Reviewer time goes to logic, not policy
   enforcement.
7. **The schema is the input shape for a future form-UI adoption path.**
   ArtifactHub renders charts with `values.schema.json` as forms. Backstage's
   software-template plugin does the same. If the org later wants a
   non-text-file adoption surface for less CLI-comfortable teams, the
   schema is step one of that path, written for its near-term purpose. No
   speculative work.
8. **Contract-as-data outlives contract-as-prose.** A successor maintainer
   can `cat values.schema.json` and read the full enforced contract in one
   file. The prose README will drift; the schema and the chart can't drift
   without breaking adopters' installs, which is the kind of drift that
   gets fixed.

## Alternatives Considered

### CODEOWNERS on `values-*.yaml` in adopting repos — rejected as primary mechanism

**Pro:** Puts a human in the loop for security-context overrides. Catches
intent ("this team wants to do an unsafe thing and we should know why")
where the schema only catches form.
**Con:** Social, not mechanical. Depends on each adopting team setting up
CODEOWNERS correctly. Doesn't help local development or CI before the PR
exists. Doesn't help on `--set` overrides at the command line.
**Con:** Conflates two layers — the platform team should not be a default
reviewer on every adopting team's values file edits. CODEOWNERS at the
chart-repo level (changes to *the chart itself*) is the right fit;
CODEOWNERS at the adopting-team level is overreach.

Reasonable as a complement, not a replacement. Worth recommending in the
adoption playbook (Sprint 4) for teams whose security posture warrants it,
without making it part of the platform's enforcement surface.

### Kyverno / OPA Gatekeeper admission policy — deferred, complementary

**Pro:** Server-side enforcement. The cluster rejects pods that violate
policy regardless of which chart they came from, which scope hand-rolled
manifests (and any chart from outside the paved road) into the same
guardrails.
**Pro:** Richer expression than JSON Schema — policies can reference
runtime context (namespace, labels, image registry).
**Con:** Different layer of the stack, different operational ownership,
different failure mode. The schema fails at `helm install` with the
adopter's file path; admission policy fails at `kubectl apply` with a
cluster-level rejection. Both are valid; the schema is closer to where
the adopter is editing.
**Con:** Requires the policy engine to be installed and maintained. Sprint 3
territory at earliest, paired with the observability stack.

Defense in depth. The schema is the right Sprint 1 deliverable; admission
policy is the right Sprint 3+ deliverable. They are not redundant — the
schema catches misconfiguration before deploy; admission policy catches
anything that bypasses the chart entirely.

### Stay with prose-only README — rejected

The status quo. Rejected because the README's "MUST NOT touch" tier was
not actually different from "SHOULD configure" tier in any way an adopter
would notice. A four-tier contract that's mechanically a two-tier contract
is worse than a documented two-tier contract — it implies enforcement that
isn't there.

### Inline `required` calls in templates instead of a schema file — rejected

Helm's `required` template function works for individual MUST-override
fields and the chart already uses it. Extending this pattern to cover the
SHOULD-NOT-override tier (e.g. `{{ if not .Values.podSecurityContext.runAsNonRoot }}{{ fail "..." }}{{ end }}`)
is possible but produces enforcement scattered across templates instead of
declared in one place. The schema collects the contract; template-level
checks fragment it.

## Consequences

### Positive
- The four-tier contract becomes mechanically real. SHOULD-NOT-override
  fields fail `helm install` with file-path-pointing error messages.
- Typos in values files fail fast (`additionalProperties: false`).
- Pattern validation catches a class of K8s API rejections at install time
  rather than apply time.
- The schema is reusable as the input format for future schema-driven UI
  (ArtifactHub, Backstage), without speculative work now.
- The README/schema relationship gives a successor maintainer a clear
  authority hierarchy: the schema is the contract, the README explains
  the schema, the schema wins on disagreement.

### Negative
- Schema and chart can drift. Mitigated by a CI smoke test that runs
  `Draft202012Validator.check_schema` against the schema and `helm template`
  with both known-good and known-bad values to verify the schema rejects
  what it claims to reject. Two failing template calls + one passing one
  is the minimum useful test set; the schema-itself check is one extra line.
- Schema verbosity. JSON Schema with `additionalProperties: false` and
  per-field constraints is meaningfully longer than the equivalent prose.
  Mitigated by the README continuing to be the human-readable surface; the
  schema is read by Helm and by a successor maintainer auditing the
  contract, not by adopters in normal use.
- Overrides that the schema legitimately should not pin — a future
  fields the platform team hasn't decided on yet — will need explicit
  schema updates rather than just "set a default in values.yaml." Small
  added ceremony at decision time. Worth it.

### Neutral
- The schema's strictness can be tuned. Starting strict (`additionalProperties: false`,
  full pattern validation) is the right default for a paved-road chart;
  loosening is easier than tightening once adopters depend on a shape.

## Revisit If

- Helm's schema support diverges meaningfully from JSON Schema 2020-12
  (currently the version this schema targets).
- An admission-policy engine (Kyverno / Gatekeeper) lands in the cluster
  and the question becomes whether the chart-level schema is still
  earning its keep — answer probably remains yes (different layer, faster
  feedback) but the comparison is worth re-running.
- Adopters report cases where the schema's `additionalProperties: false`
  rejects legitimate K8s fields the chart should be passing through. The
  fix is to widen the schema or surface the field as a typed value, not
  to relax the strict-mode default globally.

## References

- [ADR-0004: Logging and Stub Standards](./0004-logging-and-stub-standards.md) — the broader pattern of converting prose conventions into mechanical checks
- [ADR-0009: Container Base Image](./0009-container-base-image.md) — the paved-road philosophy this ADR extends from the image layer to the values layer
- [`charts/standard-service/README.md`](../../charts/standard-service/README.md) — the four-tier contract this schema enforces
- [`charts/standard-service/values.schema.json`](../../charts/standard-service/values.schema.json) — the schema itself
- [Helm: Schema Files](https://helm.sh/docs/topics/charts/#schema-files)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/schema)
