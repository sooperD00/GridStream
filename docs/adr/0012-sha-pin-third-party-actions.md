# ADR-0012: SHA-pin third-party GitHub Actions, with Dependabot for updates

**Status:** Accepted
**Date:** 2026-05-04
**Sprint:** 1 (Paved Road)

## Context

The reusable CI workflow (`standard-python-service.yml`) calls four
third-party GitHub Actions: `actions/checkout`, `astral-sh/setup-uv`,
`docker/setup-buildx-action`, `docker/build-push-action`. Each was
initially pinned by tag (`@v4`, `@v3`, etc.) — the most common GHA
convention and the form GitHub's own documentation leads with.

GitHub Actions tags are **mutable references**. A maintainer (or
attacker who compromises maintainer credentials) can move `@v4` to a
different commit at any time, and every workflow that pins to `@v4`
picks up the new code on its next run. The March 2025
`tj-actions/changed-files` compromise propagated through tag movement
across an estimated 23,000+ repositories before detection. Tag pinning
is convenient; SHA pinning is the only mechanism that makes a workflow
run **the exact code reviewed at adoption time**, every time.

This decision pre-dates `@v1` of the reusable workflow. Once tagged,
the input contract and the security posture both become things adopters
inherit — including the supply-chain posture.

## Decision

Pin every third-party action used in this repo's workflows to a
**full 40-character commit SHA**, with a trailing `# vX.Y.Z` comment
naming the human-readable release the SHA corresponds to. Use
**Dependabot** (`.github/dependabot.yml`) to open PRs when new
releases ship; reviewers approve or reject each update with the
release notes visible in the PR diff.

This applies to third-party actions only. Local-path references
(`uses: ./.github/workflows/standard-python-service.yml`) and
GitHub-published first-party actions sharing the `actions/*`
namespace are both pinned by SHA under the same policy — first-party
trust is still trust, and the `tj-actions` incident showed that
namespace prestige is not a security boundary.

## Rationale

1. **Immutability is the only mechanism that closes the supply-chain
   surface.** A SHA, once published, cannot point at different code
   later. Every other pinning strategy (tags, branches, semver ranges)
   relies on the upstream maintainer's continued security posture
   remaining intact. SCADA-grade reliability mindset (per CONTEXT.md
   §2) treats "rely on others' continued security posture" as an
   accepted risk only when no alternative exists; SHA pinning is the
   alternative.

2. **The maintenance cost is solved, not deferred.** Dependabot reads
   the trailing `# v4.2.2` comment, checks upstream weekly, opens PRs
   that bump both the SHA and the comment together. Reviewers see the
   release notes in the PR description and approve in seconds. The
   review burden is not different from tag-based pinning where
   adopters track tag-bump PRs anyway; it is *more visible* because
   each update is its own diff.

3. **The cost lands on the platform team, not adopters.** Adopters
   inherit the SHA-pinned reusable workflow via `uses:
   sooperD00/gridstream/...@v1`. They do not see, maintain, or update
   the SHAs themselves. Dependabot runs in this repo. Adopters get
   the security posture for free.

4. **Pre-@v1 is the only cheap window.** Once `@v1` is tagged and
   adopters arrive, every change to the reusable workflow's behavior
   is a versioning consideration. Landing SHA pins now means the
   entire `@v1` line is SHA-pinned from inception; landing them later
   means coordinating an `@v2` cutover for adopters or accepting two
   parallel security postures.

## Consequences

### Positive
- Every workflow run uses the exact code reviewed at adoption time.
  Compromised tag movement upstream cannot affect this repo without
  Dependabot raising a PR with the changed SHA.
- Adopters of `@v1` inherit the posture without any work on their side.
- Dependabot's PRs become a routine review surface that doubles as
  a vulnerability monitoring channel — security advisories show up
  as failed-merge or held-back PRs.

### Negative
- Trailing-comment discipline. Every action pin is a SHA + comment
  pair; if the comment goes stale (Dependabot didn't update it, or
  a manual edit broke the pairing), human readers lose the version
  signal. Mitigated by Dependabot owning the update path and
  reviewers spot-checking that PR diffs update both halves.
- Slightly noisier PR queue. Weekly Dependabot batches are typical;
  acceptable for a platform repo where security posture *is* part of
  the deliverable.

### Neutral
- The decision is reversible. Reverting to tag pinning is one
  find-and-replace and a Dependabot config removal. Reversing the
  other direction (tag → SHA) is what this commit does, which is
  cheap because there's only one workflow file.

## Alternatives Considered

### Tag pinning with periodic manual audit — rejected
Status quo before this decision. Rejected because periodic manual
audit of action versions is exactly the kind of work that doesn't
get done under deadline pressure, and a paved road defined by
"trust the maintainer of every dependency" inherits every one of
those maintainers' security postures.

### Major-version tag pinning (`@v4`) without Dependabot — rejected
Convenient but the same as above with a smaller blast radius. Tag
movement on `@v4` is exactly what the `tj-actions` compromise
exploited.

### SHA pinning without Dependabot — rejected
Closes the supply-chain surface but rots into unpatched dependencies
within months. Dependabot is the maintenance answer that makes SHA
pinning sustainable rather than just secure-on-day-one.

### Third-party SHA-pinning enforcement tools (pinact, zizmor) — deferred
Tools exist that fail CI if any unpinned action sneaks in. Worth
adopting once adopters arrive and the surface area grows; for a
single-workflow repo with two workflow files, manual review at PR
time is sufficient. Revisit at Sprint 4 [SPRINT-4-CLEANUP].

## Revisit If
- A third-party action's release cadence becomes incompatible with
  Dependabot's weekly window (e.g., security patches needing same-day
  rollout). Solution: tighten Dependabot to daily for that action, or
  add a manual-update playbook entry.
- The PR review burden from Dependabot batches becomes routine
  ceremony rather than meaningful review. Adopt pinact or zizmor to
  enforce the rule in CI rather than relying on review attention.
- GitHub introduces native SHA-pinning enforcement at the org level
  (the policy linked from Lespinasse 2026 is moving in this direction).
  The repo is then policy-compliant by construction.

## References

- [ADR-0008](./0008-build-vs-adopt-idp-framework.md) — opt-in paved road posture
- [ADR-0010](./0010-multi-package-layout-with-uv-workspaces.md) — workspace shape
- [tj-actions/changed-files compromise (March 2025)](https://www.stepsecurity.io/blog/harden-runner-detection-tj-actions-changed-files-action-is-compromised) — the supply-chain incident this ADR responds to
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions) — official guidance on SHA pinning
- [Dependabot: configuration options](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
