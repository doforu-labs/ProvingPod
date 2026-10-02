#!/usr/bin/env bash
# ProvingPod local demo — one command to a verified answer.
#
#   ./demo.sh              get the images if needed, start the gateway, run a sample verification
#   ./demo.sh down         stop everything (gateway + all pods + data)
#   ./demo.sh shell        open an interactive shell inside a pod
#   ./demo.sh logs         follow the gateway log
#   ./demo.sh check        re-run only the sample verification
#
# Knobs (env):
#   GATEWAY_PORT=6901      host port for the SSH gateway
#   MAX_USERS=4            concurrent pod limit
#   IMAGE_SOURCE=auto      auto | build | registry | skip
#                          auto builds on x86_64 and pulls the published images everywhere else,
#                          which is what lets an Apple Silicon or arm64 Linux host run this
#                          without emulating x86_64 (see README "Troubleshooting")
#   PROVINGPOD_VERSION=…   which prebuilt release to pull (default: deploy/images.env)
#   PLATFORM=linux/amd64   force the build/run platform when you really are building under emulation
#   SKIP_BUILD=1           alias for IMAGE_SOURCE=skip — use the images already present
#   FORCE=1                skip the host preflight (testing only — mounts must still resolve)
#
# Requirements and the security caveat are documented at the top of docker-compose.demo.yml.
set -euo pipefail
cd "$(dirname "$0")"

GATEWAY_PORT="${GATEWAY_PORT:-6901}"
MAX_USERS="${MAX_USERS:-4}"
PASSWORD="${PASSWORD:-123456}"
PLATFORM="${PLATFORM:-}"
FORCE="${FORCE:-0}"
IMAGE_SOURCE="${IMAGE_SOURCE:-auto}"

# Both images are amd64-only: Chrome has no arm64 Linux build, and the gateway compiles its
# NSS module into /usr/lib/x86_64-linux-gnu. So on anything but x86_64 the choice is emulate
# x86_64 or use the images published from an x86_64 runner. Emulating is the expensive option:
# QEMU intermittently segfaults inside emulated apt processes, minutes into a build.
if [ "${SKIP_BUILD:-0}" = 1 ]; then IMAGE_SOURCE=skip; fi
if [ "$IMAGE_SOURCE" = auto ]; then
  if [ "$(uname -m)" = x86_64 ]; then IMAGE_SOURCE=build; else IMAGE_SOURCE=registry; fi
fi
case "$IMAGE_SOURCE" in
  build|registry|skip) ;;
  *) echo "IMAGE_SOURCE must be auto|build|registry|skip (got: $IMAGE_SOURCE)" >&2; exit 2 ;;
esac

if [ "$IMAGE_SOURCE" = registry ]; then
  # An explicit PROVINGPOD_VERSION beats the pinned default in images.env.
  if [ -n "${PROVINGPOD_VERSION:-}" ]; then VERSION="$PROVINGPOD_VERSION"; export VERSION; fi
  # shellcheck source=/dev/null
  . ./deploy/images.env
  : "${GATEWAY_IMAGE:=${REGISTRY}/${GATEWAY_IMAGE_NAME}:${VERSION}}"
  : "${USERENV_IMAGE:=${REGISTRY}/${POD_IMAGE_NAME}:${VERSION}}"
else
  : "${GATEWAY_IMAGE:=proving-gw:v1}"
  : "${USERENV_IMAGE:=proving-pod:v1}"
fi

# Name the platform explicitly on a non-x86_64 host. Our published tags are single-platform
# manifests (publish.yml sets provenance: false), so a plain pull happens to work on arm64 — but
# naming it keeps the run-time logs clean, and it stops being optional if a release is ever
# published as a manifest index, where a plain pull on arm64 fails with "no matching manifest for
# linux/arm64/v8 in the manifest list entries" instead of falling back to the one platform on
# offer (verified on colima aarch64). It also has to reach compose and the gateway's own
# `docker run` of pod containers — that is what DOCKER_DEFAULT_PLATFORM is for. On x86_64 nothing
# changes.
PLATFORM_ARGS=()
if [ "$(uname -m)" != x86_64 ]; then
  PLATFORM_ARGS=(--platform linux/amd64)
  export DOCKER_DEFAULT_PLATFORM=linux/amd64
fi

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

compose() { docker compose -f docker-compose.demo.yml "$@"; }

