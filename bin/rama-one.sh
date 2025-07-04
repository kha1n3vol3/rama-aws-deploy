#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# rama-one.sh
# -----------------------------------------------------------------------------
# Opinionated, single-command installer for a **single-node** Rama cluster on
# Ubuntu 20.04/22.04.  The script performs the following steps:
#   1. Installs required system packages (curl, wget, unzip, openjdk, etc.).
#   2. Downloads and unpacks ZooKeeper 3.9.3 under /opt/zookeeper.
#   3. Downloads Rama server zip (1.x) and unpacks to /opt/rama.
#   4. Drops systemd unit files for ZooKeeper, Rama Conductor and Supervisor.
#   5. Creates minimal rama.yaml pointing to the local ZooKeeper.
#   6. Enables + starts all services.
#
# This script intentionally avoids Terraform/Cloud-init and can be executed
# manually or by a configuration-management tool.  Run as **root** or with sudo.
# -----------------------------------------------------------------------------

set -euo pipefail

### Configuration -------------------------------------------------------------

RAMA_VERSION="1.1.0"                                       # update as needed
RAMA_URL="https://redplanetlabs.s3.us-west-2.amazonaws.com/rama/rama-${RAMA_VERSION}.zip"

ZK_URL="https://dlcdn.apache.org/zookeeper/current/apache-zookeeper-3.9.3.tar.gz"

INSTALL_DIR="/opt"                                         # base directory
RAMA_DIR="${INSTALL_DIR}/rama"
ZK_DIR="${INSTALL_DIR}/zookeeper"

SYSTEMD_DIR="/etc/systemd/system"

USER_NAME="$(logname 2>/dev/null || echo ${SUDO_USER:-ubuntu})"

### Helper -------------------------------------------------------------------

log() {
  echo "[ $(date -u +%H:%M:%S) ] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "Installing $1"; apt-get install -y "$2"; }
}

### 1. Ensure prerequisites ---------------------------------------------------

log "Updating apt cache & installing prerequisites …"
apt-get update -y

# Map of binary → apt package name
need_cmd curl curl
need_cmd wget wget
need_cmd unzip unzip
need_cmd java openjdk-11-jre-headless
need_cmd tar tar

### 2. ZooKeeper --------------------------------------------------------------

if [[ ! -d "${ZK_DIR}" ]]; then
  log "Downloading ZooKeeper …"
  wget -qO /tmp/zookeeper.tgz "${ZK_URL}"
  log "Extracting ZooKeeper to ${ZK_DIR} …"
  mkdir -p "${ZK_DIR}"
  tar -xzf /tmp/zookeeper.tgz --strip-components 1 -C "${ZK_DIR}"
fi

# Create data/log directories expected by default config
mkdir -p "${ZK_DIR}/data" "${ZK_DIR}/logs"

# Minimal zoo.cfg
cat >"${ZK_DIR}/conf/zoo.cfg" <<EOF
tickTime=2000
dataDir=${ZK_DIR}/data
dataLogDir=${ZK_DIR}/logs
clientPort=2181
EOF

# Systemd unit
cat >"${SYSTEMD_DIR}/zookeeper.service" <<EOF
[Unit]
Description=Apache ZooKeeper
After=network.target

[Service]
Type=simple
WorkingDirectory=${ZK_DIR}
ExecStart=${ZK_DIR}/bin/zkServer.sh start-foreground
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

### 3. Rama -------------------------------------------------------------------

if [[ ! -d "${RAMA_DIR}" ]]; then
  log "Downloading Rama ${RAMA_VERSION} …"
  wget -qO /tmp/rama.zip "${RAMA_URL}"
  log "Extracting Rama to ${RAMA_DIR} …"
  mkdir -p "${RAMA_DIR}"
  unzip -q /tmp/rama.zip -d "${RAMA_DIR}"
fi

# Minimal rama.yaml placed in install dir
cat >"${RAMA_DIR}/rama.yaml" <<EOF
zookeeper.servers:
  - "127.0.0.1"

conductor.host: "127.0.0.1"
supervisor.host: "127.0.0.1"
EOF

# Systemd template generator
generate_unit() {
  local svc=$1
  local desc=$2
  cat >"${SYSTEMD_DIR}/${svc}.service" <<EOF
[Unit]
Description=Rama ${desc}
After=network.target zookeeper.service

[Service]
Type=simple
WorkingDirectory=${RAMA_DIR}
ExecStart=${RAMA_DIR}/rama ${svc}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

generate_unit conductor "Conductor"
generate_unit supervisor "Supervisor"

### 4. Enable & start services ------------------------------------------------

log "Reloading systemd daemon …"
systemctl daemon-reload

for svc in zookeeper conductor supervisor; do
  log "Enabling and starting $svc.service …"
  systemctl enable --now "$svc.service"
done

log "All components installed.  Verify with: systemctl status zookeeper conductor supervisor"

