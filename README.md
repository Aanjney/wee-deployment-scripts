## Edge stack (generic)

Compose + Caddy + scripts for one VPS. Adjust names, paths, and ports for each project.

### 1. Layout on the VPS

```text
~/deploy/
  docker-compose.yml
  Caddyfile
  deploy.sh
  pull-and-deploy-if-changed.sh
  run-with-lock.sh
  env.template          # checklist (comments only)
~/services/<app>/
  Dockerfile
  .env                  # if compose uses env_file
  …
```

### 2. Host prerequisites

- Docker Engine + Compose plugin  
- `git` (for automated pulls)  
- Firewall: **80** and **443**  
- DNS for each public hostname → this server  
- Deploy keys / tokens for private Git remotes (if needed)  

Details and variable names: **`env.template`**.

### 3. Compose and Caddy

1. Edit **`docker-compose.yml`**: service name(s), `build.context` → `../services/<app>`, `expose` port, `healthcheck` if you use Compose health.  
2. Edit **`Caddyfile`**: site address and `reverse_proxy <service>:<port>`.  
3. First boot: `cd ~/deploy && docker compose up -d --build`

### 4. Deploy one service by hand

```bash
export DEPLOY_SERVICE=webapp
export DEPLOY_REPO=/home/you/services/webapp
export DEPLOY_HEALTH_URL=http://127.0.0.1:8000/ready   # or SKIP — see §6
~/deploy/deploy.sh
```

### 5. Cron (per app)

Use a **different** `DEPLOY_LOCK` / `DEPLOY_LOG_FILE` per service so jobs don’t block each other.

```cron
* * * * * DEPLOY_SERVICE=webapi DEPLOY_REPO=/home/you/services/webapi DEPLOY_HEALTH_URL=http://127.0.0.1:8080/health DEPLOY_LOCK=/var/lock/deploy-webapi.lock DEPLOY_LOG_FILE=/var/log/deploy-webapi.log /home/you/deploy/run-with-lock.sh
```

Only the repo that changed is fetched/merged; only that service is rebuilt and rolled.

### 6. Health URL — required?

**For this rolling script:** you need **some** signal that the **new** container is safe before removing the old one.

| Situation | What to use |
|-----------|----------------|
| HTTP API with a probe | `DEPLOY_HEALTH_URL=http://127.0.0.1:<port>/<path>` |
| Nginx (or similar) serving static **from a container** | Same: e.g. `http://127.0.0.1:80/` (200 OK on `/`) |
| No good HTTP target | `DEPLOY_HEALTH_URL=SKIP` and tune `DEPLOY_STABILIZE_SECONDS` (fixed sleep; less safe) |
| **Pure static files** only in Caddy (`root` + `file_server`, **no** backend container) | **Don’t** use this rolling flow for that site. Update files on disk (rsync/git pull on host) and `caddy reload`. No replica swap. |

So: a dedicated health **path** is not mandatory; a **200 from `/`** is enough. True “static-only in Caddy” doesn’t need this script.

### 7. `image:` only (no `build:`)

`docker compose build <service>` may do nothing. Pull new images yourself (e.g. `docker compose pull <service>`) or extend the scripts.
