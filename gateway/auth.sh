#!/bin/bash
# PAM auth hook (used with sshd: auth sufficient pam_exec.so quiet expose_authtok)
#   - non-hex6 user -> exit 1 (hand back to pam_unix system auth)
#   - hex6 user -> read password from stdin (expose_authtok, no newline), compare against passwd.conf
U=$PAM_USER
[[ "$U" =~ ^[0-9a-f]{6}$ ]] || exit 1
pass=$(cat)
conf=/opt/gateway/passwd.conf
[ -r "$conf" ] || exit 1
expected=$(sed -n 's/^PASSWORD=//p' "$conf" | head -1)
[ -n "$expected" ] || exit 1
want=$(printf '%s' "$expected" | sha256sum | awk '{print $1}')
got=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
[ "$got" = "$want" ] || exit 1
exit 0
