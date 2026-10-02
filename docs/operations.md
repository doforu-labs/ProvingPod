# Operations

Everything you need to deploy, configure, tune and tear down a ProvingPod host.
For the internals, see [architecture.md](architecture.md).

## Requirements

- Docker Engine **20.10+** (tested on 29.x). The `docker compose` plugin is **optional** —
  `deploy/deploy.sh` uses plain `docker run` so it works everywhere.
- An **x86_64** host to build on. Every other architecture pulls the prebuilt images instead —
  see "Where the images come from" below.
- Internet access during **build only**: the images pull from `apt`, `deb.nodesource.com` and
  `dl.google.com` (Chrome). Runtime needs no external network. Deploying from the prebuilt images
  needs to reach `ghcr.io`, and nothing else.
- The gateway needs the host Docker daemon (`docker.sock`); the user `dev` must be in the `docker`
  group (or have equivalent socket permissions).

## Deployment

```bash
# One-shot deploy. On x86_64 it builds both images; anywhere else it pulls the prebuilt ones.
sudo ./deploy/deploy.sh
sudo ./deploy/deploy.sh --from-registry  # always use the prebuilt images
sudo ./deploy/deploy.sh --build          # always build here
sudo ./deploy/deploy.sh --skip-build     # only (re)create the gateway container
sudo ./deploy/deploy.sh --with-cleanup   # also install the hourly TTL cleanup timer
```

### Where the images come from

Both images are amd64-only, so building them on an arm64 host means emulating x86_64 — and QEMU
segfaults intermittently inside emulated `apt` processes, minutes into the build.
[`publish.yml`](../.github/workflows/publish.yml) therefore builds them on an x86_64 runner and
pushes them to GHCR, and `deploy.sh` pulls from there whenever the host is not x86_64.

| `IMAGE_SOURCE` | Behaviour |
|---|---|
| `auto` *(default)* | build on x86_64, pull from GHCR otherwise |
| `build` | always build locally — refused on non-x86_64 unless `FORCE_BUILD=1` |
| `registry` | always pull `${REGISTRY}/provingpod-{gateway,pod}:${VERSION}` |
| `skip` | use whatever images are already present |

`REGISTRY` and `VERSION` come from [`deploy/images.env`](../deploy/images.env). Override the release
without editing it:

```bash
PROVINGPOD_VERSION=v0.2.0 sudo ./deploy/deploy.sh --from-registry
GATEWAY_IMAGE=registry.example/provingpod-gateway:v1 \
USERENV_IMAGE=registry.example/provingpod-pod:v1 \
  sudo ./deploy/deploy.sh --skip-build
```

> Why `--platform linux/amd64` is spelled out: the published tags are single-platform amd64
> manifests (`provenance: false`), so on an arm64 host a plain `docker pull` actually succeeds —
> Docker has no platform list to match against, and the mismatch only surfaces as a `docker run`
> warning. Naming the platform keeps those logs clean, and keeps the command correct if a release
> is ever published as a manifest index, where a plain pull on arm64 fails with
> `no matching manifest for linux/arm64/v8 in the manifest list entries` instead of falling back to
> the one platform on offer. Under compose, set `DOCKER_DEFAULT_PLATFORM=linux/amd64`.

### Publishing a release

```bash
git tag v0.2.0 && git push origin v0.2.0   # publish.yml builds on x86_64 and pushes to GHCR
```

Then bump `VERSION` in `deploy/images.env` in the same commit, so `--from-registry` hands out the new
release by default. `publish.yml` warns when the tag and that file disagree.

<details>
<summary>Manual <code>docker run</code> equivalent</summary>

```bash
docker build --network host -t proving-pod:v1 userenv/
docker build --network host -t proving-gw:v1 gateway/
docker run -d --name provingpod-gateway --restart=unless-stopped -p 6901:22 \
  -v /var/run/docker.sock:/var/run/docker.sock \
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
