<!-- [SPRINT-2-CLEANUP] grep-able marker per ADR-0004. Replace this
     placeholder README with real package documentation when consumer/ lands. -->

# consumer

**Sprint 2.** Placeholder.

The resilient consumer lands in Sprint 2: subscribes to `gridstream.readings`,
DLQ-routes poison pills to `gridstream.failed`, idempotent via
`device_id + timestamp`, wet-bulb safety interlock per
[ADR-0003](../../docs/adr/0003-fail-open-safety-interlocks.md). Deploys via
the Sprint 1 chart with no chart customizations. See
[`docs/remaining_sprints.md`](../../docs/remaining_sprints.md) §Sprint 2.

This directory exists in Sprint 1 to land the workspace shape per
[ADR-0010](../../docs/adr/0010-multi-package-layout-with-uv-workspaces.md).
