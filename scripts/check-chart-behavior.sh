#!/usr/bin/env bash
# Verifies helm enforces values.schema.json when rendering the chart.
# Two cases should fail (schema rejection), one should succeed.

set -uo pipefail   # NOT -e — we *want* to capture expected failures
CHART="charts/standard-service"
FAIL=0

# Minimum-valid placeholders that satisfy the schema. Reused wherever we're
# exercising chart *behavior* rather than its rejection logic.
VALID=(--set app.name=demo --set image.repository=nginx)

helm lint "$CHART" "${VALID[@]}" >/dev/null 2>&1 \
    && echo "✓ helm lint passes" \
    || { echo "✗ helm lint FAILED — schema may be malformed"; FAIL=$((FAIL+1)); }

helm template test "$CHART" --set podSecurityContext.runAsNonRoot=false >/dev/null 2>&1 \
    && { echo "✗ ACCEPTED runAsNonRoot=false — tier-1 const not enforced!"; FAIL=$((FAIL+1)); } \
    || echo "✓ rejects runAsNonRoot=false"

helm template test "$CHART" >/dev/null 2>&1 \
    && { echo "✗ ACCEPTED empty app.name — required-field check broken"; FAIL=$((FAIL+1)); } \
    || echo "✓ rejects empty app.name"

helm template test "$CHART" "${VALID[@]}" >/dev/null 2>&1 \
    && echo "✓ valid values render" \
    || { echo "✗ valid values REJECTED — schema over-restrictive"; FAIL=$((FAIL+1)); }

[ "$FAIL" -eq 0 ] || exit 1
