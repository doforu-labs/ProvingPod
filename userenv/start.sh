#!/bin/bash
set -e
echo "[start] proving-pod starting..."
/start-vnc.sh
echo "[start] VNC/noVNC ready, keeping container in foreground"
exec tail -f /dev/null
