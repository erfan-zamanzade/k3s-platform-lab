# Shared helpers for the lab scripts. Source it, don't execute it.
# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# shellcheck source=scripts/versions.sh
source "$REPO_ROOT/scripts/versions.sh"

export CLUSTER_NAME="${CLUSTER_NAME:-platform-lab}"
export LAB_HTTPS_PORT="${LAB_HTTPS_PORT:-8443}"
export LAB_HTTP_PORT="${LAB_HTTP_PORT:-8088}"
export LAB_DOMAIN="${LAB_DOMAIN:-lab.test}"
export APP_NAMESPACE="${APP_NAMESPACE:-app}"
export APP_RELEASE="${APP_RELEASE:-laravel-app}"
export MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

# Tools are installed per repository, and the lab gets its own kubeconfig, so
# nothing here can read or change a kubeconfig that points at a real cluster.
export PATH="$REPO_ROOT/.tools/bin:$PATH"
export KUBECONFIG="$REPO_ROOT/.kube/config"

LAB_CA_FILE="$REPO_ROOT/.kube/lab-ca.crt"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
ok() { printf '\033[1;32m  ✓\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# Refuse to run against anything but the lab cluster.
require_lab_context() {
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == "k3d-$CLUSTER_NAME" ]] \
    || fail "kubectl context is '${ctx:-<none>}', expected 'k3d-$CLUSTER_NAME'. Run 'make cluster' first."
}

# Export the lab CA so curl can verify the ingress certificates (no -k).
fetch_lab_ca() {
  kubectl -n cert-manager get secret lab-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$LAB_CA_FILE"
}

# curl through the k3d load balancer with real TLS verification, without DNS:
# every <name>.lab.test host resolves to the published port on 127.0.0.1.
lab_curl() {
  local host="$1"; shift
  [[ -s "$LAB_CA_FILE" ]] || fetch_lab_ca
  curl --silent --show-error --max-time 10 \
    --cacert "$LAB_CA_FILE" \
    --resolve "$host.$LAB_DOMAIN:$LAB_HTTPS_PORT:127.0.0.1" \
    "$@"
}

lab_url() { printf 'https://%s.%s:%s%s' "$1" "$LAB_DOMAIN" "$LAB_HTTPS_PORT" "${2:-}"; }

# Run a PromQL instant query through the Prometheus ingress; prints the JSON result.
prom_query() {
  lab_curl prometheus --get --data-urlencode "query=$1" "$(lab_url prometheus /api/v1/query)"
}

# Poll a command until it succeeds or the timeout (seconds) expires.
wait_until() {
  local timeout="$1" description="$2"; shift 2
  local deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || fail "timed out after ${timeout}s waiting for: $description"
    sleep 3
  done
  ok "$description"
}

# Background traffic through the ingress, one request every 200 ms, so
# rollouts and drills can be judged by what a client actually saw.
LOAD_PID=""
LOAD_LOG=""
start_load() {
  LOAD_LOG="$(mktemp)"
  [[ -s "$LAB_CA_FILE" ]] || fetch_lab_ca
  (
    while true; do
      # curl prints 000 itself when no HTTP response arrives.
      lab_curl app --output /dev/null --write-out '%{http_code}\n' "$(lab_url app /)" >>"$LOAD_LOG" 2>/dev/null || true
      sleep 0.2
    done
  ) &
  LOAD_PID=$!
}

# Stop the traffic and print "<total> <failed>"; anything but HTTP 200 counts as failed.
stop_load() {
  [[ -n "$LOAD_PID" ]] && kill "$LOAD_PID" 2>/dev/null && wait "$LOAD_PID" 2>/dev/null || true
  LOAD_PID=""
  local total failed
  total=$(wc -l <"$LOAD_LOG")
  failed=$(grep -cv '^200$' "$LOAD_LOG" || true)
  if ((failed > 0)); then
    log "non-200 responses: $(grep -v '^200$' "$LOAD_LOG" | sort | uniq -c | tr -s ' ' | paste -sd, -)"
  fi
  rm -f "$LOAD_LOG"
  echo "$total $failed"
}

# True when the named alert is in the given state (firing|pending) in Prometheus.
alert_state_is() {
  prom_query "ALERTS{alertname=\"$1\", alertstate=\"$2\"}" | jq -e '.data.result | length > 0'
}

alert_absent() {
  prom_query "ALERTS{alertname=\"$1\"}" | jq -e '.data.result | length == 0'
}
