#!/usr/bin/env bash
# Create the k3d cluster and write its kubeconfig to ./.kube/config.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

mkdir -p "$REPO_ROOT/.kube"
if k3d cluster list -o json | jq -e --arg n "$CLUSTER_NAME" 'any(.[]; .name == $n)' >/dev/null; then
  log "Cluster $CLUSTER_NAME already exists"
else
  log "Creating cluster $CLUSTER_NAME ($K3S_IMAGE, HTTPS on 127.0.0.1:$LAB_HTTPS_PORT)"
  k3d cluster create --config "$REPO_ROOT/k3d/cluster.yaml"
fi
k3d kubeconfig get "$CLUSTER_NAME" >"$KUBECONFIG"
chmod 600 "$KUBECONFIG"
kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null
require_lab_context

wait_until 180 "all nodes Ready" kubectl wait --for=condition=Ready nodes --all --timeout=5s
wait_until 240 "Traefik ingress controller running" \
  kubectl -n kube-system rollout status deployment/traefik --timeout=5s
kubectl get nodes -o wide
