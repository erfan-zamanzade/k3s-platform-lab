# Every target runs against the lab cluster only (k3d context and a
# repository-local kubeconfig); see scripts/lib.sh.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

tools: ## Install pinned k3d, helm, kubectl, kubeconform, helm-unittest into .tools/
	scripts/install-tools.sh

lint: ## Helm lint, unit tests, kubeconform, shellcheck
	scripts/lint.sh

test-alerts: ## promtool unit tests for the alert rules
	scripts/test-alerts.sh

check: lint test-alerts ## All static checks (no cluster needed)

cluster: ## Create the k3d cluster
	scripts/cluster-up.sh

platform: ## Install kube-prometheus-stack, cert-manager and the lab CA
	scripts/install-platform.sh

deploy: ## Deploy datastores and the application (TAG=... to choose the image)
	scripts/deploy.sh $(TAG)

smoke: ## End-to-end checks of the running release
	scripts/smoke-test.sh

rollout: ## Rolling update and rollback under traffic
	scripts/rollout.sh

drills: ## Failure drills: pod loss, PostgreSQL and Redis outages, bad release
	scripts/drills/pod-loss.sh
	scripts/drills/dependency-outage.sh postgres
	scripts/drills/dependency-outage.sh redis
	scripts/drills/bad-release.sh

up: tools cluster platform deploy smoke ## Everything from zero to a verified deployment

demo: up rollout drills ## up, then the rollout demo and all drills

down: ## Delete the cluster
	scripts/cluster-down.sh

.PHONY: help tools lint test-alerts check cluster platform deploy smoke rollout drills up demo down
