#!/usr/bin/env bash

# logging removed
set -euxo pipefail

mv /run/rama/rama.yaml /data/rama/rama.yaml

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

cat <<EOF >> /data/rama/rama.yaml

supervisor.host: "$PRIVATE_IP"
EOF

systemctl enable supervisor.service
systemctl start supervisor.service

# Verify supervisor becomes active
for i in {1..15}; do
  if systemctl is-active --quiet supervisor.service; then
    echo "Supervisor service is active."
    exit 0
  fi
  sleep 4
done
echo "ERROR: Supervisor service failed to start." >&2
journalctl -u supervisor.service --no-pager
exit 1