# ---------------------------------------------------------------- preflight --
preflight() {
  have docker || die "docker not found in PATH"
  docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon (is it running? are you in the docker group?)"

  if [ "$FORCE" != "1" ]; then
    [ "$(uname -s)" = "Linux" ] || die "this demo needs a LINUX host.
   It bind-mounts /var/run/docker.sock so the gateway can create sibling containers, and the
   Docker daemon resolves that path in its own namespace — it does not exist on $(uname -s).
   Run it on a Linux box or inside WSL2. (FORCE=1 bypasses this check.)"
    [ -S /var/run/docker.sock ] || die "/var/run/docker.sock not found — is this a Docker Desktop style host?"
    if [ "$IMAGE_SOURCE" = build ] && [ "$(uname -m)" != "x86_64" ] && [ -z "$PLATFORM" ]; then
      die "host is $(uname -m), but both images are x86_64-only
   (gateway compiles into /usr/lib/x86_64-linux-gnu; the pod image installs Chrome's amd64 .deb).
   Building them here means emulating x86_64, and QEMU does that unreliably — expect random
   'failed with status code -11' failures during apt, minutes into the build.
   Drop IMAGE_SOURCE=build and the published images are pulled instead, or:
     * Apple Silicon, build locally anyway: colima start --arch aarch64 --vm-type=vz --vz-rosetta
       (--arch must stay aarch64; with --arch x86_64 colima ignores --vz-rosetta and uses QEMU)
     * other hosts: build on an x86_64 Linux host and reuse those images here.
   PLATFORM=linux/amd64 FORCE=1 to build under emulation anyway."
    fi
  else
    warn "FORCE=1: skipping host preflight (testing mode)"
  fi

  if [ "$(id -u)" = "0" ]; then
    :
  elif ! docker ps >/dev/null 2>&1; then
    die "your user cannot talk to Docker; add yourself to the docker group or run as root"
  fi
}

# ------------------------------------------------------------------- images --
ensure_images() {
  case "$IMAGE_SOURCE" in
    skip)
      say "using the images already present ($USERENV_IMAGE, $GATEWAY_IMAGE)"
      return ;;
    registry)
      say "pulling prebuilt images — no local build, no x86_64 emulation"
      docker pull ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} "$USERENV_IMAGE" || die "cannot pull $USERENV_IMAGE
   Nothing is published under that name yet, or the version is wrong, or the package is
   private and this host has not run 'docker login ghcr.io'.
   Try PROVINGPOD_VERSION=<other tag>, or IMAGE_SOURCE=build to build it here."
      docker pull ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} "$GATEWAY_IMAGE" || die "cannot pull $GATEWAY_IMAGE (same reasons as above)"
      return ;;
  esac

  local -a plat=()
  [ -n "$PLATFORM" ] && plat=(--platform "$PLATFORM")
  if docker image inspect "$USERENV_IMAGE" >/dev/null 2>&1; then
    say "pod image $USERENV_IMAGE already present (delete it to rebuild)"
  else
    say "building $USERENV_IMAGE — this is the slow one (XFCE + Chrome, minutes on a cold cache)"
    docker build ${plat[@]+"${plat[@]}"} -t "$USERENV_IMAGE" userenv/
  fi
  if docker image inspect "$GATEWAY_IMAGE" >/dev/null 2>&1; then
    say "gateway image $GATEWAY_IMAGE already present (delete it to rebuild)"
  else
    say "building $GATEWAY_IMAGE"
    docker build ${plat[@]+"${plat[@]}"} -t "$GATEWAY_IMAGE" gateway/
  fi
}

# --------------------------------------------------------------- ssh helper --
# The gateway disables public-key auth (PubkeyAuthentication no in sshd_config), so
# unattended use needs the password. We feed it through SSH_ASKPASS (OpenSSH >= 8.4,
# SSH_ASKPASS_REQUIRE=force), falling back to sshpass when that is what you have.
ASKPASS_SCRIPT=""
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10
          -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1)

setup_askpass() {
  ASKPASS_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/provingpod-askpass.XXXXXX")"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$PASSWORD" > "$ASKPASS_SCRIPT"
  chmod 700 "$ASKPASS_SCRIPT"
  trap 'rm -f "$ASKPASS_SCRIPT"' EXIT
}

