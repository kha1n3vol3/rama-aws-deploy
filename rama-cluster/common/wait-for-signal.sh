#!/usr/bin/env bash

# Wait for disk setup to complete (signaled by setup-disks.sh)
echo "Waiting for disks to complete..."
while [ ! -f "/tmp/disks_complete.signal" ]; do
  sleep 1
done
echo "Disks complete signal file detected, continuing..."