#!/usr/bin/env bash
# Drill: a release with broken configuration (wrong Redis host).
# Expected: the new pods never become Ready, the rollout stalls instead of
# replacing healthy pods, Helm marks the release failed, clients see no
# errors, and `helm rollback` restores the last good revision.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
require_lab_context

good_revision=$(helm -n "$APP_NAMESPACE" status "$APP_RELEASE" -o json | jq -r .version)
tag=$(helm -n "$APP_NAMESPACE" get values "$APP_RELEASE" -a -o json | jq -r .image.tag)

log "Deploying a release with REDIS_HOST=redis-typo (expected to fail)"
start_load
if "$REPO_ROOT/scripts/deploy.sh" "$tag" --set env.REDIS_HOST=redis-typo --timeout 90s >/dev/null 2>&1; then
  stop_load >/dev/null
  fail "the broken release was reported as successful"
fi
status=$(helm -n "$APP_NAMESPACE" status "$APP_RELEASE" -o json | jq -r .info.status)
[[ "$status" == failed ]] || fail "release status is $status, expected failed"
ok "Helm marked the release failed"

d=$(kubectl -n "$APP_NAMESPACE" get deployment "$APP_RELEASE" -o json)
jq -e '.status.readyReplicas == .spec.replicas' <<<"$d" >/dev/null || fail "healthy replicas were removed"
ok "old pods kept serving ($(jq -r .status.readyReplicas <<<"$d") ready, $(jq -r '.status.unavailableReplicas // 0' <<<"$d") new pod(s) stuck NotReady)"

log "Rolling back to revision $good_revision"
helm -n "$APP_NAMESPACE" rollback "$APP_RELEASE" "$good_revision" --wait --timeout 5m >/dev/null
read -r total failed < <(stop_load)
((failed == 0)) || fail "$failed of $total requests failed during the drill"
ok "$total requests during the failed release and rollback, 0 failed"
"$REPO_ROOT/scripts/smoke-test.sh" >/dev/null 2>&1 || fail "smoke test failed after rollback"
ok "smoke test passes after rollback"
