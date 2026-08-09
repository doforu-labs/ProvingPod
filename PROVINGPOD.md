# ProvingPod

> **Zero-cost proving pods for AI-generated code.**
> (AI-generated code, verified at zero cost.)

One SSH command gets you a free, isolated, recyclable code-verification environment in seconds.

## Name

```text
Proving  ×  Pod
 │          │
 │          └─ pod/capsule + cloud-native semantics (K8s/Podman's minimal deployment unit)
 │             instantly understood by developers: "a containerized run unit"
 └─ proving ground (compressed)
      points straight at the product essence: "prove this code runs"
```

- **ProvingPod** = a "verification pod": a standalone container unit dedicated to proving code can run
- Positioning vs. DevPod (dev-environment container) / RunPod (GPU cloud):
  - DevPod = put my dev environment into a container
  - RunPod = rent GPUs on demand
  - **ProvingPod = throw AI-written code in and prove it runs, at 0 cost**

## Naming conventions (component mapping)

| Layer | Former internal codename (deprecated) | ProvingPod name | Status |
|---|---|---|---|
| Brand/product | (none) | **ProvingPod** | this document |
| Domain | — | provingpod.ai (preferred) / .dev / .com | suggested to register |
| CLI | — | `pp` (`pp up` = start a proving pod) | planned |
| Gateway image | gateway:v4 | **proving-gw:v1** | re-tagged |
| User image | userenv:v2 | **proving-pod:v1** | re-tagged |
| Gateway container | gateway (old container name) | provingpod-gateway (at next rebuild) | pending switch |
| User container | hex_<user> | proving-<user> (provision logic change) | pending switch |
| Data volume | gw-data (old volume name) | provingpod-data | pending switch |
| Cleanup service | docker-ephemeral-cleanup | provingpod-cleanup | pending switch |

> Note: re-tagging an image is a zero-risk operation (the reference points to the same image ID, running containers are unaffected); the deprecated internal-codename images gateway:v4 / userenv:v2 have all been re-tagged to provingpod-* and retired; renaming containers/volumes/services requires rebuilds and is executed as a "switch plan" in a safe maintenance window (see below).

## Architecture (current, Docker edition)

```text
[client] ssh <6-char hex>@<host> -p 6901 (password 123456)
   │
   ▼
[provingpod-gateway]  gateway container (sshd + PAM + libnss_hex6 + provision)
   │  auth: pam_exec expose_authtok verifies the password + account stage creates the proving pod
   │  jump: ForceCommand → sudo docker exec (command pass-through supported)
   ▼
[proving-<user>]  per-user isolated proving pod (proving-pod:v1)
   ├─ node 22 + npm + git (npm install native compilation OK)
   ├─ XFCE desktop + TigerVNC(5900) + noVNC(6901) + Chrome
   └─ random port mapping + isolated network namespace (same ports never conflict)
```

## Slogan candidates

```text
Primary: Prove it in a pod.          (prove it inside a pod)
Alt: SSH in. Prove it. Ship it.      (log in, prove it, ship it)
Alt: Where AI code gets proved.      (where AI code gets proved)
Alt: One command. One verdict.       (one command, one verdict)
```

## Positioning guardrails (agreement after the naming debate)

> Naming debate (ProvingPod vs TestingPod) verdict: ProvingPod won, but it must stay anchored to "constructive proof" semantics —
> **code that runs = proof it can run**, with no promise of mathematical "absolute correctness".

- Slogans anchored to "it runs": "Prove it in a pod" / "Prove it runs"
- Avoid "prove correctness / guarantee" phrasing (Dijkstra: testing cannot prove the absence of bugs)
- Positioning narrative: not formal proof, but "verified, ran, released" (proving ground semantics)

## Usage

```bash
# One command to get a proving pod (auto-created, ~1s)
ssh <random 6-char hex>@<host> -p 6901      # password 123456
# Command mode (pass-through execution)
ssh <hex>@<host> -p 6901 'npm install && npm test'
# Desktop/browser verification (noVNC)
# Actual ports are in /data/ephemeral-users/<hex>.ports on the gateway
```

## Verification matrix (tested 2026-08-09, all passed)

End-to-end SSH 10/10, npm install (with native compilation), desktop + Chrome, noVNC, port isolation, multi-user concurrency, TTL cleanup, gateway restart persistence, incus edition coexistence without regression.

## Switch plan (server component renames, executed in a safe maintenance window)

1. Images already re-tagged (zero-risk, done)
2. At the next gateway container rebuild, use `--name provingpod-gateway` + volume `provingpod-data`
3. Change provision.sh user-container prefix `hex_` → `proving-` (must update enter.sh/cleanup scripts to match)
4. Rename the cleanup service to provingpod-cleanup.service/timer
5. After all renames, verify: SSH login, desktop, cleanup, regression

## Security notes (required before production)

- Gateway mounting docker.sock ≈ host root → use a restricted RPC / minimal exposure
- Password 123456 is public and fixed → per-user passwords + fail2ban + ufw allowlist
- VNC password is shared → make it per-user
