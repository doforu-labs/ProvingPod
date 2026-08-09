#!/bin/bash
# ============================================================
# ephemeral-provision.sh - create the ephemeral user environment (run as root)
# Invoked by the PAM hook provision-user.sh after password verification.
# Host accounts are already covered by the NSS virtual users (libnss_hex6), so no useradd;
# it only creates: container + isolated network + in-container user + lastseen + network isolation.
# Idempotent: reuses the container/network/in-container user if they already exist (orphan leftovers tolerated).
# ============================================================
set -e
U=$1
[ -n "$U" ] && echo "$U" | grep -qE '^[0-9a-f]{6}$' || { echo "BAD_USER"; exit 1; }
source /etc/ephemeral-users.conf

# Host already has a real account (leftover from the old mechanism) -> idempotent return (NSS virtual users don't count)
grep -q "^$U:" /etc/passwd && exit 0

# Container already exists (orphan/partial) -> reuse it directly, no new quota consumed
if incus list "c-$U" </dev/null | grep -q RUNNING; then
  # in-container user (idempotent)
  if ! incus exec "c-$U" -- id "$U" </dev/null >/dev/null 2>&1; then
    incus exec "c-$U" -- useradd -m -s /bin/bash --badname "$U" </dev/null
    echo "$U:$PASSWORD" | incus exec "c-$U" -- chpasswd
  fi
  mkdir -p /var/lib/ephemeral-users
  date +%s > "/var/lib/ephemeral-users/$U.lastseen"
  /usr/local/sbin/doforu-net-isolate.sh
  echo "==> $U ready (reused)"
  exit 0
fi

# Container count limit (checked only when creating new containers)
COUNT=$(incus list --format csv </dev/null | grep -c '^c-')
[ "$COUNT" -ge "$MAX_CONTAINERS" ] && { echo "LIMIT_REACHED($MAX_CONTAINERS)"; exit 1; }

echo "==> provisioning $U"

# Free subnet range 10.103.x ~ 10.250.x
SUBNET=""
for i in $(seq 103 250); do
  if ! ip route show | grep -q "10.$i.0.0/24"; then SUBNET="10.$i.0.0/24"; break; fi
done
[ -z "$SUBNET" ] && { echo "NO_SUBNET"; exit 1; }
GW=$(echo "$SUBNET" | sed 's|\.0\.0/24|.0.1|')

# 1) isolated network (idempotent)
if ! incus network show "net-$U" </dev/null >/dev/null 2>&1; then
  incus network create "net-$U" ipv4.address="$GW/24" ipv4.nat=true ipv6.address=none </dev/null
fi

# 2) container (skip if it already exists; the normal flow launches after the quota check)
incus launch vreg-runtime "c-$U" --network "net-$U" </dev/null
for i in $(seq 1 30); do
  incus list "c-$U" </dev/null | grep -q RUNNING && break
  sleep 2
done
incus config set "c-$U" limits.cpu "$CPU_LIMIT" </dev/null
incus config set "c-$U" limits.memory "$MEM_LIMIT" </dev/null

# 3) in-container user (idempotent)
if ! incus exec "c-$U" -- id "$U" </dev/null >/dev/null 2>&1; then
  incus exec "c-$U" -- useradd -m -s /bin/bash --badname "$U" </dev/null
  echo "$U:$PASSWORD" | incus exec "c-$U" -- chpasswd
fi

# 4) lastseen
mkdir -p /var/lib/ephemeral-users
date +%s > "/var/lib/ephemeral-users/$U.lastseen"

# 5) refresh network isolation
/usr/local/sbin/doforu-net-isolate.sh
echo "==> $U ready"
