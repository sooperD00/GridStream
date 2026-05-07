#!/usr/bin/env bash
# Smoke-test the deployed standard-service-stub.
#
# Runs after `make deploy-local`. Wired up via `make smoke-test`.
# Verifies the paved road's first traveler answers correctly through the
# Helm-deployed Service: probe endpoints, /docs renders, /echo round-trips
# valid input and rejects empty input, and ADR-0004 structured logging
# fires with the expected service-context shape.
#
# Exits non-zero on any failure so CI (eventually) can gate on it.

set -euo pipefail

SERVICE=standard-service-stub
LOCAL_PORT=8000
SVC_PORT=80
BASE_URL="http://localhost:${LOCAL_PORT}"

# ─── tiny output helpers ────────────────────────────────────────────────────

GREEN='\033[32m'; RED='\033[31m'; CYAN='\033[36m'; RESET='\033[0m'
PASS=0; FAIL=0
ok()      { printf "  ${GREEN}✓${RESET} %s\n" "$1"; PASS=$((PASS+1)); }
ko()      { printf "  ${RED}✗${RESET} %s\n" "$1"; FAIL=$((FAIL+1)); }
section() { printf "\n${CYAN}%s${RESET}\n" "$1"; }

# Note: tests below use if-then-else rather than `cmd && ok || ko`. The
# &&-chain form trips SC2015 because a failing ok would falsely trigger ko.
# Each test's failure message includes context (response body, status code)
# that's specific enough to be worth repeating per-test rather than DRYing
# into a helper that would lose the per-test debugging detail.

# ─── port-forward setup (cleaned up on any exit path) ───────────────────────

section "Port-forward svc/${SERVICE} ${LOCAL_PORT}→${SVC_PORT}"
kubectl port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${SVC_PORT}" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT

# Poll /healthz until the forward is live (max ~10s).
for i in $(seq 1 20); do
  if curl -sf "${BASE_URL}/healthz" >/dev/null 2>&1; then
    ok "port-forward live (${i} attempt(s))"
    break
  fi
  sleep 0.5
  if [ "$i" -eq 20 ]; then
    ko "port-forward never came up — is the pod Ready?"
    exit 1
  fi
done

# ─── HTTP checks ────────────────────────────────────────────────────────────

section "Probes"

healthz_body=$(curl -sf "${BASE_URL}/healthz")
if echo "$healthz_body" | grep -q '"status":"alive"'; then
  ok "/healthz status=alive"
else
  ko "/healthz body: $healthz_body"
fi
if echo "$healthz_body" | grep -q '"service":"standard-service-stub"'; then
  ok "/healthz service=standard-service-stub"
else
  ko "/healthz service field wrong"
fi

readyz_body=$(curl -sf "${BASE_URL}/readyz")
if echo "$readyz_body" | grep -q '"status":"ready"'; then
  ok "/readyz status=ready"
else
  ko "/readyz body: $readyz_body"
fi

section "Swagger UI"
docs_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/docs")
if [ "$docs_code" = "200" ]; then
  ok "/docs returns 200 (Swagger renders)"
else
  ko "/docs returned ${docs_code}"
fi

section "Echo — Pydantic round-trip"
echo_body=$(curl -sf -X POST "${BASE_URL}/echo" \
  -H 'content-type: application/json' \
  -d '{"message":"hello"}')
if echo "$echo_body" | grep -q '"message":"hello"'; then
  ok "POST /echo mirrors message"
else
  ko "/echo body: $echo_body"
fi
if echo "$echo_body" | grep -q '"server_received_at"'; then
  ok "/echo includes server_received_at (default_factory ran server-side)"
else
  ko "/echo missing server_received_at"
fi
if echo "$echo_body" | grep -q '"service":"standard-service-stub"'; then
  ok "/echo stamps service name"
else
  ko "/echo service field wrong"
fi

section "Echo — Pydantic rejects empty (proves validator is real, not theatrical)"
empty_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/echo" \
  -H 'content-type: application/json' \
  -d '{"message":""}')
if [ "$empty_code" = "422" ]; then
  ok "POST /echo {message:\"\"} → 422"
else
  ko "empty-message POST returned ${empty_code} (expected 422)"
fi

# ─── ADR-0004 structured-logging shape check ────────────────────────────────

section "Structured logging (ADR-0004)"
# Brief flush window after the echo POST.
sleep 1
if kubectl logs "deploy/${SERVICE}" --tail=50 \
    | grep -q "echo request received service=standard-service-stub message_length=5"; then
  ok "ADR-0004 log line present in pod logs"
else
  ko "expected log line not found — see: kubectl logs deploy/${SERVICE}"
fi

# ─── verdict ────────────────────────────────────────────────────────────────

section "Result"
printf "  %d passed, %d failed\n\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
