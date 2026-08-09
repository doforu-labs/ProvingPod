#!/bin/bash
# ProvingPod one-shot deploy: build images + start gateway (+ optional TTL cleanup timer)
# Usage:
#   sudo ./deploy/deploy.sh              # build + run gateway
#   sudo ./deploy/deploy.sh --with-cleanup   # also install the hourly TTL cleanup timer
#   sudo ./deploy/deploy.sh --skip-build     # only (re)create the gateway container
set -euo pipefail

cd "$(dirname "$0")/.."

GATEWAY_IMAGE="${GATEWAY_IMAGE:-proving-gw:v1}"
USERENV_IMAGE="${USERENV_IMAGE:-proving-pod:v1}"
GATEWAY_PORT="${GATEWAY_PORT:-6901}"
MAX_USERS="${MAX_USERS:-8}"
TTL_DAYS="${TTL_DAYS:-3}"
WITH_CLEANUP=0
SKIP_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --with-cleanup) WITH_CLEANUP=1 ;;
    --skip-build)   SKIP_BUILD=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> ProvingPod deploy (gateway=$GATEWAY_PORT, max_users=$MAX_USERS, ttl=$TTL_DAYS days)"

# --- sanity ---
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "cannot talk to docker daemon (are you root / in the docker group?)" >&2; exit 1; }
if [ ! -d gateway ] || [ ! -d userenv ]; then
  echo "gateway/ or userenv/ missing" >&2
  exit 1
fi

# --- build ---
if [ "$SKIP_BUILD" = "0" ]; then
  echo "==> building $USERENV_IMAGE (needs internet for apt/node/chrome)..."
  docker build --network host -t "$USERENV_IMAGE" userenv/
  echo "==> building $GATEWAY_IMAGE..."
  docker build --network host -t "$GATEWAY_IMAGE" gateway/
else
  echo "==> --skip-build: using existing images"
fi

# --- (re)create gateway ---
echo "==> (re)creating gateway container"
docker rm -f provingpod-gateway >/dev/null 2>&1 || true
docker run -d --name provingpod-gateway --restart=unless-stopped \
  -p "${GATEWAY_PORT}:22" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker \
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
