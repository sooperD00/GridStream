<!-- [SPRINT-2-CLEANUP] grep-able marker per ADR-0004. Replace this
     placeholder README with real package documentation when models/ lands. -->

# models

**Sprint 2.** Placeholder.

Shared Pydantic v2 models that mirror the Avro schemas in `schemas/`. Imported
by both the producer and consumer; promotes "shared models" out of an import
hack and into a first-class workspace member per
[ADR-0010](../../docs/adr/0010-multi-package-layout-with-uv-workspaces.md).

Lands in Sprint 2 alongside the schemas. This directory exists in Sprint 1 to
make the workspace shape visible at `tree` time so future sprints don't
relitigate the layout.
