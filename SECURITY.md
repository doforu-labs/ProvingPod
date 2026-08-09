# Security

ProvingPod is a **private-LAN demo / internal tool** design. It is not hardened for direct
exposure to the public internet without the mitigations below.

## Threat model

| Asset | Attack surface | Risk |
|---|---|---|
| Host docker daemon | Gateway mounts `/var/run/docker.sock` | **Host root escape** (docker ≈ root) — highest risk |
| Pods (`hex_<user>`) | Interactive SSH into a pod | Host escape via docker.sock → root |
| Gateway sshd (6901) | Password auth, arbitrary hex usernames | Brute force, resource exhaustion |
| VNC/noVNC on pods | Shared password `vncpass` | Cross-pod desktop access |

## Inherent by design

- `docker.sock` inside the gateway: anyone who reaches the gateway (or a pod, since pods are
  created through it) can drive the host docker daemon. **The pods are NOT a security boundary.**
- Fixed public password `123456` (hex6 users) — convenient for throwaway proving pods, dangerous
  for anything persistent. Pods are ephemeral and auto-reclaimed after 3 days TTL.

## Hardening checklist (before any public exposure)

1. **Replace the docker.sock mount** with a restricted RPC/agent (least privilege, per-user
   containers only) — or keep the service on an isolated host / VM.
2. **Change the password**: edit `gateway/passwd.conf` (e.g. `PASSWORD=<long-random>`), rebuild
   the gateway image, redeploy. Consider mounting a secret-managed conf at
   `/opt/gateway/passwd.conf` instead of baking it into the image.
3. **Change the `dev` admin user's password** inside the gateway image (`userenv`/`gateway`
   Dockerfiles use `123456` for `dev` too).
4. **Fail2ban** on the SSH port (6901) + **ufw/firewalld allowlist** of client IPs.
5. **Per-user VNC passwords**: pass `VNC_PASS=<random>` per pod (currently shared `vncpass`).
6. Keep `--cap-drop ALL` and the minimal `cap_add` set; `AUDIT_WRITE` is required for `-tt` login
   (see `docs/migration-notes.md`).
7. Run the gateway with a **dedicated non-root session user** and passwordless sudo only for
   `/usr/bin/docker` (already the layout; don't widen the sudoers rule).

## Reporting

This is an open-source tool; report issues via the project's issue tracker. Do not include
deployment credentials or live host addresses in reports.
