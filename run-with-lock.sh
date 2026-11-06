#!/usr/bin/env bash
# Cron wrapper: flock, then pull-and-deploy-if-changed. Logs only deploys and errors.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEPLOY_SERVICE:-}" || -z "${DEPLOY_REPO:-}" ]]; then
  echo "error: set DEPLOY_SERVICE and DEPLOY_REPO" >&2
  exit 1
fi

LOCK="${DEPLOY_LOCK:-/var/lock/deploy-${DEPLOY_SERVICE}.lock}"
LOG="${DEPLOY_LOG_FILE:-/var/log/deploy-${DEPLOY_SERVICE}.log}"

exec 9>"${LOCK}"
if ! flock -n 9; then
  exit 0
fi

export DEPLOY_SERVICE DEPLOY_REPO
"${DEPLOY_DIR}/pull-and-deploy-if-changed.sh" >>"${LOG}" 2>&1
