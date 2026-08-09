#!/bin/bash
# Docker edition ephemeral user cleanup: lastseen TTL + orphan metadata fallback
TTL_DAYS="${TTL_DAYS:-3}"
DATA_DIR="/var/lib/docker/volumes/provingpod-data/_data/ephemeral-users"
TTL=$((TTL_DAYS*24*3600)); NOW=$(date +%s)
[ -d "$DATA_DIR" ] || exit 0
for f in "$DATA_DIR"/*.lastseen; do
  [ -f "$f" ] || continue
  U=$(basename "$f" .lastseen)
  docker ps --format "{{.Names}}" | grep -qx "hex_$U" && continue
  AGE=$((NOW-$(cat "$f")))
  if [ "$AGE" -gt "$TTL" ]; then
    echo "==> expire hex_$U (age ${AGE}s > TTL ${TTL}s)"
    docker rm -f "hex_$U" >/dev/null 2>&1 || true
    rm -f "$DATA_DIR/$U.lastseen" "$DATA_DIR/$U.ports"
  fi
done
# orphan metadata fallback
for p in "$DATA_DIR"/*.ports; do
  [ -f "$p" ] || continue
  U=$(basename "$p" .ports)
  docker ps -a --format "{{.Names}}" | grep -qx "hex_$U" || rm -f "$DATA_DIR/$U.lastseen" "$p"
done
echo "cleanup done"
