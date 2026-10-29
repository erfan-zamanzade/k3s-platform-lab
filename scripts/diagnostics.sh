#!/usr/bin/env bash
# Collect cluster state for debugging a failed run (CI uploads the result).
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

out="$REPO_ROOT/diagnostics"
mkdir -p "$out"
kubectl get nodes -o wide >"$out/nodes.txt" 2>&1
kubectl get all,ingress,certificates,networkpolicies,pdb -A -o wide >"$out/resources.txt" 2>&1
kubectl get events -A --sort-by=.lastTimestamp >"$out/events.txt" 2>&1
kubectl -n "$APP_NAMESPACE" describe pods >"$out/app-pods.txt" 2>&1
for pod in $(kubectl -n "$APP_NAMESPACE" get pods -o name 2>/dev/null); do
  kubectl -n "$APP_NAMESPACE" logs "$pod" --all-containers --tail=300 >"$out/logs-${pod#pod/}.txt" 2>&1
done
helm list -A >"$out/helm-releases.txt" 2>&1
helm -n "$APP_NAMESPACE" history "$APP_RELEASE" >"$out/helm-history.txt" 2>&1
log "diagnostics written to $out"
