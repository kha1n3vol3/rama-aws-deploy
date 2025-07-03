#!/bin/bash

set -eo pipefail

# -----------------------------------------------------------------------------
# Terraform logging helpers (same logic as bin/rama-cluster.sh but simplified)
# -----------------------------------------------------------------------------

DEFAULT_TF_LOG_LEVEL="INFO"

ensure_terraform_logging() {
  if [[ -z "${TF_LOG_PATH:-}" ]]; then
    local log_dir="$HOME/.rama/terraform-logs"
    mkdir -p "$log_dir"

    local timestamp="$(date +%Y%m%dT%H%M%S)"
    TF_LOG_PATH="${log_dir}/terraform-infra-${APPLY_ROLE}-${timestamp}.log"
    export TF_LOG_PATH
  fi

  if [[ -z "${TF_LOG:-}" ]]; then
    TF_LOG="$DEFAULT_TF_LOG_LEVEL"
    export TF_LOG
  fi
}

usage () {
  echo "Usage: rama-infra.sh <admin|user>"
  exit 2
}

[[ $# -eq 1 ]] || usage

APPLY_ROLE=$1
ROOT_DIR=$(pwd)
TF_DIR="${ROOT_DIR}"/rama-infra/"${APPLY_ROLE}"

# Enable Terraform logging
ensure_terraform_logging

pushd "${TF_DIR}" || usage

WORKSPACE_NAME=infra-"${APPLY_ROLE}"

terraform workspace select "${WORKSPACE_NAME}" &> /dev/null || terraform workspace new "${WORKSPACE_NAME}"
terraform init
terraform apply

popd
