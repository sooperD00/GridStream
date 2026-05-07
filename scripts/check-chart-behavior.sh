#!/usr/bin/env bash
# Verifies helm enforces values.schema.json when rendering the chart.
# Two cases should fail (schema rejection), two should succeed.

set -uo pipefail   # NOT -e — we *want* to capture expected failures
CHART="charts/standard-service"
FAIL=0

# Minimum-valid placeholders that satisfy the schema. Reused wherever we're
# exercising chart *behavior* rather than its rejection logic.
VALID=(--set app.name=demo --set image.repository=nginx)

# Helpers: if-then-else form (rather than `cmd && ok || ko`) avoids the
# SC2015 trap where a failing `echo` falsely triggers the failure branch.
# Single-label parameter — the helper supplies the ✓/✗ framing.
expect_pass() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ ${label}"
    else
        echo "✗ FAILED: ${label}"
        FAIL=$((FAIL+1))
    fi
}

expect_reject() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "✗ NOT REJECTED: ${label}"
        FAIL=$((FAIL+1))
    else
        echo "✓ rejected: ${label}"
    fi
}

expect_pass "helm lint passes" \
    helm lint "$CHART" "${VALID[@]}"

expect_reject "runAsNonRoot=false (tier-1 const must be enforced)" \
    helm template test "$CHART" --set podSecurityContext.runAsNonRoot=false

expect_reject "missing app.name (required field must be enforced)" \
    helm template test "$CHART"

expect_pass "valid values render" \
    helm template test "$CHART" "${VALID[@]}"

[ "$FAIL" -eq 0 ] || exit 1
