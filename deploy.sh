#!/usr/bin/env bash
# Rolling deploy for ONE compose service: git pull, build that service, scale 2→wait→1, reload Caddy.
# Other services stay running unless this deploy fails mid-roll.
#
# Required:
#   DEPLOY_SERVICE   compose service name (e.g. webapp)
#   DEPLOY_REPO      absolute path to that service’s git clone
#
# Wait for new replica — pick one:
#   DEPLOY_HEALTH_URL=http://127.0.0.1:PORT/path   curl until OK (default if unset: see below)
#   DEPLOY_HEALTH_URL=SKIP                         sleep DEPLOY_STABILIZE_SECONDS (no curl)
#
# Optional:
#   DEPLOY_COMPOSE_FILE, COMPOSE_PROJECT_NAME / STACK_NAME, DEPLOY_SKIP_ENV_CHECK=1
#   DEPLOY_STABILIZE_SECONDS  (default 25, used with SKIP)
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEPLOY_SERVICE:-}" || -z "${DEPLOY_REPO:-}" ]]; then
  echo "error: set DEPLOY_SERVICE and DEPLOY_REPO (see deploy/env.template)" >&2
  exit 1
fi

SERVICE="${DEPLOY_SERVICE}"
COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-${DEPLOY_DIR}/docker-compose.yml}"
COMPOSE=(docker compose -f "${COMPOSE_FILE}")
STACK_NAME="${COMPOSE_PROJECT_NAME:-${STACK_NAME:-edge}}"
HEALTH_URL="${DEPLOY_HEALTH_URL:-}"
STABILIZE="${DEPLOY_STABILIZE_SECONDS:-25}"

if [[ ! -d "${DEPLOY_REPO}/.git" ]]; then
  echo "error: not a git repo: ${DEPLOY_REPO}" >&2
  exit 1
fi

if [[ "${DEPLOY_SKIP_ENV_CHECK:-0}" != "1" && ! -f "${DEPLOY_REPO}/.env" ]]; then
  echo "error: missing ${DEPLOY_REPO}/.env (or set DEPLOY_SKIP_ENV_CHECK=1)" >&2
  exit 1
fi

if [[ ! -f "$(dirname "${COMPOSE_FILE}")/Caddyfile" ]]; then
  echo "error: missing Caddyfile next to compose ($(dirname "${COMPOSE_FILE}")/Caddyfile)" >&2
  exit 1
fi

git -C "${DEPLOY_REPO}" pull --ff-only

export BUILD_VERSION
BUILD_VERSION="$(git -C "${DEPLOY_REPO}" rev-parse HEAD)"
echo "$(date --utc +%FT%TZ): service=${SERVICE} repo=${DEPLOY_REPO} sha=${BUILD_VERSION}"

cd "$(dirname "${COMPOSE_FILE}")"
echo "$(date --utc +%FT%TZ): docker compose build ${SERVICE}..."
BUILD_VERSION="${BUILD_VERSION}" "${COMPOSE[@]}" build "${SERVICE}"

mapfile -t OLD_IDS < <("${COMPOSE[@]}" ps -q "${SERVICE}" 2>/dev/null || true)

_reload_caddy() {
  local cid
  cid="$(docker ps -qf "name=${STACK_NAME}-caddy" | head -n1 || true)"
  if [[ -z "${cid}" ]]; then
    echo "$(date --utc +%FT%TZ): caddy container not found; skip reload" >&2
    return 0
  fi
  echo "$(date --utc +%FT%TZ): reloading caddy (${cid})..."
  docker exec "${cid}" caddy reload --config /etc/caddy/Caddyfile || true
}

_wait_new_replica() {
  local id="$1"
  if [[ "${HEALTH_URL}" == "SKIP" || "${HEALTH_URL}" == "skip" ]]; then
    echo "$(date --utc +%FT%TZ): no HTTP probe (DEPLOY_HEALTH_URL=SKIP); sleeping ${STABILIZE}s..."
    sleep "${STABILIZE}"
    return 0
  fi
  if [[ -z "${HEALTH_URL}" ]]; then
    echo "$(date --utc +%FT%TZ): warning: DEPLOY_HEALTH_URL unset; sleeping ${STABILIZE}s (set URL or SKIP explicitly)" >&2
    sleep "${STABILIZE}"
    return 0
  fi
  echo "$(date --utc +%FT%TZ): waiting for ${HEALTH_URL} in ${id}..."
  local ok=false
  for _ in $(seq 1 120); do
    if docker exec "${id}" curl -sf "${HEALTH_URL}" >/dev/null 2>&1; then
      ok=true
      break
    fi
    sleep 5
  done
  if [[ "${ok}" != true ]]; then
    echo "error: health check failed; leaving 2 replicas for inspection" >&2
    return 1
  fi
  return 0
}

mapfile -t ANY_STACK < <("${COMPOSE[@]}" ps -q 2>/dev/null || true)

if [[ ${#OLD_IDS[@]} -eq 0 ]]; then
  echo "$(date --utc +%FT%TZ): no running replica for ${SERVICE}..."
  if [[ ${#ANY_STACK[@]} -eq 0 ]]; then
    echo "$(date --utc +%FT%TZ): cold start — full stack..."
    BUILD_VERSION="${BUILD_VERSION}" "${COMPOSE[@]}" up -d --build
  else
    echo "$(date --utc +%FT%TZ): starting / updating ${SERVICE} only..."
    BUILD_VERSION="${BUILD_VERSION}" "${COMPOSE[@]}" up -d --build "${SERVICE}"
  fi
  _reload_caddy
  echo "$(date --utc +%FT%TZ): done."
  exit 0
fi

echo "$(date --utc +%FT%TZ): scaling ${SERVICE} to 2 replicas..."
BUILD_VERSION="${BUILD_VERSION}" "${COMPOSE[@]}" up -d --no-deps --scale "${SERVICE}=2" --no-recreate "${SERVICE}"

NEW_ID=""
mapfile -t ALL_IDS < <("${COMPOSE[@]}" ps -q "${SERVICE}")
for id in "${ALL_IDS[@]}"; do
  skip=false
  for old in "${OLD_IDS[@]}"; do
    if [[ "${id}" == "${old}" ]]; then skip=true; break; fi
  done
  if [[ "${skip}" == false ]]; then NEW_ID="${id}"; break; fi
done

if [[ -z "${NEW_ID}" ]]; then
  echo "error: could not find new container id after scale-up" >&2
  exit 1
fi

if ! _wait_new_replica "${NEW_ID}"; then
  exit 1
fi

echo "$(date --utc +%FT%TZ): removing old replica(s)..."
for old in "${OLD_IDS[@]}"; do docker rm -f "${old}" 2>/dev/null || true; done

echo "$(date --utc +%FT%TZ): scaling ${SERVICE} back to 1..."
BUILD_VERSION="${BUILD_VERSION}" "${COMPOSE[@]}" up -d --no-deps --scale "${SERVICE}=1" "${SERVICE}"

_reload_caddy
echo "$(date --utc +%FT%TZ): deploy complete (${SERVICE})."
