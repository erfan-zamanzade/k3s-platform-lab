#!/usr/bin/env bash
# Render the chart's PrometheusRule and unit-test it with promtool.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

out="$REPO_ROOT/tests/alerts/rendered-rules.yaml"
helm template laravel-app "$REPO_ROOT/charts/laravel-app" --namespace app \
  --show-only templates/prometheusrule.yaml \
  | docker run --rm -i "$YQ_IMAGE" '.spec' >"$out"
docker run --rm --user "$(id -u):$(id -g)" -v "$REPO_ROOT/tests/alerts:/rules:ro" -w /rules \
  --entrypoint promtool "$PROMETHEUS_IMAGE" check rules rendered-rules.yaml
docker run --rm --user "$(id -u):$(id -g)" -v "$REPO_ROOT/tests/alerts:/rules:ro" -w /rules \
  --entrypoint promtool "$PROMETHEUS_IMAGE" test rules laravel-app.test.yaml
