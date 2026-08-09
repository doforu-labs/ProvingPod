#!/bin/bash
# ProvingPod user environment: start TigerVNC(5900) + noVNC(6901), all output to stdout for debugging
set -e

VNC_PASS="${VNC_PASS:-vncpass}"
RUN_USER="${RUN_USER:-dev}"
GEOMETRY="${VNC_GEOMETRY:-1280x800}"
export DISPLAY=:0

echo "[start-vnc] cleaning up old instances..."
pkill -f Xvnc 2>/dev/null || true
pkill -f websockify 2>/dev/null || true
pkill -f novnc_proxy 2>/dev/null || true
sleep 1

echo "[start-vnc] preparing VNC password (user=${RUN_USER}, pass=${VNC_PASS})"
mkdir -p "/home/${RUN_USER}/.vnc"
if [ "$(id -u)" = "0" ]; then
  printf '%s\n%s\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd "/home/${RUN_USER}/.vnc/passwd" >/dev/null 2>&1 || true
  chown -R "${RUN_USER}:${RUN_USER}" "/home/${RUN_USER}/.vnc"
else
  printf '%s\n%s\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd "/home/${RUN_USER}/.vnc/passwd" >/dev/null 2>&1 || true
fi

echo "[start-vnc] starting TigerVNC :0 (port 5900) as ${RUN_USER}"
su - "${RUN_USER}" -c "vncserver :0 -localhost no -geometry ${GEOMETRY} -depth 24" >/tmp/vncserver.log 2>&1 || {
  echo "[start-vnc] vncserver failed to start:"; cat /tmp/vncserver.log; exit 1; }
sleep 2
if ss -ltn | grep -q ':5900 '; then
  echo "[start-vnc] VNC listening on 5900"
else
  echo "[start-vnc] WARNING: 5900 not listening, vncserver.log:"; cat /tmp/vncserver.log
fi

echo "[start-vnc] starting noVNC (websockify -> localhost:5900, listen 6901)"
if command -v novnc_proxy >/dev/null 2>&1; then
  nohup novnc_proxy --vnc localhost:5900 --listen 6901 >/tmp/novnc.log 2>&1 &
else
  nohup websockify --web /usr/share/novnc 6901 localhost:5900 >/tmp/novnc.log 2>&1 &
fi
sleep 2
if ss -ltn | grep -q ':6901 '; then
  echo "[start-vnc] noVNC listening on 6901, access: http://<host>:6901/vnc.html"
else
  echo "[start-vnc] WARNING: 6901 not listening, novnc.log:"; cat /tmp/novnc.log
fi

echo "[start-vnc] done"
