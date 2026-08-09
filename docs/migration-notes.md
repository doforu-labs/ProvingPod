# Migration notes (ProvingPod)

## Timeline

### 2026-08-09 · 1st generation (incus edition) done
- Problem: the first SSH connection of a dynamically created user always failed (OpenSSH substitutes a fake password for users whose getpwnam fails, with valid=0 forcing rejection)
- Solution B: a custom NSS module `libnss_hex6` (virtual users uid=0x40000000+hex) + PAM `auth sufficient pam_exec.so expose_authtok` to verify the password itself
- Implementation: host port 22, a PAM hook dynamically creates incus containers (`c-<hex>` + isolated subnet + in-container user), ForceCommand jump
- Result: a brand-new user's first connection succeeds on the first try (container creation ~7s); 3-day TTL cleanup; iptables network isolation
- Source: `incus/` directory

### 2026-08-09 · 2nd generation (Docker edition) done
- Motivation: distribution / operations / ecosystem (Docker images, registry, multi-node); user-environment needs (npm install + desktop + Chrome + port isolation)
- Architecture: gateway container (sshd+PAM+NSS+provision, port 6901) + dynamically created per-user Docker containers (node+desktop+Chrome+noVNC)
- Key fixes:
  1. docker0 egress failures → root cause: `gw_monitor.sh` route failover flapping (the "72 all-DROP rules" were an iptables -L display artifact); self-healed
  2. Gateway docker.sock permissions → passwordless sudoers docker + enter.sh uses sudo
  3. `ssh host 'cmd'` pass-through → SSH_ORIGINAL_COMMAND branch (better than the incus edition)
  4. Desktop silently failing → userenv added tigervnc-tools + start.sh set -e
  5. TTL timer silently idling → service User=dev changed to root
  6. compose missing SYS_CHROOT cap → fixed
- Verification: end-to-end 10/10, npm install (with bcrypt native compilation), desktop + Chrome, noVNC, port isolation, multi-user concurrency, TTL cleanup, incus coexistence without regression

### 2026-08-09 · Docker edition hotfix: missing AUDIT_WRITE cap breaks interactive (-t/-tt) login
- Symptom: `ssh -tt <hex>@host -p 6901` fails with `Connection closed by remote host` immediately after auth; plain command mode (`ssh host 'cmd'`) works fine. Even the system user `dev` was affected (i.e. not a hex6/ForceCommand issue)
- Root cause: gateway container runs with `cap_drop ALL`; after authentication sshd writes an audit record (`linux_audit_write_entry`) which requires **CAP_AUDIT_WRITE**. Without it the pty session setup is aborted and the connection is dropped
- Evidence: debug container without caps worked; with identical cap list reproduced the failure; sshd -E log showed `linux_audit_write_entry failed: Operation not permitted`
- Fix: add `AUDIT_WRITE` to `cap_add` (compose + docker run). Verified: interactive login works, 10/10 regression passed
- Note: existing running gateway containers need a rebuild with the new cap

### Naming
- ProvingPod (debate verdict: Proving vs Testing → Proving won, with positioning guardrails attached)
- Images: proving-gw:v1 / proving-pod:v1 (the former internal-codename images gateway:v4 / userenv:v2 have been re-tagged and retired)

## Architecture comparison

| | incus edition (1st gen) | Docker edition (2nd gen) |
|---|---|---|
| Entrypoint | host 22 | gateway container 6901 |
| Environment | incus system container (c-<hex>) | Docker container (hex_<hex>) |
| Creation | PAM account stage | same (provision docker run) |
| Jump | ForceCommand → incus exec | ForceCommand → sudo docker exec (command pass-through supported) |
| Desktop | must install yourself | node+desktop+Chrome image, works out of the box |
| Distribution | host-level config (PAM/NSS/iptables) | fully containerized, docker run is the service |
