#!/bin/bash
# ProvingPod gateway entrypoint:
#   - persist ssh host keys under /data/ssh (survives container recreation, so clients don't get
#     host-key-change warnings on redeploy)
#   - start sshd in the foreground
set -e

HOSTKEY_DIR="/data/ssh"
mkdir -p "$HOSTKEY_DIR"

for k in rsa ed25519 ecdsa; do
  key="$HOSTKEY_DIR/ssh_host_${k}_key"
  if [ ! -f "$key" ]; then
    echo "==> generating ssh host key: $key"
    ssh-keygen -q -t "$k" -f "$key" -N "" >/dev/null
  fi
  # make sure sshd finds them at the standard location
  install -m 600 "$key" "/etc/ssh/ssh_host_${k}_key"
  install -m 644 "$key.pub" "/etc/ssh/ssh_host_${k}_key.pub"
done

echo "==> starting sshd"
exec /usr/sbin/sshd -D
