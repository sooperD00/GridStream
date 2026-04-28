---
name: 🐛 Bug Report
about: Report a platform or data ingestion issue
title: '[BUG]: '
labels: bug, triage
---

## 📝 Description
A clear and concise description of the failure. 

## ⚠️ Safety & Compliance Impact
Does this issue present a risk to humans, physical assets, or regulatory standing?
- [ ] **Worker Safety:** Impacts field technicians or industrial SCADA operations.
- [ ] **Hazardous:** Potential for hardware damage (e.g., battery overcharge, transformer stress).
- [ ] **Customer Safety:** Impacts during high wet-bulb temps (heat stroke risk), hospital circuit detected, telemetry loss, etc.
- [ ] **Compliance:** Breach of FERC/NERC reliability standards or data privacy (GDPR/CCPA).
- [ ] **None:** Purely logical or UI-related.

## ⚡ Grid Impact
What is the operational impact of this bug?
- [ ] Critical: Data loss or incorrect grid dispatch (SCADA impact)
- [ ] High: Ingestion lag increasing beyond SLO
- [ ] Medium: Observability/UI mismatch
- [ ] Low: Non-functional or developer experience issue

## 🛠 Steps to Reproduce
1. Go to '...'
2. Run '...'
3. See error

## 🔍 Observed vs. Expected Behavior
- **Observed:** (e.g., Kafka Lag increased to 50k messages)
- **Expected:** (e.g., HPA should have scaled pods to 10 replicas)

## 📊 Environment Data
- **Environment:** (Dev/Stage/Prod)
- **Trace ID:** (If available via Jaeger/OpenTelemetry)
- **Schema Version:** (Avro version used)

## 📸 Screenshots / Logs
Add logs or Prometheus screenshots here.