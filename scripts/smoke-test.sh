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
echo "$healthz_body" | grep -q '"status":"alive"' \
  && ok "/healthz status=alive" \
  || ko "/healthz body: $healthz_body"
echo "$healthz_body" | grep -q '"service":"standard-service-stub"' \
  && ok "/healthz service=standard-service-stub" \
  || ko "/healthz service field wrong"

readyz_body=$(curl -sf "${BASE_URL}/readyz")
echo "$readyz_body" | grep -q '"status":"ready"' \
  && ok "/readyz status=ready" \
  || ko "/readyz body: $readyz_body"

section "Swagger UI"
docs_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/docs")
[ "$docs_code" = "200" ] \
  && ok "/docs returns 200 (Swagger renders)" \
  || ko "/docs returned ${docs_code}"

section "Echo — Pydantic round-trip"
echo_body=$(curl -sf -X POST "${BASE_URL}/echo" \
  -H 'content-type: application/json' \
  -d '{"message":"hello"}')
echo "$echo_body" | grep -q '"message":"hello"' \
  && ok "POST /echo mirrors message" \
  || ko "/echo body: $echo_body"
echo "$echo_body" | grep -q '"server_received_at"' \
  && ok "/echo includes server_received_at (default_factory ran server-side)" \
  || ko "/echo missing server_received_at"
echo "$echo_body" | grep -q '"service":"standard-service-stub"' \
  && ok "/echo stamps service name" \
  || ko "/echo service field wrong"

section "Echo — Pydantic rejects empty (proves validator is real, not theatrical)"
empty_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/echo" \
  -H 'content-type: application/json' \
  -d '{"message":""}')
[ "$empty_code" = "422" ] \
  && ok "POST /echo {message:\"\"} → 422" \
  || ko "empty-message POST returned ${empty_code} (expected 422)"

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
