#!/bin/bash
# ============================================================
# provision-user.sh - PAM authentication hook (run as root)
# Used with /etc/pam.d/sshd:
#   auth sufficient pam_exec.so quiet expose_authtok /usr/local/sbin/provision-user.sh
#
# Logic:
#   - non-hex6 user -> exit 1 (sufficient fails, continue normal auth via common-auth, e.g. dev)
#   - hex6 user   -> read password from stdin (expose_authtok, no newline), compare against PASSWORD in conf
#                    pass -> refresh lastseen or call ephemeral-provision.sh to create, exit 0 (short-circuit success)
#                    fail -> exit 1 (continue common-auth; pam_unix always fails for virtual users -> reject)
# ============================================================
U=$PAM_USER

# non-hex6 user: hand back to common-auth
[[ "$U" =~ ^[0-9a-f]{6}$ ]] || exit 1

# read password (stdin, no newline; read it all first so later commands don't consume it)
pass=$(cat)

# expected password
conf=/etc/ephemeral-users.conf
[ -r "$conf" ] || exit 1
expected=$(sed -n 's/^PASSWORD=//p' "$conf" | head -1)
[ -n "$expected" ] || exit 1

# sha256 normalized comparison (avoid plaintext in logs; timing difference is negligible since PASSWORD is a public fixed value)
want=$(printf '%s' "$expected" | sha256sum | awk '{print $1}')
got=$(printf '%s' "$pass" | sha256sum | awk '{print $1}')
[ "$got" = "$want" ] || exit 1

# password correct
mkdir -p /var/lib/ephemeral-users
if grep -q "^$U:" /etc/passwd; then
  # host already has a real account (leftover from the old mechanism): only refresh lastseen
  date +%s > "/var/lib/ephemeral-users/$U.lastseen" 2>/dev/null || true
  exit 0
fi

# missing -> create the container environment
/usr/local/sbin/ephemeral-provision.sh "$U"
rc=$?
if [ $rc -eq 0 ]; then
  date +%s > "/var/lib/ephemeral-users/$U.lastseen" 2>/dev/null || true
fi
exit $rc
