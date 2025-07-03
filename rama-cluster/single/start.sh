#!/usr/bin/env bash


sudo yum update -y

echo "Starting zookeeper..."

sudo cp zookeeper.service /etc/systemd/system
sudo systemctl start zookeeper.service
sudo systemctl enable zookeeper.service

echo "Starting ZooKeeper status check loop..."

while true; do
    # Run the ZooKeeper status command and check its exit code
    if ./zookeeper/bin/zkServer.sh status > /dev/null 2>&1; then
        echo "ZooKeeper is running!"
        break
    else
        echo "ZooKeeper is not ready yet. Retrying..."
    fi
    sleep 1
done


# -f and sudo because we must override the rama.yaml that comes from extracting rama.zip
sudo mv -f /tmp/rama.yaml /data/rama/rama.yaml

cd /data/rama

sudo systemctl enable conductor.service
sudo systemctl start conductor.service

sudo systemctl enable supervisor.service
sudo systemctl start supervisor.service

# Wait for services to become active to ensure reliability for downstream
# Terraform provisioners.
for svc in conductor supervisor; do
  echo "Waiting for $svc service to become active..."
  for i in {1..10}; do
    if systemctl is-active --quiet "${svc}.service"; then
      echo "$svc service is active."
      break
    fi
    sleep 3
  done
  # Fail script (and therefore Terraform) if service failed to start
  if ! systemctl is-active --quiet "${svc}.service"; then
    echo "ERROR: $svc service failed to start."
    journalctl -u "${svc}.service" --no-pager
    exit 1
  fi
done
