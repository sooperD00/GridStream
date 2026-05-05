# GridStream Makefile.
#
# This is the Stage-1 adoption surface from ADR-0006: a `Makefile` is
# the first artifact teams adopt, ahead of the shared workflow and the
# chart. Targets here mirror what's documented in docs/paved-road.md.

.DEFAULT_GOAL := help

# ─── Configuration ──────────────────────────────────────────────────────────

# single-source-of-truth
PYTHON_VERSION := $(shell cut -d. -f1,2 .python-version)

# Local Kind cluster name. Override with `make CLUSTER=foo infra-up`.
CLUSTER     ?= gridstream
KIND_CONFIG ?= kind/cluster.yaml

# Stub service.
STUB_NAME  := standard-service-stub
STUB_DIR   := packages/standard-service-stub
STUB_IMAGE := gridstream-$(STUB_NAME):dev

# Standard "make help" niceties.
GREEN := \033[32m
CYAN  := \033[36m
BOLD  := \033[1m
RESET := \033[0m

##@ Workflow

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(CYAN)<target>$(RESET)\n"} \
	    /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2 } \
	    /^##@/ { printf "\n$(BOLD)%s$(RESET)\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Setup

.PHONY: setup
setup: ## Sync workspace dependencies and install pre-commit hooks.
	uv sync --all-extras --dev
	uv run pre-commit install
	uv run pre-commit install --hook-type commit-msg

##@ Quality Gates (ADR-0005, ADR-0011)

.PHONY: lint
lint: ## Ruff check + format check across the workspace.
	uv run ruff check .
	uv run ruff format --check .

.PHONY: typecheck
typecheck: ## Mypy strict type-check on the stub.
	uv run mypy $(STUB_DIR)/src $(STUB_DIR)/tests

.PHONY: test
test: ## Run pytest with the 80% coverage gate.
	uv run pytest $(STUB_DIR)/tests \
		--cov=$(STUB_DIR)/src \
		--cov-report=term-missing \
		--cov-fail-under=80

# [SPRINT-1-CLEANUP] Wire-up verification: confirm `jsonschema` is in dev deps,
# helm is installed locally, then run this target end-to-end. Add the
# corresponding step to .github/workflows/ci.yml during CI review.
.PHONY: check-schema
check-schema: ## Smoke-test charts/standard-service/values.schema.json (ADR-0011).
	@scripts/check-chart-schema.sh

# [SPRINT-1-CLEANUP] Behavior companion to check-schema (ADR-0011).
# check-schema validates the schema FILE is well-formed; this validates
# the schema's BEHAVIOR — that helm actually rejects const-pinned and
# required-field violations at template/install time. Add the
# corresponding step to .github/workflows/ci.yml during CI review.
.PHONY: check-chart
check-chart: ## Verify helm enforces the values schema (ADR-0011 phase 2).
	@scripts/check-chart-behavior.sh

##@ Build (ADR-0009)

.PHONY: build
build: ## Build the stub's distroless production image.
	docker build \
		--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
		-f $(STUB_DIR)/Dockerfile \
		-t $(STUB_IMAGE) \
		.

.PHONY: build-dev
build-dev: ## Build the stub's slim local-dev image (NOT FOR PRODUCTION).
	docker build \
		--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
		-f $(STUB_DIR)/Dockerfile.dev \
		-t $(STUB_IMAGE)-dev \
		.

##@ Local Cluster

.PHONY: infra-up
infra-up: ## Start the local Kind cluster.
	@if kind get clusters 2>/dev/null | grep -q '^$(CLUSTER)$$'; then \
		echo "$(GREEN)→$(RESET) Cluster '$(CLUSTER)' already up."; \
	else \
		kind create cluster --name $(CLUSTER) --config $(KIND_CONFIG); \
	fi

.PHONY: infra-down
infra-down: ## Tear down the local Kind cluster.
	kind delete cluster --name $(CLUSTER)

.PHONY: deploy-local
deploy-local: build check-schema check-chart ## Build, kind-load, and helm-install the stub.
	kind load docker-image $(STUB_IMAGE) --name $(CLUSTER)
	helm upgrade --install $(STUB_NAME) charts/standard-service \
		--set app.name=$(STUB_NAME) \
		--set image.repository=gridstream-$(STUB_NAME) \
		--set image.tag=dev \
		--wait
	@echo ""
	@echo "$(GREEN)Stub deployed.$(RESET) Try:"
	@echo "  kubectl get pods -l app.kubernetes.io/instance=$(STUB_NAME)"
	@echo "  kubectl port-forward svc/$(STUB_NAME) 8000:80"
	@echo "  curl http://localhost:8000/healthz"

.PHONY: smoke-test
smoke-test: ## Smoke-test the deployed standard-service-stub.
	@scripts/smoke-test.sh
