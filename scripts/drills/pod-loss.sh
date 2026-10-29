#!/usr/bin/env bash
# Drill: a pod disappears (node drain, eviction, manual delete).
# Expected: clients see no errors, the Deployment replaces the pod.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
require_lab_context

pod=$(kubectl -n "$APP_NAMESPACE" get pods -l "app.kubernetes.io/instance=$APP_RELEASE,app.kubernetes.io/component=web" \
  -o jsonpath='{.items[0].metadata.name}')
log "Deleting pod $pod under traffic"
start_load
sleep 2
kubectl -n "$APP_NAMESPACE" delete pod "$pod" --wait=true >/dev/null
kubectl -n "$APP_NAMESPACE" rollout status "deployment/$APP_RELEASE" --timeout=120s >/dev/null
sleep 5
read -r total failed < <(stop_load)

ready=$(kubectl -n "$APP_NAMESPACE" get deployment "$APP_RELEASE" -o jsonpath='{.status.readyReplicas}')
desired=$(kubectl -n "$APP_NAMESPACE" get deployment "$APP_RELEASE" -o jsonpath='{.spec.replicas}')
[[ "$ready" == "$desired" ]] || fail "$ready of $desired replicas ready"
ok "replacement pod ready ($ready/$desired)"
((failed == 0)) || fail "$failed of $total requests failed"
ok "$total requests during the drill, 0 failed"
