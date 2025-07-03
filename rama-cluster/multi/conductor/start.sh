#!/usr/bin/env bash

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
