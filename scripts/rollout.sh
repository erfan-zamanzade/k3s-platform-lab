#!/usr/bin/env bash
# Rolling update and rollback under live traffic:
#   1. deploy APP_PREVIOUS_TAG (starting point)
#   2. upgrade to APP_RELEASE_TAG while a client sends requests
#   3. roll back to the previous Helm revision, again under traffic
#   4. roll forward to APP_RELEASE_TAG
# Fails if any request during steps 2 or 3 gets a non-200 answer.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_lab_context

serving() { lab_curl app --fail "$(lab_url app /)" | jq -r .version; }

"$REPO_ROOT/scripts/deploy.sh" "$APP_PREVIOUS_TAG" >/dev/null
from_revision=$(helm -n "$APP_NAMESPACE" status "$APP_RELEASE" -o json | jq -r .version)
[[ "$(serving)" == "$APP_PREVIOUS_TAG" ]] || fail "expected $APP_PREVIOUS_TAG to be serving"
ok "serving $APP_PREVIOUS_TAG (Helm revision $from_revision)"

log "Rolling update to $APP_RELEASE_TAG under traffic"
start_load
"$REPO_ROOT/scripts/deploy.sh" "$APP_RELEASE_TAG" >/dev/null
read -r total failed < <(stop_load)
[[ "$(serving)" == "$APP_RELEASE_TAG" ]] || fail "update did not switch to $APP_RELEASE_TAG"
((failed == 0)) || fail "rolling update: $failed of $total requests failed"
ok "now serving $APP_RELEASE_TAG; $total requests during the update, 0 failed"

log "Rollback to revision $from_revision under traffic"
start_load
helm -n "$APP_NAMESPACE" rollback "$APP_RELEASE" "$from_revision" --wait --timeout 5m >/dev/null
read -r total failed < <(stop_load)
[[ "$(serving)" == "$APP_PREVIOUS_TAG" ]] || fail "rollback did not restore $APP_PREVIOUS_TAG"
((failed == 0)) || fail "rollback: $failed of $total requests failed"
ok "back on $APP_PREVIOUS_TAG; $total requests during the rollback, 0 failed"

log "Rolling forward to $APP_RELEASE_TAG"
"$REPO_ROOT/scripts/deploy.sh" "$APP_RELEASE_TAG" >/dev/null
[[ "$(serving)" == "$APP_RELEASE_TAG" ]] || fail "roll forward did not switch to $APP_RELEASE_TAG"
ok "serving $APP_RELEASE_TAG"
helm -n "$APP_NAMESPACE" history "$APP_RELEASE" --max 4
