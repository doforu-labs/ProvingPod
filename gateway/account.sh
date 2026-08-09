#!/bin/bash
# PAM account hook: hex6 user -> ensure the user container exists (provision) + refresh lastseen
U=$PAM_USER
[[ "$U" =~ ^[0-9a-f]{6}$ ]] || exit 0
mkdir -p /data/ephemeral-users
if ! /opt/gateway/provision.sh "$U"; then
  exit 1
fi
date +%s > "/data/ephemeral-users/$U.lastseen" 2>/dev/null || true
exit 0
