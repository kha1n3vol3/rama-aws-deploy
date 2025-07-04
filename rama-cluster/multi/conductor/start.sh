#!/usr/bin/env bash

# Log bootstrap actions for troubleshooting
LOGDIR="$HOME/rama-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/conductor-bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1

set -euxo pipefail

echo "$(date -u) – Conductor bootstrap starting"

mv /run/rama/rama.yaml /data/rama/rama.yaml

cd /data/rama

systemctl enable conductor.service
systemctl start conductor.service

# ensure service is up
for i in {1..15}; do
  if systemctl is-active --quiet conductor.service; then
echo "Conductor service is active."
    exit 0
  fi
  sleep 4
done
echo "ERROR: Conductor service failed to start." >&2
journalctl -u conductor.service --no-pager
exit 1

echo "$(date -u) – Conductor bootstrap complete."
