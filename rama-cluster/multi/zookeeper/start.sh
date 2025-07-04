#!/usr/bin/env bash

# logging removed
set -euxo pipefail

# Update package metadata
if command -v yum >/dev/null 2>&1; then
  sudo yum -y update
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf -y update
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get -y update
fi

echo "Starting zookeeper..."

sudo cp zookeeper.service /etc/systemd/system
sudo systemctl start zookeeper.service
sudo systemctl enable zookeeper.service

# Basic health check to ensure ZooKeeper is running; exit non-zero if it is not
for i in {1..10}; do
  if ./zookeeper/bin/zkServer.sh status > /dev/null 2>&1; then
echo "ZooKeeper is running!"
    exit 0
  fi
  echo "ZooKeeper not ready yet..."
  sleep 3
done
echo "ERROR: ZooKeeper failed to start." >&2
exit 1
