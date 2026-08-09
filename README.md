# ProvingPod

> **Zero-cost proving pods for AI-generated code.**
> One SSH command gets you a free, isolated, recyclable code-verification environment in seconds.

## Quick start

```bash
# Login (auto-creates a proving pod, ~1s, password 123456)
ssh <random 6-char hex>@<host> -p 6901
# Command mode (pass-through execution)
ssh <hex>@<host> -p 6901 'npm install && npm test'
```

`<host>` = the IP/DNS of the machine running the gateway (e.g. `192.168.31.82`). Any
6-character lowercase-hex username (`[0-9a-f]{6}`, e.g. `3f2a9c`, `b00c1e`) is valid;
a fresh name gets a fresh isolated pod, reusing a name resumes your existing pod (within TTL).

## Capabilities

- node 22 + npm + git + build-essential (npm install with native compilation OK)
- XFCE desktop + TigerVNC(5900) + noVNC(6901) + Google Chrome (view the desktop directly in a browser)
- Per-user isolated container + random port mapping (same ports never conflict) + 2GB/2CPU quota
- TTL 3-day auto-reclamation (systemd timer, hourly)

## Directory structure

```text
ProvingPod/
├── README.md           This file
├── PROVINGPOD.md       Brand document (naming / slogan / positioning guardrails)
├── LICENSE             MIT license
├── SECURITY.md         Security model + hardening guide
├── gateway/            SSH gateway image source (sshd + PAM + libnss_hex6 + provision + jump)
├── userenv/            User environment image source (node + desktop + Chrome + noVNC)
├── deploy/             Deployment files (deploy.sh / compose / cleanup scripts / systemd units)
├── incus/              Legacy incus edition source (old 22-port system, reference only)
└── docs/               Usage guide + migration notes
```

## Images

| Image | Contents |
|---|---|
| `proving-gw:v1` | Gateway: sshd + PAM + NSS virtual users + dynamically creates proving pods |
| `proving-pod:v1` | Proving pod: node22 + XFCE + TigerVNC + noVNC + Chrome |

## Requirements (host)

- Docker Engine **20.10+** (tested on 29.x). `docker compose` plugin is **optional** — `deploy/deploy.sh`
  uses plain `docker run` so it works everywhere.
- Internet access during **build only**: the images pull from `apt`, `deb.nodesource.com` and
  `dl.google.com` (Chrome). Runtime needs no external network.
- The gateway needs the host docker daemon (`docker.sock`); the user `dev` must be in the `docker`
  group (or equivalent socket permissions).

## Deployment

```bash
# One-shot deploy: builds both images, starts the gateway, optionally installs the TTL cleanup timer
sudo ./deploy/deploy.sh            # run as root (or a user in the docker group)

# --- or manually ---
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
# or docker compose -f deploy/docker-compose.yml up -d (if the compose plugin is installed)
```

> ⚠️ **AUDIT_WRITE is required**: sshd writes a Linux audit record after authentication; without
> this capability interactive logins (`ssh -t/-tt`) are killed with `Connection closed by remote host`
> right after auth. See `docs/migration-notes.md`.

## TTL cleanup (optional but recommended)

```bash
sudo cp deploy/docker-ephemeral-cleanup.sh /usr/local/sbin/
sudo cp deploy/docker-ephemeral-cleanup.service /etc/systemd/system/
sudo cp deploy/docker-ephemeral-cleanup.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-ephemeral-cleanup.timer
# idle pods older than 3 days (TTL_DAYS env) are reclaimed hourly
```

## Verification status (tested 2026-08-09 on T470s, Docker 29.1.3 / kernel 6.17)

End-to-end SSH 10/10 · npm install (with native compilation, bcrypt) · desktop + Chrome · noVNC
(HTTP 200 on all pods) · port isolation (concurrent pods, random ports never clash) · multi-user
concurrency (3+ pods) · TTL cleanup · gateway restart persistence · **interactive `-tt` login**
(after the `AUDIT_WRITE` cap fix) · **host-key persistence across gateway recreation** ·
incus edition coexistence without regression.

Known-good deploy paths: `sudo ./deploy/deploy.sh` (docker run, no compose plugin needed) and
`docker compose -f deploy/docker-compose.yml up -d`.

## Changelog

- 2026-08-09 · `AUDIT_WRITE` cap fix (interactive `-tt` login was killed after auth without it);
  host keys persisted under the data volume; one-shot `deploy/deploy.sh`; repo prepared for
  public open-sourcing (LICENSE, SECURITY.md, usage guide rewrite).

## Security notes (read before public deployment)

- **Gateway mounts docker.sock ≈ host root.** Anyone who gets a shell inside the gateway (or an
  interactive pod) can escape to the host via docker. This is an inherent trade-off of the design;
  for anything beyond a private LAN demo, replace the socket mount with a restricted RPC.
- **Password `123456` is public and fixed by default.** Change it before exposing the service:
  edit `gateway/passwd.conf` (or mount your own over `/opt/gateway/passwd.conf`) and rebuild the
  image — then redeploy. Add `fail2ban` + a firewall allowlist on port 6901.
- **VNC password is shared** (`vncpass` by default) across pods — make it per-user via the
  `VNC_PASS` env on the userenv image if you need isolation.
- **Pods are ephemeral and throwaway.** Never store data you cannot afford to lose; everything
  is reclaimed by the TTL cleanup.

See `SECURITY.md` for the full threat model and hardening checklist.

## FAQ

- **sftp / scp does not work** — by design. sshd ForceCommand always jumps into the pod, which
  corrupts the sftp/scp protocol stream. Transfer files inside the pod (pipe base64/tar over the
  SSH channel) or stage them via git.
- **Interactive login needs `-tt`** (`ssh -tt <hex>@<host> -p 6901`), or pipe commands in:
  `printf 'npm test && exit\n' | ssh -tt <hex>@<host> -p 6901`.
- **Where is my desktop?** The gateway records the pod's random public ports in
  `/data/ephemeral-users/<hex>.ports` (VNC and noVNC web). Open the noVNC URL in a browser.
- **Too many pods / limit reached?** `MAX_USERS=8` by default; idle pods are reaped by the TTL
  timer, and reusing the same hex name reuses an existing pod.
- **Interactive login fails with `Connection closed by remote host`?** You are missing
  `AUDIT_WRITE` in `cap_add` (see Deployment).

## History

- 1st generation: incus system-container edition (host port 22, `incus/` directory, PAM+NSS dynamic creation, `ssh <hex>@host` worked on the first try)
- 2nd generation: Docker edition (this directory, gateway 6901 + dynamic proving pods), migration reasons: distribution / operations / ecosystem (see `docs/`)
