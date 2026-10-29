#!/usr/bin/env bash
# Install pinned k3d, helm, kubectl and kubeconform into ./.tools/bin and verify
# each download against its pinned SHA-256. Nothing is installed system-wide.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) fail "unsupported architecture $(uname -m)" ;;
esac

BIN="$REPO_ROOT/.tools/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$BIN"

# download URL FILE SHA256
download() {
  curl --fail --silent --show-error --location --retry 3 -o "$WORK/$2" "$1"
  echo "$3  $WORK/$2" | sha256sum --check --quiet - || fail "checksum mismatch for $2"
}

sha() { local var="${1}_SHA256_${ARCH}"; printf '%s' "${!var}"; }

if [[ "$(k3d version 2>/dev/null | head -1)" != "k3d version $K3D_VERSION" ]]; then
  download "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/k3d-linux-$ARCH" k3d "$(sha K3D)"
  install -m 0755 "$WORK/k3d" "$BIN/k3d"
fi
ok "k3d $K3D_VERSION"

if [[ "$(helm version --template '{{.Version}}' 2>/dev/null)" != "$HELM_VERSION" ]]; then
  download "https://get.helm.sh/helm-$HELM_VERSION-linux-$ARCH.tar.gz" helm.tgz "$(sha HELM)"
  tar -xzf "$WORK/helm.tgz" -C "$WORK" "linux-$ARCH/helm"
  install -m 0755 "$WORK/linux-$ARCH/helm" "$BIN/helm"
fi
ok "helm $HELM_VERSION"

if [[ ! -x "$BIN/kubectl" || "$("$BIN/kubectl" version --client -o json | jq -r .clientVersion.gitVersion)" != "$KUBECTL_VERSION" ]]; then
  download "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl" kubectl "$(sha KUBECTL)"
  install -m 0755 "$WORK/kubectl" "$BIN/kubectl"
fi
ok "kubectl $KUBECTL_VERSION"

if [[ "$(kubeconform -v 2>/dev/null)" != "$KUBECONFORM_VERSION" ]]; then
  download "https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION/kubeconform-linux-$ARCH.tar.gz" kubeconform.tgz "$(sha KUBECONFORM)"
  tar -xzf "$WORK/kubeconform.tgz" -C "$WORK" kubeconform
  install -m 0755 "$WORK/kubeconform" "$BIN/kubeconform"
fi
ok "kubeconform $KUBECONFORM_VERSION"

# Helm plugins live in a repo-local directory as well.
export HELM_PLUGINS="$REPO_ROOT/.tools/helm-plugins"
if ! helm plugin list 2>/dev/null | grep -q "^unittest[[:space:]].*${HELM_UNITTEST_VERSION#v}"; then
  helm plugin uninstall unittest >/dev/null 2>&1 || true
  # helm-unittest releases are not signed with a key Helm 4 knows about.
  helm plugin install https://github.com/helm-unittest/helm-unittest --version "$HELM_UNITTEST_VERSION" --verify=false >/dev/null
fi
ok "helm-unittest $HELM_UNITTEST_VERSION"
