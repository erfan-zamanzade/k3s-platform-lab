# shellcheck shell=bash
# Pinned versions for every tool and chart used by the lab, in one place.
# Sourced by the other scripts and by CI. Checksums are the upstream SHA-256
# values of the release artifacts.

export K3S_IMAGE="rancher/k3s:v1.37.1-k3s1"

export K3D_VERSION="v5.9.0"
export K3D_SHA256_amd64="06d8f25bc3a971c4eb29e0ff08429b180402db0f4dec838c9eac427e296800a0"
export K3D_SHA256_arm64="03cde5cf23e6e8e67de5a039ecf26e5b85aca82fba3e5d13dadf904cd218a250"

export HELM_VERSION="v4.3.1"
export HELM_SHA256_amd64="0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b"
export HELM_SHA256_arm64="8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88"

export KUBECTL_VERSION="v1.37.2"
export KUBECTL_SHA256_amd64="c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4"
export KUBECTL_SHA256_arm64="fcc16f63186659d9722014b7e02d5fdd2d4e669cb8c0ab66365d7d3b8ba03509"

export KUBECONFORM_VERSION="v0.8.0"
export KUBECONFORM_SHA256_amd64="9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883"
export KUBECONFORM_SHA256_arm64="1f53fc8e81258197a35e8603054162a5af1de8c5af13746c71ab680d9534ed87"

export HELM_UNITTEST_VERSION="v1.2.1"

# Charts
export CERT_MANAGER_CHART_VERSION="v1.21.3"
export KUBE_PROMETHEUS_STACK_CHART_VERSION="92.15.0"

# Container images used for linting and rule tests (no local install needed)
export PROMETHEUS_IMAGE="prom/prometheus:v3.15.1"
export SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0"

# Application images (published by github.com/erfan-zamanzade/laravel-cicd-pipeline)
export APP_IMAGE_REPO="ghcr.io/erfan-zamanzade/laravel-cicd-pipeline"
# Current release, and the one before it for the rollout and rollback demo.
# 1.0.1 fixes the Redis outage bug that the dependency drill found in 1.0.0.
export APP_RELEASE_TAG="1.0.1"
export APP_PREVIOUS_TAG="1.0.0"
export YQ_IMAGE="mikefarah/yq:4.54.1"
