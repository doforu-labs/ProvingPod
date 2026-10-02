# Architecture

How ProvingPod turns "any 6-character hex username" into a working, isolated environment.

## The two images

| Image | Contents |
|---|---|
| `proving-gw:v1` | Gateway: sshd + PAM + NSS virtual users. Creates pods on demand and jumps you into them. |
| `proving-pod:v1` | Proving pod: Node 22 + XFCE desktop + TigerVNC + noVNC + Chrome. This is what you actually use. |

The gateway is a long-running container. Pods are ordinary Docker containers created on the fly,
one per user, on the same host.

## How a login flows

```text
    ssh 3f2a9c@<host> -p 6901              (password: 123456)
         │
         │  login
         ▼
┌─ gateway: provingpod-gateway   (image: proving-gw:v1) ────────┐
│                                                               │
│  sshd + libnss_hex6.so   →   accept ANY [0-9a-f]{6} username  │
│                                                               │
│  PAM auth.sh             →   verify password (passwd.conf)    │
│      └─ account.sh       →   provision.sh → docker run        │
│                                                               │
│  ForceCommand enter.sh   →   sudo docker exec                 │
│                                                               │
└───────────────────────────────────────────────────────────────┘
         │
         │  docker exec
         ▼
┌─ pod: proving-<user>   (image: proving-pod:v1) ───────────────┐
│                                                               │
│  node 22 + npm + git + build-essential                        │
│  XFCE desktop + TigerVNC (:5900) + noVNC (:6901) + Chrome     │
│  2 GB / 2 CPU  ·  isolated network  ·  random host ports      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

Three pieces are glued together with SSH's own plumbing:

1. **NSS virtual users (`gateway/nss_hex6.c`).** OpenSSH rejects a login when `getpwnam()` cannot
   find the user. This small NSS module answers for *every* 6-character lowercase-hex name, mapping
   it to a synthetic uid (`0x40000000 + hex value`) so sshd lets the connection through to PAM.
2. **PAM authentication (`gateway/auth.sh`).** `auth sufficient pam_exec.so quiet expose_authtok`
   hands the typed password to a script, which SHA-256-compares it against `gateway/passwd.conf`
   (default `123456`). The PAM *account* hook (`account.sh`) then calls `provision.sh`, which
   `docker run`s the pod on first login and refreshes its `lastseen` timestamp.
3. **The jump (`gateway/enter.sh`).** `sshd ForceCommand` always runs this script, which
   `sudo docker exec`s you into your pod. In command mode it forwards `SSH_ORIGINAL_COMMAND`, which
   is what makes `ssh <hex>@<host> 'npm install && npm test'` transparent.

## Why it is built this way

The hard part is the very first connection. A dynamically created user does not exist yet, so
OpenSSH cannot look it up — and it substitutes a fake password with `valid=0`, forcing a rejection.
The NSS module makes the name *look* real so sshd proceeds, and PAM is then free to verify the
real password and provision the container. The container creation happens in the PAM **account**
stage, before the shell is ever reached.

A fresh name always yields a fresh pod; reusing a name resumes the existing one (within TTL). Pods
are plain Docker containers on the gateway host, which keeps operations simple.

## Generations

- **1st generation:** incus system-container edition (host port 22, `incus/` directory).
- **2nd generation:** Docker edition (this repository; gateway on 6901 + dynamic pods).

The migration drivers and a full comparison are in
[migration-notes.md](migration-notes.md).
