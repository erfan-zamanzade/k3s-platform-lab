#!/usr/bin/env bash
# Delete the lab cluster and its kubeconfig. Touches nothing else.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

k3d cluster delete "$CLUSTER_NAME"
rm -f "$KUBECONFIG" "$LAB_CA_FILE"
