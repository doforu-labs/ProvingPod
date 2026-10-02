# ProvingPod

**Get a clean machine to run your code — with one command.**

```bash
ssh 3f2a9c@<your-server> -p 6901      # password: 123456
```

That is the whole setup. The moment you connect, you have a fresh, isolated environment that is
yours alone:

| What you get | What it means |
|---|---|
| **A full toolchain** | Node 22, npm, git and build-essential — `npm install && npm test` just works |
| **A desktop in the browser** | XFCE + Chrome over noVNC, if you would rather click than type |
| **Your own sandbox** | a separate container and network, 2 GB / 2 CPU, ports that never clash |
| **Nothing to clean up** | walk away and it recycles itself after 3 days |

No signup, no keys, no cloud account, no bill.

> Pick any 6-character hex username (like `3f2a9c`); reuse the same name to come back to the same
> machine. No server running yet? One command on any Docker host sets one up — see
> [Run your own](#run-your-own).

[![build](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml/badge.svg)](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![status: experimental](https://img.shields.io/badge/status-experimental-orange.svg)](#project-status)

## Why you would want this

AI writes plenty of code that *looks* right. The quickest way to find out whether it actually
**runs** is to drop it on a clean machine and try — the annoying part is setting that machine up
and cleaning it afterwards. ProvingPod turns the whole loop into one command.

| Project | In one line |
|---|---|
| DevPod | Put *my* dev environment into a container (persistent, mine) |
| RunPod | Rent GPUs on demand (paid cloud) |
| **ProvingPod** | Throw code in, prove it runs — disposable, isolated, free (self-hosted) |

## Run your own

ProvingPod is self-hosted. On any machine with Docker:

```bash
sudo ./deploy/deploy.sh
```

That builds both images and starts the gateway. Full deployment, configuration and teardown
details live in **[docs/operations.md](docs/operations.md)**.

## Project status

**Experimental / early.** A working, single-maintainer prototype. Its job is to *prove code runs*,
not to run production workloads, and interfaces may change without notice.

> ⚠️ **Not hardened for the public internet.** The gateway mounts the host Docker socket
> (≈ host root) and ships with a fixed default password. Keep it on a private LAN, or read the
> hardening checklist first — see **[SECURITY.md](SECURITY.md)**.

## FAQ

- **`sftp` / `scp` do not work** — by design; every login jumps straight into the pod. Move files
  with git, or pipe a tarball through SSH.
- **Interactive login needs `-tt`** — use `ssh -tt <hex>@<host> -p 6901`.
- **Where is my desktop?** Each pod gets random ports; the gateway records them. See
  [docs/operations.md](docs/operations.md#ports).
- **Hitting a limit?** The default cap is 8 concurrent pods, and idle ones are recycled for you.

## Learn more

- **How it works under the hood** — [docs/architecture.md](docs/architecture.md)
- **Deploy, configure, tear down** — [docs/operations.md](docs/operations.md)
- **Day-to-day usage** — [docs/service-usage.md](docs/service-usage.md)
- **Security model & hardening** — [SECURITY.md](SECURITY.md)
- **Migration & design history** — [docs/migration-notes.md](docs/migration-notes.md)
- **Contributing** — [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE).
