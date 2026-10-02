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

# Persist the provisioning settings where the PAM account hook can reach them.
# pam_exec runs account.sh -> provision.sh in a minimal PAM environment that does NOT inherit the
# container's environment. Without this file, provision.sh always falls back to its built-in
# defaults, so USER_IMAGE / MAX_USERS set in compose or deploy.sh are silently ignored.
printf 'USER_IMAGE=%s\nMAX_USERS=%s\n' \
  "${USER_IMAGE:-proving-pod:v1}" "${MAX_USERS:-8}" > /data/gateway.env
echo "==> gateway.env: $(tr '\n' ' ' < /data/gateway.env)"

echo "==> starting sshd"
exec /usr/sbin/sshd -D
