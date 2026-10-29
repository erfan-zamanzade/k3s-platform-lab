#!/usr/bin/env bash
# End-to-end checks of a deployed release, from the outside in:
# TLS ingress -> app endpoints -> network policy -> monitoring wiring -> helm test.
#   scripts/smoke-test.sh [expected-version]
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_lab_context

EXPECTED_VERSION="${1:-}"
DEPLOY="$APP_RELEASE"

log "Application through the ingress (TLS verified against the lab CA)"
body=$(lab_curl app --fail "$(lab_url app /health)")
[[ "$(jq -r .status <<<"$body")" == ok ]] || fail "/health: $body"
ok "/health is ok"

body=$(lab_curl app --fail "$(lab_url app /ready)")
[[ "$(jq -r '.checks.database.status + "," + .checks.cache.status' <<<"$body")" == ok,ok ]] || fail "/ready: $body"
ok "/ready: database and cache reachable"

info=$(lab_curl app --fail "$(lab_url app /)")
version=$(jq -r .version <<<"$info")
if [[ -n "$EXPECTED_VERSION" && "$version" != "$EXPECTED_VERSION" ]]; then
  fail "/ reports version $version, expected $EXPECTED_VERSION"
fi
ok "/ reports version $version (commit $(jq -r .commit <<<"$info"))"

lab_curl app --fail "$(lab_url app /metrics)" | grep -q '^app_info{' || fail "/metrics has no app_info"
ok "/metrics exposes app_info"

issuer=$(echo | openssl s_client -connect "127.0.0.1:$LAB_HTTPS_PORT" -servername "app.$LAB_DOMAIN" 2>/dev/null \
  | openssl x509 -noout -issuer)
[[ "$issuer" == *"k3s-platform-lab CA"* ]] || fail "unexpected certificate issuer: $issuer"
ok "certificate issued by the lab CA via cert-manager"

log "Network policy"
image=$(kubectl -n "$APP_NAMESPACE" get deployment "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')
# probe NAME LABELS: try to open a TCP connection to PostgreSQL from a
# throwaway pod, up to 8 times over ~20 s (policy rules for a brand-new pod IP
# take a moment to sync). Succeeds as soon as one connection is accepted.
probe() {
  local overrides
  overrides=$(jq -cn --argjson labels "$2" '{metadata: {labels: $labels}, spec: {automountServiceAccountToken: false,
    securityContext: {runAsNonRoot: true, runAsUser: 82, seccompProfile: {type: "RuntimeDefault"}},
    containers: [{name: "probe", image: "'"$image"'", command: ["php", "-r", "for ($i = 0; $i < 8; $i++) { if (@fsockopen(\"postgres\", 5432, $e, $s, 2)) exit(0); sleep(2); } exit(1);"],
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}')
  kubectl -n "$APP_NAMESPACE" run "$1" --image="$image" --restart=Never --rm --quiet --attach \
    --overrides="$overrides" --pod-running-timeout=90s --request-timeout=0 >/dev/null 2>&1
}
probe np-probe-denied '{"run": "np-probe"}' && fail "a pod without the db-client label reached PostgreSQL"
ok "pod without the db-client label cannot reach PostgreSQL"
probe np-probe-allowed '{"run": "np-probe", "db-client": "true"}' || fail "a db-client pod could not reach PostgreSQL"
ok "pod with the db-client label reaches PostgreSQL"

log "Monitoring"
replicas=$(kubectl -n "$APP_NAMESPACE" get deployment "$DEPLOY" -o jsonpath='{.spec.replicas}')
wait_until 120 "Prometheus scrapes all $replicas pods" \
  bash -c "source '$REPO_ROOT/scripts/lib.sh'; prom_query 'sum(up{namespace=\"$APP_NAMESPACE\", job=\"$DEPLOY\"})' | jq -e '.data.result[0].value[1] == \"$replicas\"'"
lab_curl prometheus --fail "$(lab_url prometheus /api/v1/rules)" \
  | jq -e '[.data.groups[].rules[].name] | index("LaravelAppNoReadyReplicas")' >/dev/null \
  || fail "alert rules not loaded"
ok "alert rules loaded in Prometheus"
grafana_password=$(kubectl -n "$MONITORING_NAMESPACE" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)
wait_until 90 "Grafana has the laravel-app dashboard" \
  lab_curl grafana --fail --user "admin:$grafana_password" "$(lab_url grafana /api/dashboards/uid/laravel-app)"

log "helm test"
helm -n "$APP_NAMESPACE" test "$APP_RELEASE" --timeout 2m >/dev/null
ok "helm test passed"

log "All smoke tests passed"
