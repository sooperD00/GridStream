#!/usr/bin/env bash
# Smoke test for charts/standard-service/values.schema.json (ADR-0011).
# Verifies (1) the schema parses as JSON Schema 2020-12, and (2) Helm
# actually enforces it on install — known-bad overrides must fail
# `helm template`, known-good must succeed.
#
# Called from CI and from `make check-schema`.
# Requires `jsonschema` in the workspace's dev dependencies.
set -euo pipefail

CHART="charts/standard-service"

# ── 1. Schema is well-formed ────────────────────────────────────────────────
uv run python - <<EOF
from jsonschema import Draft202012Validator
import json
Draft202012Validator.check_schema(json.load(open("${CHART}/values.schema.json")))
print("✓ schema is well-formed JSON Schema 2020-12")
EOF

# ── 2. Helm enforces the schema ─────────────────────────────────────────────
# expect_ok / expect_fail wrap `helm template` so the test cases below read as
# "this set of values should/should not render."
run()         { helm template test "${CHART}" "$@" > /dev/null 2>&1; }
expect_ok()   { local label="$1"; shift; run "$@" && echo "✓ ${label}" || { echo "✗ ${label} FAILED (expected helm template to succeed)"; exit 1; }; }
expect_fail() { local label="$1"; shift; run "$@" && { echo "✗ ${label} NOT REJECTED (expected helm template to fail)"; exit 1; } || echo "✓ ${label}"; }

# Known-good: minimum viable values render cleanly.
expect_ok "known-good values render" \
    --set app.name=demo \
    --set image.repository=nginx

# MUST-override tier: missing app.name must fail
# (deployment.yaml `required` + schema's minLength).
expect_fail "missing app.name rejected" \
    --set image.repository=nginx

# SHOULD-NOT-override tier: pinned const fields must fail (schema only).
expect_fail "runAsNonRoot=false rejected" \
    --set app.name=demo \
    --set image.repository=nginx \
    --set podSecurityContext.runAsNonRoot=false

expect_fail "probe path override rejected" \
    --set app.name=demo \
    --set image.repository=nginx \
    --set probes.liveness.path=/custom

echo
echo "All schema checks passed."
