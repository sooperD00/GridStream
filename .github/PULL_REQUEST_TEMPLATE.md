## 📝 Summary
*Briefly describe the changes introduced by this PR.*

## 🎯 High-Level Intent
- [ ] Bug Fix (Non-breaking)
- [ ] New Feature (Non-breaking)
- [ ] **Breaking Change** (Requires Architectural Review)
- [ ] Standardization/Refactor

## 🏗 Architectural Alignment
- [ ] **ADR Check:** Does this change align with existing [ADRs](docs/adr/)? 
- [ ] **Schema Check:** If modified, is the Avro schema backward-compatible?
- [ ] **Observability:** Have OpenTelemetry traces/metrics been added/updated?
- [ ] **Scale:** Has this been tested for high-volume telemetry (10k+ msg/s)?

## ⚠️ Safety & Risk Assessment
- [ ] Does this impact **Critical Loads** (Hospitals/Life-Safety)?
- [ ] Does this affect the **"Fail-Open"** logic during heatwaves (Wet-Bulb protocol)?
- [ ] Is there a rollback plan? (e.g., `make rollback` or Helm uninstall)

## 🧪 Quality Gate
- [ ] Unit tests passed (`make test`)
- [ ] Integration tests passed (Kafka/K8s connectivity)
- [ ] Linting and Type-checking passed (`ruff`, `mypy`)

## 📊 Evidence
*Please paste links to Grafana dashboards or Jaeger traces showing the code working in a dev environment.*

## 🔗 Related Issues
Fixes # (issue number)