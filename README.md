**English** | [中文](README.zh-CN.md)

# ProvingPod

**A disposable sandbox where AI agents prove code actually runs — with one command.**

```bash
ssh 3f2a9c@<your-server> -p 6901 'npm install && npm test'
```

That is the whole setup. The moment you connect, you have a fresh, isolated sandbox that is yours
alone:

| What you get | What it means |
|---|---|
| **A full toolchain** | Node 22, npm, git and build-essential — `npm install && npm test` just works |
| **A runtime verdict** | the remote command's exit status comes back to you: `0` means it ran |
| **Your own sandbox** | a separate container and network namespace, 2 GB / 2 CPU, ports that never clash |
| **A desktop in the browser** | XFCE + Chrome over noVNC, if you would rather click than type |
| **Nothing to clean up** | walk away and it recycles itself after 3 days |

No signup, no keys, no cloud account, no bill.

> Pick any 6-character hex username (like `3f2a9c`); reuse the same name to come back to the same
> machine. No server running yet? One command on an x86_64 Linux host sets one up — see
> [Run your own](#run-your-own).

[![build](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml/badge.svg)](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![status: experimental](https://img.shields.io/badge/status-experimental-orange.svg)](#project-status)

## Sandbox, agent, verdict

AI writes plenty of code that *looks* right. The only way to know whether it actually **runs** is to
put it on a clean machine and execute it — and the annoying part has always been finding that
machine and cleaning it up afterwards.

ProvingPod is that machine, as something your agent can drive with a single SSH call. It is a
**sandbox for verification**, not a development box: you do not maintain it, it holds no state you
care about, and it throws itself away when you are done.

| Project | In one line |
|---|---|
| DevPod | Put *my* dev environment into a container (persistent, mine) |
| RunPod | Rent GPUs on demand (paid cloud) |
| **ProvingPod** | Throw code in, prove it runs — disposable, isolated, free (self-hosted) |

## Built for the agent loop

- **One command, no provisioning.** No signup, no API key, no cloud account, no SDK. If your agent
  can run `ssh`, it can use this.
- **Non-interactive by default.** Pass a command and it executes — no TTY required, no prompt to
  answer.
- **The exit status is the verdict.** `ssh <hex>@<host> -p 6901 'npm test'` hands back the command's
  own exit code, so an agent can branch on it instead of scraping output.
- **A clean machine on demand.** A new hex name is a brand-new sandbox, which is what makes a
  verification run reproducible. The same name resumes the same machine until the TTL recycles it.
- **Throwaway.** Idle pods reclaim themselves after 3 days; nothing accumulates for an agent to
  track or tidy up.
- **Isolated from your machine.** Its own container, network namespace and port space, capped at
  2 GB / 2 CPU — a failed build never touches your laptop.
- **Self-hosted.** Generated code stays on your own infrastructure; nothing is handed to a
  third-party cloud.

```text
   agent writes code
          │
          ▼
   ssh <hex6>@<host> -p 6901 'npm install && npm test'
          │
          ├── exit 0  ──▶  verified: it runs
          └── exit ≠0 ──▶  the failure output comes back unchanged
          │
          ▼
   the pod recycles itself (TTL 3 days) — nothing to clean up
```

### Driving it from a script

```bash
POD=$(openssl rand -hex 3)                    # a fresh sandbox per run
TARGET="$POD@<your-server>"

# drop the working tree in and run the tests (sftp/scp are unavailable — pipe a tarball)
tar czf - . | sshpass -p 123456 ssh -o StrictHostKeyChecking=accept-new \
    "$TARGET" -p 6901 'mkdir -p ~/src && tar xzf - -C ~/src && cd ~/src && npm install && npm test'

echo "verdict: $?"                            # 0 = it ran
```

Public-key auth is **off** on the gateway (`PubkeyAuthentication no`), so unattended runs hand over
the default password — the `sshpass` above, or whatever mechanism your agent already uses.

## The checks that are hard to run anywhere else

Verification is rarely hard because of `npm test`. It is hard because of the checks that need a
*machine* rather than a script:

| The awkward check | Why it is awkward elsewhere | In a proving pod |
|---|---|---|
| **It has to be restarted** | a CI job is torn down when it ends, so there is no machine to come back to | the pod is long-lived: start, kill, restart — then log in again later and inspect what survived |
| **It has to be looked at** | headless runners have no display, and your own laptop is the machine you least want to pollute | a real X display (XFCE, 1280x800) that you watch and click from your browser over noVNC |
| **It has to be driven** | you cannot attach to a browser that is not running there | Chrome ships in the image — start it with the DevTools Protocol on and drive it with your own script |

### Restart and lifecycle

```bash
ssh 3f2a9c@<host> -p 6901 '
  cd ~/src && nohup node server.js > /tmp/app.log 2>&1 &   # start
  sleep 2 && curl -sf localhost:3000/health                # it answers
  pkill -f server.js && sleep 1                            # kill it
  nohup node server.js > /tmp/app.log 2>&1 &               # start it again
  sleep 2 && curl -sf localhost:3000/health                # did state survive?
'
```

The container's filesystem lives as long as the pod does, so what the app wrote to disk is still
there afterwards — which is exactly what a restart check needs. Note that the pod has **no init
system** (no `systemd`), so this is process-level restart testing; `systemctl` is not available.

### Looking at it (GUI)

Each pod publishes its desktop on random host ports; read them from the gateway:

```bash
docker exec provingpod-gateway cat /data/ephemeral-users/3f2a9c.ports
# 6901/tcp =0.0.0.0:32769    <- open http://<host>:32769/vnc.html
```

The desktop belongs to the `dev` user (your SSH shell is root), so launch the app there:

```bash
ssh 3f2a9c@<host> -p 6901 'nohup su - dev -c "DISPLAY=:0 google-chrome http://localhost:3000" &'
```

Now you can watch the window render, click through it and see the thing with your own eyes — the
verdict a text log cannot give you. The desktop password defaults to `vncpass`.

### Driving it (CDP)

Chrome is already installed, so a pod doubles as a browser-verification runtime:

```bash
ssh 3f2a9c@<host> -p 6901 '
  nohup google-chrome --headless=new --no-sandbox --remote-debugging-port=9222 \
    --user-data-dir=/tmp/cdp about:blank > /tmp/chrome.log 2>&1 &
  sleep 3
  curl -s localhost:9222/json/version          # the DevTools endpoint is up
'
```

The endpoint listens **inside** the pod, so run the driver there too — puppeteer/playwright
installed in the pod, or a plain WebSocket `Runtime.evaluate`. Then assert on console errors, failed
requests or a final screenshot, and hand back a verdict instead of a wall of log lines.

## What "sandbox" does and does not mean

**What it means.** A proving pod is its own container with its own filesystem, network namespace,
port space and 2 GB / 2 CPU caps. It is isolated from *your* machine and from other pods' accidental
interference, and it disappears on its own.

**What it does not mean.** It is not a hardened boundary against hostile code. The gateway mounts the
host Docker socket (≈ host root) and ships a fixed public default password. Use ProvingPod to verify
code you broadly trust — not to jail an adversary. Read **[SECURITY.md](SECURITY.md)** before
pointing anything untrusted at it.

## Run your own

ProvingPod is self-hosted, and one constraint decides where it can run: the pod image is
**`linux/amd64` only**, because Chrome ships no arm64 `.deb`. Everything else follows from that.

| Host | Works? | How |
|---|---|---|
| Linux x86_64 | ✅ | builds both images locally — the path this project is tested on |
| Linux arm64 (Graviton, Raspberry Pi, …) | ✅ | pulls the prebuilt amd64 images; nothing is built, so nothing is emulated while building |
| macOS, Apple Silicon | ⚠️ | prebuilt images remove the build, but the gateway also needs a Linux daemon socket — see below |
| Windows | ⚠️ | untested |

```bash
sudo ./deploy/deploy.sh
```

On x86_64 that builds both images. On any other architecture the same command pulls images this
project publishes from an x86_64 runner instead:

```bash
sudo ./deploy/deploy.sh --from-registry                            # force the prebuilt images
PROVINGPOD_VERSION=v0.2.0 sudo ./deploy/deploy.sh --from-registry  # pin a release
```

That route exists because building the amd64 image on an arm64 host means emulating x86_64, and QEMU
does that unreliably — failing ten minutes into a build rather than immediately. Full deployment,
configuration and teardown details live in **[docs/operations.md](docs/operations.md)**.

### If you are on Apple Silicon

Pulling instead of building removes the QEMU problem, but there is a second requirement: the gateway
creates pod containers as siblings of itself, so it needs the host Docker daemon at
`/var/run/docker.sock`. Whether that path resolves depends on your Docker VM:

| | `/var/run/docker.sock` inside the VM | Mounting it |
|---|---|---|
| colima | the VM's own daemon socket | ✅ verified — a container reached the daemon through it |
| Docker Desktop | a directory; the host path is not in the VM's namespace | ❌ |

So with colima, `deploy.sh --from-registry` is expected to work on macOS — the socket resolves and
drives the daemon. The bundled `demo.sh` still refuses non-Linux hosts, which is stricter than
colima needs. That last mile has not been tested end to end.

If you would rather build here than pull, use Rosetta — in the real pod build the QEMU path died and
the Rosetta path completed (3m58s, 589 MB):

```bash
# colima
colima start --arch aarch64 --vm-type=vz --vz-rosetta

# Docker Desktop: Settings -> General -> Apple Virtualization,
# then enable "Use Rosetta for x86_64/amd64 emulation on Apple Silicon"
```

`--arch` must stay `aarch64`. With `--arch x86_64`, colima silently ignores `--vz-rosetta` and
falls back to full QEMU emulation — which is the failure mode you are trying to avoid.

## Troubleshooting (known issues)

**`Exception: ('python3.12', '-c', 'import importlib.util; print(importlib.util.MAGIC_NUMBER)') failed
with status code -11`** — often surfacing a few lines later as
`dpkg: error processing package python3-oslo.serialization`, and then as `novnc` /
`python3-novnc` errors. You are building the amd64 pod image under QEMU user-mode emulation and QEMU
segfaulted inside the emulated process. It is intermittent: it appears minutes into a heavy `apt`
run, so a short reproduction loop will not necessarily see it. This is an upstream QEMU bug, not a
ProvingPod bug — the same signature is reported against `uv`, `rustc`, `.NET` and ordinary `apt`
builds. Stop emulating:

```bash
sudo ./deploy/deploy.sh --from-registry   # images built on an x86_64 runner, nothing emulated
```

or enable Rosetta ([above](#if-you-are-on-apple-silicon)), or build on x86_64 and reuse those images
with `--skip-build`. Background:
[docker/setup-qemu-action#188](https://github.com/docker/setup-qemu-action/issues/188),
[docker/desktop-feedback#382](https://github.com/docker/desktop-feedback/issues/382),
[qemu-project/qemu#3130](https://gitlab.com/qemu-project/qemu/-/work_items/3130).

**`no matching manifest for linux/arm64/v8 in the manifest list entries`** — an arm64 host was asked
to pull a **manifest list** (image index) that only offers amd64. Docker matches manifests against the
host platform and, for a list, does not fall back to the one platform on offer, so it errors instead
of pulling. ProvingPod's own tags are not manifest lists: `publish.yml` sets `provenance: false`, so
each tag is a plain single-platform manifest, which pulls on any architecture — the mismatch only
surfaces as a warning when you *run* it. This error does show up with third-party multi-arch images.
`deploy.sh` passes `--platform linux/amd64` regardless, both to keep the run-time logs clean and to
stay correct if a release is ever published as an index; if you pull by hand, do the same. Under
compose, set `DOCKER_DEFAULT_PLATFORM=linux/amd64` (as `demo.sh` does).

**`/opt/gateway/provision.sh: /usr/bin/docker: cannot execute: required file not found`** — the
gateway used to bind-mount the host's Docker CLI, which only works while host and image share an
architecture. The CLI now ships inside the gateway image; if you are carrying a volume or compose
file over from an older deployment, drop the `/usr/bin/docker` bind mount.

**`Connection closed by remote host` immediately after a correct password** — authentication
succeeded but the PAM *account* hook failed, so the login was rejected. Provisioning runs there, so
a failing `sudo -n docker`, a missing pod image, or a `LIMIT_REACHED` quota all look like this.
Check `docker logs provingpod-gateway`.

## Project status

**Experimental / early.** A working, single-maintainer prototype. Its job is to *prove code runs*,
not to run production workloads, and interfaces may change without notice.

> ⚠️ **Not hardened for the public internet.** The gateway mounts the host Docker socket
> (≈ host root) and ships with a fixed default password. Keep it on a private LAN, or read the
> hardening checklist first — see **[SECURITY.md](SECURITY.md)**.

## FAQ

- **`sftp` / `scp` do not work** — by design; every login jumps straight into the pod. Move files
  with git, or pipe a tarball through SSH.
- **Interactive login needs `-tt`** — use `ssh -tt <hex>@<host> -p 6901`. One-off commands do not
  need it, which is what makes the sandbox scriptable.
- **Where is my desktop?** Each pod gets random ports; the gateway records them. See
  [docs/operations.md](docs/operations.md#ports).
- **Hitting a limit?** The default cap is 8 concurrent pods, and idle ones are recycled for you.
- **Is my run reproducible?** Yes, if you want it to be: take a fresh hex name every time and you get
  a machine that has never run anything before.

## Learn more

- **How it works under the hood** — [docs/architecture.md](docs/architecture.md)
- **Deploy, configure, tear down** — [docs/operations.md](docs/operations.md)
- **Day-to-day usage** — [docs/service-usage.md](docs/service-usage.md)
- **Security model & hardening** — [SECURITY.md](SECURITY.md)
- **Migration & design history** — [docs/migration-notes.md](docs/migration-notes.md)
- **Contributing** — [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE).
