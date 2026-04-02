#!/usr/bin/env bash
# Cron wrapper: export DEPLOY_* then run pull-and-deploy-if-changed (serialized per lock file).
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEPLOY_SERVICE:-}" || -z "${DEPLOY_REPO:-}" ]]; then
  echo "error: set DEPLOY_SERVICE and DEPLOY_REPO (e.g. in crontab)" >&2
  exit 1
fi

LOCK="${DEPLOY_LOCK:-/var/lock/deploy-${DEPLOY_SERVICE}.lock}"
LOG="${DEPLOY_LOG_FILE:-/var/log/deploy-${DEPLOY_SERVICE}.log}"

exec 9>"${LOCK}"
if ! flock -n 9; then
  exit 0
fi

{
  echo "=== $(date --utc +%FT%TZ) ${DEPLOY_SERVICE} start ==="
  export DEPLOY_SERVICE
  export DEPLOY_REPO
  export DEPLOY_HEALTH_URL="${DEPLOY_HEALTH_URL:-}"
  export DEPLOY_STABILIZE_SECONDS="${DEPLOY_STABILIZE_SECONDS:-}"
  export DEPLOY_COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-}"
  export DEPLOY_SKIP_ENV_CHECK="${DEPLOY_SKIP_ENV_CHECK:-}"
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"
  export STACK_NAME="${STACK_NAME:-}"
  export DEPLOY_REMOTE="${DEPLOY_REMOTE:-}"
  export DEPLOY_BRANCH="${DEPLOY_BRANCH:-}"
  "${DEPLOY_DIR}/pull-and-deploy-if-changed.sh"
  echo "=== $(date --utc +%FT%TZ) ${DEPLOY_SERVICE} end ==="
} >>"${LOG}" 2>&1
