# ProvingPod user environment image (runtime for the Docker dynamic SSH user system)
# Core: node22 + git + build-essential | Desktop: XFCE + TigerVNC + noVNC + Google Chrome
# Ports: in-container 5900 (VNC) + 6901 (noVNC web)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG=C.UTF-8

# ---------- Base tools ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg sudo git build-essential \
        locales tzdata dbus-x11 xauth \
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# ---------- Node.js 22 LTS (NodeSource, verified reachable) ----------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ---------- Desktop layer: XFCE + TigerVNC + noVNC ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal xfce4-session xfce4-panel xfce4-settings \
        tigervnc-standalone-server tigervnc-tools novnc websockify iproute2 \
    && rm -rf /var/lib/apt/lists/*

# ---------- Google Chrome (dl.google.com verified reachable; ubuntu's chromium-browser is a snap transition package, unusable inside containers) ----------
RUN curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update \
    && apt-get install -y /tmp/chrome.deb \
    && rm -f /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# ---------- Default user dev (for user containers) ----------
RUN useradd -m -s /bin/bash dev \
    && echo 'dev:123456' | chpasswd \
    && usermod -aG sudo dev \
    && mkdir -p /home/dev/.vnc \
    && chown -R dev:dev /home/dev

# ---------- Startup scripts ----------
COPY start-vnc.sh /start-vnc.sh
COPY start.sh /start.sh
RUN chmod +x /start-vnc.sh /start.sh

# Memory/CPU limits are not set inside the image; the gateway decides them via --memory etc. at provision time
EXPOSE 5900 6901
CMD ["/start.sh"]
