#!/bin/bash
# ProvingPod one-shot deploy: obtain the images, start the gateway (+ optional TTL cleanup timer)
#
# Usage:
#   sudo ./deploy/deploy.sh                  # x86_64: build. anything else: pull prebuilt images
#   sudo ./deploy/deploy.sh --from-registry  # force the prebuilt GHCR images
#   sudo ./deploy/deploy.sh --build          # force a local build here
#   sudo ./deploy/deploy.sh --skip-build     # only (re)create the gateway container
#   sudo ./deploy/deploy.sh --with-cleanup   # also install the hourly TTL cleanup timer
#
# Knobs (env):
#   IMAGE_SOURCE=auto|build|registry|skip   where the images come from (default: auto)
#   PROVINGPOD_VERSION=v0.1.0               which prebuilt release to pull (see deploy/images.env)
#   GATEWAY_IMAGE / USERENV_IMAGE           use your own images; wins over everything above
#   GATEWAY_PORT=6901  MAX_USERS=8  TTL_DAYS=3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

GATEWAY_PORT="${GATEWAY_PORT:-6901}"
MAX_USERS="${MAX_USERS:-8}"
TTL_DAYS="${TTL_DAYS:-3}"
IMAGE_SOURCE="${IMAGE_SOURCE:-auto}"
WITH_CLEANUP=0

for arg in "$@"; do
  case "$arg" in
    --with-cleanup)  WITH_CLEANUP=1 ;;
    --from-registry) IMAGE_SOURCE=registry ;;
    --build)         IMAGE_SOURCE=build ;;
    --skip-build)    IMAGE_SOURCE=skip ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# --- where do the images come from? ------------------------------------------
# Both images are amd64-only: the pod image installs Chrome's amd64 .deb (there is no arm64
# Linux build of Chrome) and the gateway compiles its NSS module into /usr/lib/x86_64-linux-gnu.
# On anything but x86_64 the choice is emulate x86_64 locally, or use the images this project
# builds on an x86_64 runner. Default: build natively on x86_64, pull everywhere else.
HOST_ARCH="$(uname -m)"
if [ "$IMAGE_SOURCE" = auto ]; then
  if [ "$HOST_ARCH" = x86_64 ]; then IMAGE_SOURCE=build; else IMAGE_SOURCE=registry; fi
fi
case "$IMAGE_SOURCE" in
  build|registry|skip) ;;
  *) echo "IMAGE_SOURCE must be auto|build|registry|skip (got: $IMAGE_SOURCE)" >&2; exit 2 ;;
esac

if [ "$IMAGE_SOURCE" = registry ]; then
  # An explicit PROVINGPOD_VERSION beats the pinned default in images.env.
  if [ -n "${PROVINGPOD_VERSION:-}" ]; then VERSION="$PROVINGPOD_VERSION"; export VERSION; fi
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/images.env"
  : "${GATEWAY_IMAGE:=${REGISTRY}/${GATEWAY_IMAGE_NAME}:${VERSION}}"
  : "${USERENV_IMAGE:=${REGISTRY}/${POD_IMAGE_NAME}:${VERSION}}"
else
  : "${GATEWAY_IMAGE:=proving-gw:v1}"
  : "${USERENV_IMAGE:=proving-pod:v1}"
fi

# The published images are amd64-only, and `docker pull` matches manifests against the host
# platform by default. On an arm64 host a plain pull therefore fails outright with
#   no matching manifest for linux/arm64/v8 in the manifest list entries
# instead of falling back to the one platform on offer — verified on colima aarch64. So name the
# platform explicitly. (`docker run` survives without it and only warns, but passing it keeps the
# logs clean.) On x86_64 nothing is added, so behaviour there is unchanged.
PLATFORM_ARGS=()
if [ "$HOST_ARCH" != x86_64 ]; then
  PLATFORM_ARGS=(--platform linux/amd64)
fi

echo "==> ProvingPod deploy (gateway=$GATEWAY_PORT, max_users=$MAX_USERS, ttl=$TTL_DAYS days)"

# --- sanity ---
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "cannot talk to docker daemon (are you root / in the docker group?)" >&2; exit 1; }
if [ ! -d gateway ] || [ ! -d userenv ]; then
  echo "gateway/ or userenv/ missing" >&2
  exit 1
fi

