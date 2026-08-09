# ProvingPod — Usage Guide (Docker edition)

> ProvingPod 的临时访问账号体系：随机 6 位小写 hex 用户名（如 `3f2a9c`）+ 固定默认密码 `123456`。
> SSH 首次连接自动创建隔离的 Docker 容器（proving pod）并直接进入。**交互式会话用 `-tt`，批量执行用命令透传**（`ssh <hex>@host 'cmd'`，Docker 版已支持）；sftp / scp 不可用（ForceCommand 会污染协议流）。

## Overview

The service provides zero-friction, disposable proving environments over SSH:

- Any **6-character lowercase hex** username (`[0-9a-f]{6}`, e.g. `3f2a9c`, `b00c1e`) plus the
  default password `123456` is a valid login.
- The first SSH connection **auto-provisions** a private, isolated Docker container (`hex_<user>`,
  image `proving-pod:v1`) and drops you straight into it (first-time provisioning ~1s).
- Mechanism: **NSS virtual users** (libnss_hex6) make every hex6 name a valid account → PAM
  (`auth sufficient pam_exec` with `expose_authtok`) verifies the password → the account/pam hook
  runs `provision.sh` (docker run) on first login → **sshd ForceCommand** runs `enter.sh`, which
  jumps into the container via `sudo docker exec`.
- No signup, no key setup: `ssh <hex>@<host> -p 6901` (password `123456`) is all you need.

Concrete deployment used for testing: `192.168.31.82` port `6901` (replace `<host>` with yours).

## How to connect

```bash
ssh <random-6-hex>@<host> -p 6901        # password: 123456
```

You can pick any 6-char lowercase hex name; a fresh name gets a fresh container, reusing the same
name resumes your existing container (if still within TTL).

## Session modes

### Recommended

| Purpose | Command | Notes |
|---|---|---|
| Interactive shell | `ssh -tt <hex>@<host> -p 6901` | `-tt` gives you a clean interactive bash in the pod |
| One-off command | `ssh <hex>@<host> -p 6901 'npm install && npm test'` | Command pass-through (Docker edition; works without `-tt`) |
| Scripted session | `printf 'cmd && exit\n' \| ssh -tt <hex>@<host> -p 6901` | Robust against the jump banner |

Example (run `npm install && npm test`, then leave):

```bash
ssh 3f2a9c@<host> -p 6901 'npm install && npm test'
```

## Pod contents

- node 22 LTS + npm + git + build-essential (native npm modules compile fine)
- XFCE desktop + TigerVNC(5900) + noVNC(6901) + Google Chrome
- 2 GB RAM / 2 CPU quota, isolated network namespace, random public ports (never conflict)

## Desktop (VNC / noVNC)

Each pod publishes random host ports for VNC (5900) and noVNC (6901). Find them on the gateway:

```bash
docker exec provingpod-gateway cat /data/ephemeral-users/<hex>.ports
# 5900/tcp =0.0.0.0:32768   <- VNC
# 6901/tcp =0.0.0.0:32769   <- noVNC web (open http://<host>:32769/ in a browser)
```

VNC password: `vncpass` by default (shared across pods; per-user via `VNC_PASS` env on userenv).

## sftp / scp limitation — and why

**sftp and scp are NOT available.** The sshd `ForceCommand` always runs the jump script; sftp/scp
are SSH subsystems that expect a clean protocol stream, but the jump emits the container banner /
provisioning output on the same channel before the protocol handshake completes, corrupting the
framing → `Connection closed` / `Received message too long` / hang.

Workarounds: transfer files **inside** the pod (pipe base64/tar over the SSH channel), or stage
files via git.

## Operations notes

| Item | Value / Rule |
|---|---|
| Container quota | `MAX_USERS=8` (env on the gateway) — provisioning fails with `LIMIT_REACHED(8)` once 8 pods exist; existing pods are reused |
| Cleanup (TTL) | **3 days** — idle pods past TTL are auto-reclaimed by the host systemd timer; a new login re-provisions a fresh one |
| Per-pod resources | 2 CPU / 2 GiB RAM (set by `provision.sh`) |
| Network isolation | Each pod gets its own network namespace with random port mappings (ports never conflict) |
| Credentials | Username: any `[0-9a-f]{6}`; password: `123456` by default (public — treat pods as ephemeral; change `gateway/passwd.conf` before public exposure) |
| Nature | Temporary proving pods only — never store data you cannot afford to lose |

## Troubleshooting

- **`Connection closed by remote host` on interactive (`-tt`) login** → the gateway container is
  missing the `AUDIT_WRITE` capability. Recreate it with `--cap-add AUDIT_WRITE`
  (see `README.md` → Deployment; fixed in `deploy/docker-compose.yml`).
- **`LIMIT_REACHED(8)`** → all pods are busy; reuse an existing hex name or wait for TTL cleanup.
- **Login works but noVNC is blank** → check the pod's VNC is up: `docker logs hex_<user>` should
  show `VNC listening on 5900` / `noVNC listening on 6901`.

## Legacy: incus edition (1st generation, reference only)

The first generation ran incus system containers on host port 22 (`ssh <hex>@host`). It is kept in
`incus/` for reference; the Docker edition (this guide) replaces it. Differences: entry port 22 →
6901, incus exec → docker exec, command pass-through not supported → supported.
