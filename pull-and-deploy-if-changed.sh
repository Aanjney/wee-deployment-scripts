#!/usr/bin/env bash
# Fetch one repo; if it changed vs upstream, fast-forward and run deploy.sh for that service only.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEPLOY_SERVICE:-}" || -z "${DEPLOY_REPO:-}" ]]; then
  echo "error: set DEPLOY_SERVICE and DEPLOY_REPO" >&2
  exit 1
fi

REMOTE="${DEPLOY_REMOTE:-origin}"
BRANCH="${DEPLOY_BRANCH:-main}"
REMOTE_REF="${REMOTE}/${BRANCH}"

git -C "${DEPLOY_REPO}" fetch "${REMOTE}" "${BRANCH}"

if [[ "$(git -C "${DEPLOY_REPO}" rev-parse HEAD)" == "$(git -C "${DEPLOY_REPO}" rev-parse "${REMOTE_REF}")" ]]; then
  exit 0
fi

echo "$(date --utc +%FT%TZ): ${DEPLOY_SERVICE}: ${REMOTE_REF} advanced; deploying..."
exec "${DEPLOY_DIR}/deploy.sh"
