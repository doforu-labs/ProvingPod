#!/bin/bash
# Create/reuse the user container hex_$U
#   - already exists -> idempotent return
#   - missing -> docker run (random host port mapping 6901/5900, docker auto-avoids conflicts)
#   - MAX_USERS quota check
# Port mapping is recorded to /data/ephemeral-users/$U.ports
set -e
U=$1
[[ "$U" =~ ^[0-9a-f]{6}$ ]] || { echo "BAD_USER"; exit 1; }
USER_IMAGE="${USER_IMAGE:-proving-pod:v1}"
MAX_USERS="${MAX_USERS:-8}"

if docker inspect "hex_$U" >/dev/null 2>&1; then
  echo "==> hex_$U exists"
  exit 0
fi

COUNT=$(docker ps -a --format '{{.Names}}' | grep -c '^hex_' || true)
[ "$COUNT" -ge "$MAX_USERS" ] && { echo "LIMIT_REACHED($MAX_USERS)"; exit 1; }

echo "==> creating hex_$U"
docker run -d --name "hex_$U" --memory 2g --cpus 2 \
  -p 6901 -p 5900 \
  "$USER_IMAGE" /start.sh >/dev/null

# Record port mapping (HOST_NO_VNC / HOST_VNC)
{ docker port "hex_$U" 2>/dev/null || true; } \
  | awk -F'-> ' '{gsub(/ /,"",$2); print $1"="$2}' \
  > "/data/ephemeral-users/$U.ports" 2>/dev/null || true
echo "==> hex_$U ready"
exit 0
