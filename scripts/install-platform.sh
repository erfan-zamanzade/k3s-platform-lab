#!/usr/bin/env bash
# Install the platform layer: kube-prometheus-stack, cert-manager and the lab CA.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_lab_context

for ns in "$MONITORING_NAMESPACE" cert-manager; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

# Grafana's admin password is generated once per cluster and only lives in a Secret.
if ! kubectl -n "$MONITORING_NAMESPACE" get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n "$MONITORING_NAMESPACE" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 24)" >/dev/null
  ok "generated Grafana admin password (Secret $MONITORING_NAMESPACE/grafana-admin)"
fi

# The monitoring stack goes first: it brings the ServiceMonitor CRD that
# cert-manager's own metrics configuration uses.
log "Installing kube-prometheus-stack $KUBE_PROMETHEUS_STACK_CHART_VERSION"
helm upgrade --install monitoring oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_CHART_VERSION" \
  --namespace "$MONITORING_NAMESPACE" \
  --values "$REPO_ROOT/platform/monitoring/values.yaml" \
  --wait --timeout 10m
ok "kube-prometheus-stack ready"

log "Installing cert-manager $CERT_MANAGER_CHART_VERSION"
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version "$CERT_MANAGER_CHART_VERSION" \
  --namespace cert-manager \
  --values "$REPO_ROOT/platform/cert-manager/values.yaml" \
  --wait --timeout 5m
ok "cert-manager ready"

kubectl apply -f "$REPO_ROOT/platform/cert-manager/issuers.yaml" >/dev/null
wait_until 120 "lab CA certificate issued" \
  kubectl -n cert-manager wait --for=condition=Ready certificate/lab-ca --timeout=5s
wait_until 120 "lab-ca ClusterIssuer ready" \
  kubectl wait --for=condition=Ready clusterissuer/lab-ca --timeout=5s
fetch_lab_ca

for cert in grafana-tls prometheus-tls alertmanager-tls; do
  wait_until 180 "certificate $cert issued" \
    kubectl -n "$MONITORING_NAMESPACE" wait --for=condition=Ready "certificate/$cert" --timeout=5s
done
wait_until 120 "Grafana answers over verified TLS" lab_curl grafana --fail "$(lab_url grafana /api/health)"
wait_until 120 "Prometheus answers over verified TLS" lab_curl prometheus --fail "$(lab_url prometheus /-/ready)"
