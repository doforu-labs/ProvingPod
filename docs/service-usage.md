# Service usage

Day-to-day usage of a running ProvingPod host. For deployment, configuration and teardown see
[operations.md](operations.md); for the internals see [architecture.md](architecture.md).

## The account model

Accounts are temporary: any 6-character lowercase-hex username (like `3f2a9c`) plus the default
password `123456`. The first SSH connection auto-creates an isolated Docker container (a proving
pod) and drops you straight in. Use `-tt` for an interactive session, or pass a command through for
batch execution. `sftp` / `scp` are not available — see [below](#why-sftp--scp-do-not-work).

## How to connect

```bash
ssh 3f2a9c@<host> -p 6901        # password: 123456
```

Any 6-character lowercase-hex name is valid; a fresh name gets a fresh container, and reusing the
same name resumes your existing container (within the TTL).

## Session modes

| Purpose | Command | Notes |
|---|---|---|
| Interactive shell | `ssh -tt <hex>@<host> -p 6901` | `-tt` gives you a clean interactive bash in the pod |
| One-off command | `ssh <hex>@<host> -p 6901 'npm install && npm test'` | Command pass-through; works without `-tt` |
| Scripted session | `printf 'cmd && exit\n' \| ssh -tt <hex>@<host> -p 6901` | Robust against the jump banner |

```bash
# run the test suite and leave
ssh 3f2a9c@<host> -p 6901 'npm install && npm test'
```

## What is in a pod

- Node 22 LTS + npm + git + build-essential — native npm modules compile fine.
- XFCE desktop + TigerVNC (`:5900`) + noVNC (`:6901`) + Google Chrome.
- 2 GB RAM / 2 CPU, its own network namespace, randomly assigned host ports.

## Desktop (VNC / noVNC)

Each pod publishes random host ports for VNC and noVNC. Read yours from the gateway:

```bash
docker exec provingpod-gateway cat /data/ephemeral-users/<hex>.ports
# 5900/tcp =0.0.0.0:32768   <- VNC
# 6901/tcp =0.0.0.0:32769   <- noVNC web (open http://<host>:32769/ in a browser)
```

The VNC password defaults to `vncpass` (shared across pods; set it per pod with the `VNC_PASS`
environment variable). The full port scheme is in [operations.md](operations.md#ports).

## Why sftp / scp do not work

**`sftp` and `scp` are not available.** sshd's `ForceCommand` always runs the jump script, and
sftp/scp are SSH subsystems that expect a clean protocol stream. The jump emits the container
banner before the protocol handshake completes, corrupting the framing → `Connection closed` /
`Received message too long` / a hang.

Workaround: move files **inside** the pod (pipe base64/tar over the SSH channel), or stage them
through git.

## Related

- Deployment, configuration, resource limits, TTL and teardown — [operations.md](operations.md)
- How login and provisioning work — [architecture.md](architecture.md)
- The 1st-generation incus edition — [migration-notes.md](migration-notes.md)