# ssh_cmd <hex6-user> <remote-command>   ->  remote exit code
ssh_cmd() {
  local user="$1" remote="$2"
  if [ -n "$ASKPASS_SCRIPT" ]; then
    SSH_ASKPASS="$ASKPASS_SCRIPT" SSH_ASKPASS_REQUIRE=force \
      ssh "${SSH_OPTS[@]}" -p "$GATEWAY_PORT" "$user@localhost" "$remote"
  elif have sshpass; then
    sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" -p "$GATEWAY_PORT" "$user@localhost" "$remote"
  else
    warn "no sshpass and no SSH_ASKPASS support — you will be prompted for the password ($PASSWORD)"
    ssh "${SSH_OPTS[@]}" -p "$GATEWAY_PORT" "$user@localhost" "$remote"
  fi
}

wait_for_gateway() {
  local user="$1"
  say "waiting for the gateway on port $GATEWAY_PORT ..."
  for _ in $(seq 1 60); do
    if ssh_cmd "$user" 'true' >/dev/null 2>&1; then say "gateway is up"; return 0; fi
    sleep 1
  done
  die "gateway did not accept SSH within 60s — try: docker logs provingpod-demo-gateway"
}

# ------------------------------------------------------------------- verify --
verify() {
  local user rc
  user="$(openssl rand -hex 3)"
  say "using a brand-new pod: $user  (its container is created on first connect)"
  wait_for_gateway "$user"

  say "1/3  code that passes — the exit code is the verdict"
  if ssh_cmd "$user" 'node -e "const s=[1,2,3].reduce((a,b)=>a+b,0); if(s!==6) process.exit(1); console.log(\"sum ok\")"'; then
    say "     exit code 0  ->  verified: it actually runs"
  else
    rc=$?; die "expected exit 0 but got $rc"
  fi

  say "2/3  code that fails — failures are reported, not swallowed"
  rc=0
  ssh_cmd "$user" 'node -e "require(\"fs\").readFileSync(\"/definitely-not-here\")"' || rc=$?
  if [ "$rc" -eq 0 ]; then die "a failing command returned 0 — exit-code passthrough is broken"; fi
  say "     exit code $rc  ->  the failure came back as a verdict"

  say "3/3  the README one-liner: npm install && npm test"
  if ssh_cmd "$user" 'mkdir -p ~/demo && cd ~/demo && npm init -y >/dev/null && npm pkg set scripts.test="node -e \"process.exit(0)\"" >/dev/null && npm test'; then
    say "     exit code 0  ->  npm test ran inside the pod"
  else
    rc=$?; die "npm test failed (exit $rc)"
  fi

  echo
  say "all three checks passed. Your pod is still running:"
  ssh_cmd "$user" 'node -v; pwd; ls -a' || true
  echo
  cat <<EOF
$(printf '\033[1;32m done \033[0m') ProvingPod works on this machine.

  new pod any time   ssh <any-6-hex>@localhost -p $GATEWAY_PORT     (password: $PASSWORD)
  interactive shell  ./demo.sh shell
  gateway log        ./demo.sh logs
  tear everything down  ./demo.sh down
EOF
}

# --------------------------------------------------------------------- down --
down_all() {
  say "removing pods (hex_* containers are not compose services, so compose alone won't do it)"
  local -a pods=()
  mapfile -t pods < <(docker ps -aq --filter 'name=^hex_' || true)
  if [ "${#pods[@]}" -gt 0 ]; then
    docker rm -f "${pods[@]}" >/dev/null
  else
    say "no pods to remove"
  fi
  compose down -v --remove-orphans
  say "done"
}

# --------------------------------------------------------------------- main --
cmd="${1:-up}"
case "$cmd" in
  up)
    preflight
    ensure_images
    setup_askpass
    say "starting the gateway"
    GATEWAY_IMAGE="$GATEWAY_IMAGE" USERENV_IMAGE="$USERENV_IMAGE" MAX_USERS="$MAX_USERS" \
      GATEWAY_PORT="$GATEWAY_PORT" compose up -d
    verify
    ;;
  check)
    preflight; setup_askpass; verify
    ;;
  down)  down_all ;;
  logs)  compose logs -f --tail=100 ;;
  shell)
    preflight; setup_askpass
    user="${2:-$(openssl rand -hex 3)}"
    say "opening an interactive shell in pod $user (password: $PASSWORD)"
    exec ssh "${SSH_OPTS[@]}" -p "$GATEWAY_PORT" "$user@localhost"
    ;;
  *) die "unknown command: $cmd (use: up|check|down|logs|shell)" ;;
esac
