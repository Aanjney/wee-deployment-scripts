#!/usr/bin/env bash
# Build and redeploy one compose service after git pull.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEPLOY_SERVICE:-}" || -z "${DEPLOY_REPO:-}" ]]; then
  echo "error: set DEPLOY_SERVICE and DEPLOY_REPO" >&2
  exit 1
fi

COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-${DEPLOY_DIR}/docker-compose.yml}"
COMPOSE=(docker compose -f "${COMPOSE_FILE}")

if [[ ! -d "${DEPLOY_REPO}/.git" ]]; then
  echo "error: not a git repo: ${DEPLOY_REPO}" >&2
  exit 1
fi

if [[ "${DEPLOY_SKIP_ENV_CHECK:-0}" != "1" && ! -f "${DEPLOY_REPO}/.env" ]]; then
  echo "error: missing ${DEPLOY_REPO}/.env (or set DEPLOY_SKIP_ENV_CHECK=1)" >&2
  exit 1
fi

git -C "${DEPLOY_REPO}" pull --ff-only

export BUILD_VERSION
BUILD_VERSION="$(git -C "${DEPLOY_REPO}" rev-parse HEAD)"
echo "$(date --utc +%FT%TZ): ${DEPLOY_SERVICE} sha=${BUILD_VERSION}"

cd "$(dirname "${COMPOSE_FILE}")"
"${COMPOSE[@]}" build "${DEPLOY_SERVICE}"
"${COMPOSE[@]}" up -d --no-deps --force-recreate "${DEPLOY_SERVICE}"
"${COMPOSE[@]}" exec -T caddy caddy reload --config /etc/caddy/Caddyfile

echo "$(date --utc +%FT%TZ): done."
