#!/usr/bin/env bash

# Wait for disk setup and unpack script to be ready (signaled by setup-disks.sh and cloud-config)
echo "Waiting for disks and unpack script to be available..."
while [ ! -f "/tmp/disks_complete.signal" ] || [ ! -f "/data/rama/unpack-rama.sh" ]; do
  sleep 1
done
echo "Disks complete and unpack-rama.sh detected, continuing..."