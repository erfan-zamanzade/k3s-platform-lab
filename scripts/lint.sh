#!/usr/bin/env bash
# Static checks: Helm lint, unit tests, schema validation of every manifest
# and shell script analysis. No cluster needed.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
export HELM_PLUGINS="$REPO_ROOT/.tools/helm-plugins"

CHART="$REPO_ROOT/charts/laravel-app"
LAB_VALUES="$REPO_ROOT/environments/lab/values.yaml"

log "helm lint"
helm lint --strict "$CHART" --values "$LAB_VALUES" >/dev/null
helm lint --strict "$CHART" >/dev/null
ok "chart lints cleanly with default and lab values"

log "helm unittest"
helm unittest "$CHART" | tail -n 4

log "kubeconform"
# Built-in kinds from the Kubernetes schemas; cert-manager and Prometheus
# Operator kinds from the community CRD catalog.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
{
  helm template laravel-app "$CHART" --namespace app --values "$LAB_VALUES"
  echo '---'
  kubectl kustomize "$REPO_ROOT/platform/datastores"
  echo '---'
  cat "$REPO_ROOT/platform/cert-manager/issuers.yaml"
} | kubeconform -strict -summary \
  -kubernetes-version "$(sed -E 's/.*:v([0-9.]+)-.*/\1/' <<<"$K3S_IMAGE")" \
  -schema-location default -schema-location "$CRD_SCHEMAS" 2>&1 \
  | sed 's/^/  /'

log "shellcheck"
docker run --rm -v "$REPO_ROOT:/mnt:ro" -w /mnt "$SHELLCHECK_IMAGE" -x scripts/*.sh scripts/drills/*.sh
ok "shell scripts are clean"
