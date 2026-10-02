# Operations

Everything you need to deploy, configure, tune and tear down a ProvingPod host.
For the internals, see [architecture.md](architecture.md).

## Requirements

- Docker Engine **20.10+** (tested on 29.x). The `docker compose` plugin is **optional** —
  `deploy/deploy.sh` uses plain `docker run` so it works everywhere.
- Internet access during **build only**: the images pull from `apt`, `deb.nodesource.com` and
  `dl.google.com` (Chrome). Runtime needs no external network.
- The gateway needs the host Docker daemon (`docker.sock`); the user `dev` must be in the `docker`
  group (or have equivalent socket permissions).

## Deployment

```bash
# One-shot deploy: builds both images and starts the gateway
sudo ./deploy/deploy.sh
sudo ./deploy/deploy.sh --with-cleanup   # also install the hourly TTL cleanup timer
sudo ./deploy/deploy.sh --skip-build     # only (re)create the gateway container
```

<details>
<summary>Manual <code>docker run</code> equivalent</summary>

```bash
docker build --network host -t proving-pod:v1 userenv/
docker build --network host -t proving-gw:v1 gateway/
docker run -d --name provingpod-gateway --restart=unless-stopped -p 6901:22 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker \
  -v provingpod-data:/data \
  -e USER_IMAGE=proving-pod:v1 \
  -e MAX_USERS=8 \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE --cap-add SYS_CHROOT --cap-add SETUID \
  --cap-add SETGID --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add AUDIT_WRITE \
  --security-opt no-new-privileges:false \
  proving-gw:v1
```
</details>

Or, if the compose plugin is installed:

```bash
docker compose -f deploy/docker-compose.yml up -d
```

> ⚠️ **Two capabilities are required.** `AUDIT_WRITE` is needed for interactive `-t`/`-tt` logins
> (without it sshd kills the pty session right after auth with `Connection closed by remote host`),
> and `SYS_CHROOT` is needed for sshd privilege separation (otherwise logins fail outright).
> See [migration-notes.md](migration-notes.md) for the full debugging story.

## Configuration reference

Set these through the `deploy/deploy.sh` environment, `docker run -e`, or
`deploy/docker-compose.yml`.

| Variable | Default | Where | Purpose |
|---|---|---|---|
| `GATEWAY_PORT` | `6901` | deploy.sh | Host port mapped to the gateway's SSH (`:22`). |
| `GATEWAY_IMAGE` | `proving-gw:v1` | deploy.sh | Gateway image tag to build/run. |
| `USERENV_IMAGE` | `proving-pod:v1` | deploy.sh | Pod image tag to build. |
| `USER_IMAGE` | `proving-pod:v1` | gateway | Image the gateway uses when provisioning pods. |
| `MAX_USERS` | `8` | gateway | Max concurrent pods; further logins fail with `LIMIT_REACHED(8)`. |
| `TTL_DAYS` | `3` | cleanup timer | Idle-pod reclamation threshold. |
| `VNC_PASS` | `vncpass` | userenv | Desktop password (*shared across pods* — see SECURITY). |
| `VNC_GEOMETRY` | `1280x800` | userenv | Desktop resolution. |
| `RUN_USER` | `dev` | userenv | In-pod desktop user. |

The SSH **login password** is not an environment variable — edit `gateway/passwd.conf`
(`PASSWORD=...`) and rebuild the gateway image, or mount your own file over
`/opt/gateway/passwd.conf`.

## Ports

| Scope | Container port | Host port | Service |
|---|---|---|---|
| Gateway | 22 | `GATEWAY_PORT` (default `6901`) | SSH entrypoint |
| Pod | 5900 | random | TigerVNC |
| Pod | 6901 | random | noVNC web (`http://<host>:<port>/vnc.html`) |

Pod ports are assigned randomly by Docker and recorded on the gateway:

```bash
docker exec provingpod-gateway cat /data/ephemeral-users/<hex>.ports
# 5900/tcp =0.0.0.0:32768   <- VNC
# 6901/tcp =0.0.0.0:32769   <- noVNC web
```

## TTL cleanup

```bash
sudo cp deploy/docker-ephemeral-cleanup.sh /usr/local/sbin/
sudo cp deploy/docker-ephemeral-cleanup.service /etc/systemd/system/
sudo cp deploy/docker-ephemeral-cleanup.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-ephemeral-cleanup.timer
# idle pods older than TTL_DAYS (default 3) are reclaimed hourly; a new login re-provisions one
```

The cleanup script also removes orphaned `*.ports` / `*.lastseen` metadata for pods that no longer
exist. Installing the timer is optional but recommended — `deploy.sh --with-cleanup` does it in one
step.

## Teardown

```bash
# Stop and remove the gateway (pods are Docker containers on the same host)
docker rm -f provingpod-gateway

# Remove all leftover pods and the data volume
docker rm -f $(docker ps -aq --filter name=hex_)
docker volume rm provingpod-data

# Remove the TTL cleanup timer (if installed)
sudo systemctl disable --now docker-ephemeral-cleanup.timer
sudo rm -f /etc/systemd/system/docker-ephemeral-cleanup.{service,timer} /usr/local/sbin/docker-ephemeral-cleanup.sh
sudo systemctl daemon-reload

# Optionally remove the images
docker rmi proving-gw:v1 proving-pod:v1
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Connection closed by remote host` on `-tt` login | Gateway is missing `AUDIT_WRITE` in `cap_add`. |
| Logins fail outright | Missing `SYS_CHROOT` in `cap_add`. |
| `LIMIT_REACHED(8)` | All pods busy. Reuse an existing hex name, or wait for the TTL timer. |
| Login works but noVNC is blank | Check the pod's VNC is up: `docker logs hex_<user>`. |
| Pod never appears | Check the password in `gateway/passwd.conf` and `docker logs provingpod-gateway`. |

## Verification status

Tested **2026-08-09 on a ThinkPad T470s, Docker 29.1.3 / kernel 6.17**: end-to-end SSH 10/10,
`npm install` with native compilation (bcrypt), desktop + Chrome, noVNC HTTP 200 on all pods,
port isolation, multi-user concurrency (3+ pods), TTL cleanup, gateway restart persistence,
interactive `-tt` login, host-key persistence across gateway recreation, and incus-edition
coexistence without regression.
