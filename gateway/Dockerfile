# ProvingPod SSH gateway image (Docker dynamic SSH user system gateway)
# sshd + libnss_hex6 + PAM (auth verifies password / account dynamically creates user containers) + ForceCommand jump via docker exec
#
# The Docker CLI is baked in on purpose. It used to be bind-mounted from the host
# (-v /usr/bin/docker:/usr/bin/docker), which only works while the host and the image share an
# architecture: on an arm64 host the mounted binary is aarch64 while this container is amd64, so
# every `sudo -n docker` call dies with
#   /usr/bin/docker: cannot execute: required file not found
# That fails the PAM account hook, and sshd drops the session right after a correct password.
FROM docker:27-cli AS dockercli

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server gcc make libc6-dev curl iproute2 ca-certificates sudo \
    && echo 'ALL ALL=(root) NOPASSWD: /usr/bin/docker' > /etc/sudoers.d/provingpod-docker \
    && chmod 440 /etc/sudoers.d/provingpod-docker \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI, at the exact path the sudoers rule above expects (`NOPASSWD: /usr/bin/docker`)
COPY --from=dockercli /usr/local/bin/docker /usr/bin/docker

# ---------- NSS virtual user module (compiled into the image) ----------
COPY nss_hex6.c /tmp/nss_hex6.c
RUN gcc -fPIC -shared -Wall -Wl,-soname,libnss_hex6.so.2 \
        -o /usr/lib/x86_64-linux-gnu/libnss_hex6.so.2 /tmp/nss_hex6.c \
    && rm /tmp/nss_hex6.c \
    && sed -i 's/^passwd:.*/passwd: files hex6 systemd/' /etc/nsswitch.conf \
    && sed -i 's/^shadow:.*/shadow: files hex6 systemd/' /etc/nsswitch.conf

# ---------- Admin user dev (uses the system auth path) ----------
RUN useradd -m -s /bin/bash dev && echo 'dev:123456' | chpasswd

# ---------- Gateway scripts and config ----------
COPY auth.sh account.sh provision.sh enter.sh entrypoint.sh /opt/gateway/
COPY passwd.conf /opt/gateway/passwd.conf
RUN chmod 755 /opt/gateway/auth.sh /opt/gateway/account.sh /opt/gateway/provision.sh /opt/gateway/enter.sh /opt/gateway/entrypoint.sh

# ---------- sshd + PAM ----------
COPY sshd_config /etc/ssh/sshd_config
COPY pam-sshd /etc/pam.d/sshd
RUN mkdir -p /run/sshd /data/ephemeral-users

EXPOSE 22
CMD ["/opt/gateway/entrypoint.sh"]
