#!/usr/bin/env bash
# Deploy the lab datastores and the application chart.
#   scripts/deploy.sh [image-tag] [extra helm args...]
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_lab_context

TAG="${1:-$APP_RELEASE_TAG}"
shift || true

kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# The database password is generated once and shared by PostgreSQL and the app
# through a Secret; it never appears in values files or Helm release data.
if ! kubectl -n "$APP_NAMESPACE" get secret app-db >/dev/null 2>&1; then
  kubectl -n "$APP_NAMESPACE" create secret generic app-db \
    --from-literal=username=app \
    --from-literal=password="$(openssl rand -hex 24)" >/dev/null
  ok "generated database credentials (Secret $APP_NAMESPACE/app-db)"
fi

log "Applying lab datastores (PostgreSQL, Redis)"
kubectl -n "$APP_NAMESPACE" apply -k "$REPO_ROOT/platform/datastores" >/dev/null
kubectl -n "$APP_NAMESPACE" rollout status statefulset/postgres --timeout=180s >/dev/null
kubectl -n "$APP_NAMESPACE" rollout status deployment/redis --timeout=120s >/dev/null
ok "datastores ready"

values=(--values "$REPO_ROOT/environments/lab/values.yaml")
if [[ -n "${LAB_EXTRA_VALUES:-}" ]]; then
  values+=(--values "$LAB_EXTRA_VALUES")
fi

log "Deploying $APP_RELEASE with image tag $TAG"
helm upgrade --install "$APP_RELEASE" "$REPO_ROOT/charts/laravel-app" \
  --namespace "$APP_NAMESPACE" \
  "${values[@]}" \
  --set image.tag="$TAG" \
  --wait --timeout 5m \
  "$@"
kubectl -n "$APP_NAMESPACE" wait --for=condition=Ready "certificate/$APP_RELEASE-tls" --timeout=120s >/dev/null
ok "$APP_RELEASE deployed: $(helm -n "$APP_NAMESPACE" status "$APP_RELEASE" -o json | jq -r '"revision \(.version), \(.info.status)"')"
