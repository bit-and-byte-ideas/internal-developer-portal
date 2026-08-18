# Local kind + CloudNativePG deployment loop for Backstage.
#
# `make local-up` gets you from a cold devcontainer to a running Backstage
# backed by a real Postgres, all inside a disposable kind cluster:
#   tools -> check-secrets -> kind-up -> cnpg-install -> image-build
#         -> kind-load -> deploy -> wait-db -> wait-app
#
# See deploy/k8s/README.md for the full walkthrough and troubleshooting.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.PHONY: help tools check-secrets kind-up kind-down cnpg-install \
	image-build kind-load deploy wait-db wait-app reload port-forward \
	logs status local-up local-down

CLUSTER_NAME       ?= backstage-local
NAMESPACE          ?= backstage
IMAGE              ?= backstage:local
OVERLAY            ?= deploy/k8s/overlays/local
KIND_CONFIG        ?= deploy/kind/kind-config.yaml
CNPG_CHART_VERSION ?= 0.29.0
DB_CLUSTER         ?= backstage-db
SECRET_FILE        := deploy/k8s/overlays/local/dev/secret-github-credentials.yaml

help: ## Show this help
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## --- Setup ------------------------------------------------------------

tools: ## Verify docker/kubectl/helm/kind are present (all provided by the devcontainer)
	@command -v docker >/dev/null || { echo "docker is required"; exit 1; }
	@command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }
	@command -v helm >/dev/null || { echo "helm is required"; exit 1; }
	@command -v kind >/dev/null || { echo "kind is required"; exit 1; }
	@echo "tools OK ($$(kind version))"

check-secrets: ## Fail if the local GitHub secret is missing; warn if it's still unfilled
	@if [ ! -f "$(SECRET_FILE)" ]; then \
		echo "Missing $(SECRET_FILE)"; \
		echo "Copy $(SECRET_FILE).example to $(SECRET_FILE) and fill in real values."; \
		exit 1; \
	fi
	@if grep -q "REPLACE_WITH_" "$(SECRET_FILE)"; then \
		echo "Warning: $(SECRET_FILE) still has REPLACE_WITH_* placeholders."; \
		echo "  Postgres, catalog sync, and backend health all work regardless -- only interactive GitHub sign-in will fail until this is filled in."; \
	fi

## --- Cluster lifecycle --------------------------------------------------

kind-up: tools ## Create the kind cluster if it doesn't already exist
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER_NAME)"; then \
		echo "kind cluster '$(CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --config $(KIND_CONFIG); \
	fi

kind-down: tools ## Delete the kind cluster (destroys the Postgres volume and all data)
	kind delete cluster --name $(CLUSTER_NAME)

cnpg-install: ## Install the CloudNativePG operator via Helm (idempotent)
	helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
	helm repo update cnpg
	helm upgrade --install cnpg cnpg/cloudnative-pg \
		--namespace cnpg-system --create-namespace \
		--version $(CNPG_CHART_VERSION) \
		--wait --timeout 5m
	@# helm --wait only waits on the operator Deployment; the Cluster CRD and
	@# its validating/mutating webhooks can lag a few seconds behind that
	@# (observed: the operator pod restarts a few times during its own
	@# startup, so Deployment can report Available in between restarts,
	@# before the webhook is stably reachable). `deploy` below also retries
	@# on top of this for the same reason.
	kubectl wait --for=condition=Established crd/clusters.postgresql.cnpg.io --timeout=120s
	kubectl wait --for=condition=Available deploy --all -n cnpg-system --timeout=300s
	kubectl wait --for=jsonpath='{.subsets[0].addresses[0].ip}' \
		endpoints/cnpg-webhook-service -n cnpg-system --timeout=120s

## --- App image + deploy --------------------------------------------------

image-build: ## Build the Backstage Docker image
	docker build -t $(IMAGE) .

kind-load: ## Load the built image into the kind cluster's containerd
	kind load docker-image $(IMAGE) --name $(CLUSTER_NAME)

deploy: check-secrets ## Apply the local overlay (namespace, Postgres cluster, Backstage)
	@# The CNPG operator's Deployment can report Available a moment before its
	@# mutating webhook is actually reachable (leader election / cert
	@# provisioning churn right after startup) -- applying the Cluster CR in
	@# that window fails with "connect: connection refused". Retry rather
	@# than try to perfectly predict readiness.
	@n=0; until [ $$n -ge 5 ]; do \
		kubectl apply -k $(OVERLAY) && exit 0; \
		n=$$((n+1)); \
		echo "deploy failed (attempt $$n/5), retrying in 5s..."; \
		sleep 5; \
	done; \
	echo "deploy failed after 5 attempts"; exit 1

wait-db: ## Wait for the CloudNativePG cluster to be created and Ready
	kubectl wait --for=create cluster/$(DB_CLUSTER) -n $(NAMESPACE) --timeout=60s
	kubectl wait --for=condition=Ready cluster/$(DB_CLUSTER) -n $(NAMESPACE) --timeout=300s

wait-app: ## Wait for the Backstage rollout to finish
	kubectl rollout status deploy/backstage -n $(NAMESPACE) --timeout=300s

reload: image-build kind-load ## Rebuild the image, reload it into kind, and restart Backstage
	kubectl rollout restart deploy/backstage -n $(NAMESPACE)
	$(MAKE) wait-app

## --- Convenience ----------------------------------------------------------

port-forward: ## Forward localhost:7007 to the Backstage service
	kubectl port-forward -n $(NAMESPACE) svc/backstage 7007:7007

logs: ## Tail the Backstage backend logs
	kubectl logs -n $(NAMESPACE) -l app=backstage -f

status: ## One-shot view of pods, services, and the Postgres cluster
	kubectl get pods,svc,cluster -n $(NAMESPACE)

## --- Composite --------------------------------------------------------

local-up: tools check-secrets kind-up cnpg-install image-build kind-load deploy wait-db wait-app ## Full pipeline: cluster, operator, image, deploy
	@echo ""
	@echo "Backstage is running. Run 'make port-forward' then open http://localhost:7007"

local-down: kind-down ## Tear down the kind cluster entirely
