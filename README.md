# wee-deployment-scripts

Single-machine deployment with Docker Compose + Caddy.

## Layout

```text
~/wee-deployment-scripts/
  docker-compose.yml
  Caddyfile
  deploy.sh
  run-with-lock.sh
  pull-and-deploy-if-changed.sh
  env.template
  templates/
    docker-compose.service.yml
    Caddyfile.site

~/services/<app>/
  .env
  data/
  Dockerfile            # internal apps only
```

**Dependencies:** Docker, compose plugin, git, ports 80/443 open, DNS pointing at this host.

## Deploy / update everything

```bash
cd ~/wee-deployment-scripts
docker compose up -d
```

## Type 1 — Third-party Docker image

Currently hosted: Linkwarden, Memos, Vaultwarden, Beszel.

1. `mkdir -p ~/services/<app>/data` and create `~/services/<app>/.env`
2. Copy the `myservice` block from `templates/docker-compose.service.yml` into `docker-compose.yml`. Rename placeholders. Add to `caddy.depends_on`.
3. Copy `templates/Caddyfile.site` into `Caddyfile`. Set domain and port.
4. Start:

```bash
docker compose up -d <app>
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Update: images are pinned to exact versions, and Diun posts to ntfy when a newer tag exists. Bump the tag in `docker-compose.yml`, check the release notes for required intermediate versions, then `docker compose pull <app> && docker compose up -d <app>`.

** Beszel agent uses `network_mode: host` 

## Type 2 — Internal app (build from source)

Example: `pysparkassist`.

1. Clone to `~/services/<app>`, copy and edit `.env`
2. Copy the `myapp` block from `templates/docker-compose.service.yml` into `docker-compose.yml`. Add sidecars and `depends_on` if needed. Add to `caddy.depends_on`.
3. Copy `templates/Caddyfile.site` into `Caddyfile`. Set domain and port.
4. Start:

```bash
docker compose up -d --build <app>
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Deploy: `DEPLOY_SERVICE=<app> DEPLOY_REPO=~/services/<app> ~/wee-deployment-scripts/deploy.sh`

Auto-deploy via cron — see `env.template`.

## Environment variables


| Where                   | What                                                               |
| ----------------------- | ------------------------------------------------------------------ |
| `~/services/<app>/.env` | App secrets and config                                             |
| Compose `environment:`  | Docker-network wiring only (e.g. `QDRANT_URL: http://qdrant:6333`) |
| Cron env                | `DEPLOY_*` vars for auto-deploy                                    |


## Caddy reload

After editing `Caddyfile`:

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Backups

Bind-mounted data lives in `~/services/<app>/data/`. Back up those directories.

## Rollback

Type 1: re-pull a pinned tag or previous image digest.

Type 2: `git checkout <sha>` in the service repo, then run `deploy.sh`.