# --- architecture guard (only when we are actually about to build) ----------
# The pod image is amd64-only: Chrome is installed from google-chrome-stable_current_amd64.deb.
# On a non-x86_64 host a local build either fails at the Chrome step (native arm64 build) or runs
# apt under QEMU user-mode emulation, where QEMU segfaults inside the emulated process:
#   Exception: ('python3.12', '-c', 'import importlib.util; ...') failed with status code -11
# That is an upstream QEMU bug (docker/setup-qemu-action#188, qemu-project/qemu#3130), not ours —
# and it is intermittent, which is what makes it expensive: it appears ten minutes into a build
# rather than immediately. So do not start a build that has to go through emulation.
if [ "$IMAGE_SOURCE" = build ] && [ "$HOST_ARCH" != x86_64 ] && [ "${FORCE_BUILD:-0}" != "1" ]; then
  cat >&2 <<'EOF'
==> refusing to build the amd64-only images on a non-x86_64 host.

    A local build here has to emulate x86_64, and QEMU intermittently segfaults inside
    emulated apt processes — a random failure ten minutes in, not a clean one.

    Use the images this project already built on an x86_64 runner:

        sudo ./deploy/deploy.sh --from-registry

    Other options:

      * Apple Silicon, and you want a local build anyway — Rosetta replaces QEMU.
        In the real pod build the QEMU path died and the Rosetta path went through
        (3m58s, 589 MB), so this is the way to build here:
            colima start --arch aarch64 --vm-type=vz --vz-rosetta
        (--arch must stay aarch64: with --arch x86_64 colima ignores --vz-rosetta and uses QEMU)
        then: sudo ./deploy/deploy.sh --build

      * Build on any x86_64 Linux host and point this one at your own images:
            GATEWAY_IMAGE=... USERENV_IMAGE=... sudo ./deploy/deploy.sh --skip-build

      * Override this check and accept the random failures: FORCE_BUILD=1
EOF
  exit 1
fi

# --- obtain the images -------------------------------------------------------
pull_or_die() {
  local ref="$1"
  if docker pull ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} "$ref"; then return 0; fi
  cat >&2 <<EOF

==> could not pull $ref

    Either nothing is published under that name yet, or the version is wrong, or the
    package is private and this host has not logged in (docker login ghcr.io).

      what exists:    https://github.com/yctech2026/ProvingPod/pkgs/container/provingpod-gateway
      pick another:   PROVINGPOD_VERSION=v0.2.0 sudo ./deploy/deploy.sh --from-registry
      build instead:  sudo ./deploy/deploy.sh --build
      your own refs:  GATEWAY_IMAGE=... USERENV_IMAGE=... sudo ./deploy/deploy.sh --skip-build
EOF
  exit 1
}

case "$IMAGE_SOURCE" in
  build)
    echo "==> building $USERENV_IMAGE (needs internet for apt/node/chrome)..."
    docker build --network host -t "$USERENV_IMAGE" userenv/
    echo "==> building $GATEWAY_IMAGE..."
    docker build --network host -t "$GATEWAY_IMAGE" gateway/
    ;;
  registry)
    echo "==> pulling prebuilt images (no local build, no x86_64 emulation)"
    pull_or_die "$USERENV_IMAGE"
    pull_or_die "$GATEWAY_IMAGE"
    ;;
  skip)
    echo "==> --skip-build: using existing images"
    ;;
esac

# --- (re)create gateway ---
echo "==> (re)creating gateway container"
docker rm -f provingpod-gateway >/dev/null 2>&1 || true
docker run -d --name provingpod-gateway --restart=unless-stopped \
  ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} \
  -p "${GATEWAY_PORT}:22" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v provingpod-data:/data \
  -e USER_IMAGE="$USERENV_IMAGE" \
  -e MAX_USERS="$MAX_USERS" \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE --cap-add SYS_CHROOT --cap-add SETUID \
  --cap-add SETGID --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add AUDIT_WRITE \
  --security-opt no-new-privileges:false \
  "$GATEWAY_IMAGE"
echo "==> gateway started: ssh <hex>@<host> -p ${GATEWAY_PORT}  (password: see gateway/passwd.conf)"

# --- optional TTL cleanup timer ---
if [ "$WITH_CLEANUP" = "1" ]; then
  echo "==> installing hourly TTL cleanup (TTL_DAYS=$TTL_DAYS)"
  sed "s|TTL_DAYS=\${TTL_DAYS:-3}|TTL_DAYS=\"$TTL_DAYS\"|" deploy/docker-ephemeral-cleanup.sh \
    > /usr/local/sbin/docker-ephemeral-cleanup.sh
  chmod 755 /usr/local/sbin/docker-ephemeral-cleanup.sh
  cp deploy/docker-ephemeral-cleanup.service /etc/systemd/system/
  cp deploy/docker-ephemeral-cleanup.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now docker-ephemeral-cleanup.timer >/dev/null 2>&1
  systemctl status docker-ephemeral-cleanup.timer --no-pager | head -5
fi

echo "==> done. Quick check:"
docker ps --filter name=provingpod-gateway --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
