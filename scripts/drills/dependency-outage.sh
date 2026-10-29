#!/usr/bin/env bash
# Drill: a dependency (PostgreSQL or Redis) goes away.
#   scripts/drills/dependency-outage.sh postgres|redis
# Expected: readiness fails so pods leave the load balancer, liveness keeps
# passing so nothing restarts, LaravelAppNoReadyReplicas fires, and the
# service recovers on its own when the dependency returns.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
require_lab_context

case "${1:-}" in
  postgres) workload=statefulset/postgres; name=PostgreSQL ;;
  redis) workload=deployment/redis; name=Redis ;;
  *) fail "usage: $0 postgres|redis" ;;
esac

restarts() {
  kubectl -n "$APP_NAMESPACE" get pods -l "app.kubernetes.io/instance=$APP_RELEASE,app.kubernetes.io/component=web" \
    -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s += $1} END {print s + 0}'
}
no_ready_replicas() {
  [[ "$(kubectl -n "$APP_NAMESPACE" get deployment "$APP_RELEASE" -o jsonpath='{.status.readyReplicas}')" == "" ]]
}
all_ready() {
  local d
  d=$(kubectl -n "$APP_NAMESPACE" get deployment "$APP_RELEASE" -o json)
  jq -e '.status.readyReplicas == .spec.replicas' <<<"$d"
}
ingress_status() { lab_curl app --max-time 5 --output /dev/null --write-out '%{http_code}' "$(lab_url app /ready)" || true; }

before=$(restarts)
started=$SECONDS
log "Stopping $name"
kubectl -n "$APP_NAMESPACE" scale "$workload" --replicas=0 >/dev/null

wait_until 90 "all app pods marked NotReady" no_ready_replicas
# Right after the dependency disappears, requests already routed to a pod can
# hang on the connection; the 3 s probe timeout bounds that window.
ingress_says_unavailable() { [[ "$(ingress_status)" == 503 ]]; }
wait_until 60 "ingress answers 503 while no pod is ready" ingress_says_unavailable
wait_until 240 "alert LaravelAppNoReadyReplicas firing in Prometheus" alert_state_is LaravelAppNoReadyReplicas firing
wait_until 60 "alert visible in Alertmanager" bash -c \
  "source '$REPO_ROOT/scripts/lib.sh'; lab_curl alertmanager --fail '$(lab_url alertmanager /api/v2/alerts)' | jq -e 'any(.[]; .labels.alertname == \"LaravelAppNoReadyReplicas\")'"
detected=$((SECONDS - started))

log "Starting $name again"
kubectl -n "$APP_NAMESPACE" scale "$workload" --replicas=1 >/dev/null
kubectl -n "$APP_NAMESPACE" rollout status "$workload" --timeout=180s >/dev/null
wait_until 120 "all app pods Ready again" all_ready
wait_until 180 "alert resolved" alert_absent LaravelAppNoReadyReplicas

after=$(restarts)
((after == before)) || fail "app containers restarted during the outage ($before -> $after)"
ok "no container restarts (liveness is independent of $name)"
ok "outage detected and alerted after ${detected}s; recovered without intervention"
