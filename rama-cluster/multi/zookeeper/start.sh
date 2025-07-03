##!/bin/bash

sudo yum update -y

echo "Starting zookeeper..." >> setup.log

sudo cp zookeeper.service /etc/systemd/system &>> setup.log
sudo systemctl start zookeeper.service &>> setup.log
sudo systemctl enable zookeeper.service &>> setup.log

# If Zookeeper successfully starts, we don't need this log anymore
rm setup.log

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
