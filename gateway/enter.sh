#!/bin/bash
# sshd ForceCommand jump: enter the user container
#   - command mode (ssh host 'cmd'): pass SSH_ORIGINAL_COMMAND through to the container bash
#   - interactive mode (ssh host): docker exec -it for an interactive shell
U="${PAM_USER:-$USER}"
[[ "$U" =~ ^[0-9a-f]{6}$ ]] || exit 1
if ! sudo -n docker inspect "hex_$U" >/dev/null 2>&1; then
  sudo -n /opt/gateway/provision.sh "$U" || exit 1
fi
if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
  exec sudo -n docker exec "hex_$U" /bin/bash -l -c "$SSH_ORIGINAL_COMMAND"
elif [ -t 0 ]; then
  exec sudo -n docker exec -it "hex_$U" /bin/bash -l
else
  exec sudo -n docker exec -i "hex_$U" /bin/bash -l
fi
