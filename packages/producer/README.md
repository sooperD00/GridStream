<!-- [SPRINT-2-CLEANUP] grep-able marker per ADR-0004. Replace this
     placeholder README with real package documentation when producer/ lands. -->

# producer

**Sprint 2.** Placeholder.

The synthetic energy producer lands in Sprint 2: reads NREL/Pecan Street CSV,
Pydantic-validates each row, Avro-serializes via Schema Registry, publishes to
`gridstream.readings`. See [`docs/remaining_sprints.md`](../../docs/remaining_sprints.md)
§Sprint 2.

This directory exists in Sprint 1 to land the workspace shape per
[ADR-0010](../../docs/adr/0010-multi-package-layout-with-uv-workspaces.md) —
adding the workspace member here is a Sprint 2 task.
