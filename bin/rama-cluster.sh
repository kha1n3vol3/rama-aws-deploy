#!/usr/bin/env bash
set -euo pipefail

usage () {
  echo "Usage: rama-cluster.sh <deploy|destroy|plan> [--singleNode] <cluster-name> [optional terraform apply args]"
  exit 2
}

[[ $# -ge 2 ]] || usage

DIR=$(realpath "$(dirname "$0")")
CWD=$(pwd)

# -----------------------------------------------------------------------------
# Terraform logging
# -----------------------------------------------------------------------------
# To aid in debugging, we optionally enable Terraform logging and write the logs
# to a predictable location on the bastion / jump server.  A user can override
# the defaults by exporting TF_LOG or TF_LOG_PATH before invoking this script.
#
#  * TF_LOG – verbosity (TRACE, DEBUG, INFO, WARN, ERROR).  Defaults to INFO.
#  * TF_LOG_PATH – destination file.  Defaults to a per-cluster file under
#    "$HOME/.rama/terraform-logs/".
#
# These variables are only set if they have not already been provided so that we
# never clobber a caller's preferences.

DEFAULT_TF_LOG_LEVEL="INFO"

# Create a default log directory and file only if TF_LOG_PATH isn't set.  We do
# this work early so that all Terraform invocations in this script inherit the
# environment variables.
ensure_terraform_logging() {
  if [[ -z "${TF_LOG_PATH:-}" ]]; then
    local log_dir="$HOME/.rama/terraform-logs"
    mkdir -p "$log_dir"

    # Example: terraform-deploy-mycluster-20250101T120000.log
    local timestamp="$(date +%Y%m%dT%H%M%S)"
    TF_LOG_PATH="${log_dir}/terraform-${OP_NAME}-${CLUSTER_NAME:-unknown}-${timestamp}.log"
    export TF_LOG_PATH
  fi

  # Respect existing TF_LOG, otherwise set a sensible default.
  if [[ -z "${TF_LOG:-}" ]]; then
    TF_LOG="$DEFAULT_TF_LOG_LEVEL"
    export TF_LOG
  fi
}

# We'll call ensure_terraform_logging once we know the cluster name (after we
# parse positional arguments below).

OP_NAME=$1
shift # remove first arg, OP_NAME

SINGLE_NODE=false

if [[ "$1" == "--singleNode" ]]; then
	SINGLE_NODE=true
	shift
fi

	
[[ $# -ge 1 ]] || usage

CLUSTER_NAME=$1
shift

# Now that we have the cluster name, configure Terraform logging to include it.
ensure_terraform_logging


WORKSPACE_NAME=${CLUSTER_NAME}

ROOT_DIR="$(realpath "${DIR}/..")"
if [[ "$SINGLE_NODE" = true ]]; then
   TF_ROOT_DIR="${ROOT_DIR}"/rama-cluster/single
else
   TF_ROOT_DIR="${ROOT_DIR}"/rama-cluster/multi
fi

HOME_CLUSTER_DIR="${HOME}/.rama/${CLUSTER_NAME}"

if [[ $CLUSTER_NAME == "default" ]]; then
    echo "Cluster name may not be \"default\""
    exit 2
fi

echo "Performing ${OP_NAME} ${CLUSTER_NAME}"

find_rama_tfvars() {
  local dir="$CWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/rama.tfvars" ]; then
      realpath "$dir/rama.tfvars"
      return
    fi
    dir=$(dirname "$dir")
  done
  echo "[ERROR] Could not find rama.tfvars file" >&2
  exit 1
}

get_tfvars_value() {
  local file="$1"
  local var="$2"
  local line
  line=$(grep -E "^[[:space:]]*${var}[[:space:]]*=" "$file" || true)
  echo "${line#*=}" | xargs
}

prepare_workspace() {
  terraform init
  terraform workspace select "$WORKSPACE_NAME" &>/dev/null || terraform workspace new "$WORKSPACE_NAME"
}

run_destroy() {
  local tfvars
  tfvars=$(find_rama_tfvars)
  cd "$TF_ROOT_DIR"
  terraform workspace select "$WORKSPACE_NAME"
  terraform destroy -auto-approve \
    -parallelism=50 \
    -var-file "$tfvars" \
    -var-file "$HOME/.rama/auth.tfvars" \
    -var="cluster_name=$CLUSTER_NAME"
  terraform workspace select default
  terraform workspace delete "$WORKSPACE_NAME"

  rm -f "$HOME/.rama/rama-$CLUSTER_NAME"
  rm -rf "$HOME/.rama/$CLUSTER_NAME"
  echo "Rama cluster destroyed."
  return 0
}

confirm_destroy () {
  echo "WARNING: you are attempting to destroy a cluster. Are you sure you want to do this?"
  read -p "Enter the name of the cluster to confirm destroy: " cluster_name
  if [ "$cluster_name" = "$CLUSTER_NAME" ]; then
    echo "Destroying $cluster_name..."
    run_destroy
  else
    echo "Cluster name was not entered, preserving cluster."
  fi
}


# extra args to pass through to `terraform apply`
tf_apply_args=("$@")

# ensure we have AWS EC2 keypair info
if [ ! -f "$HOME/.rama/auth.tfvars" ]; then
  echo "[ERROR] Missing ~/.rama/auth.tfvars; please create it with 'key_name = \"<EC2 keypair name>\"'" >&2
  exit 1
fi

run_deploy() {
  local tfvars rama_source_path
  tfvars=$(find_rama_tfvars)
  cd "$TF_ROOT_DIR"
  prepare_workspace
  terraform apply \
    -auto-approve \
    -parallelism=30 \
    -var-file "$tfvars" \
    -var-file "$HOME/.rama/auth.tfvars" \
    -var="cluster_name=$CLUSTER_NAME" \
    "${tf_apply_args[@]:-}"

  rm -rf "$HOME_CLUSTER_DIR"
  mkdir -p "$HOME_CLUSTER_DIR"

  terraform output -json > "$HOME_CLUSTER_DIR/outputs.json"

  rama_source_path=$(get_tfvars_value "$tfvars" rama_source_path)
  cp "$rama_source_path" "$HOME_CLUSTER_DIR/rama.zip"
  cp "$tfvars" "$HOME_CLUSTER_DIR"

  (
    cd "$HOME_CLUSTER_DIR"
    unzip rama.zip &>/dev/null
    rm rama.yaml
    rm rama.zip
  )

  cp "/tmp/deployment.yaml" "$HOME/.rama/$CLUSTER_NAME/rama.yaml"
  ln -fs "$HOME/.rama/$CLUSTER_NAME/rama" "$HOME/.rama/rama-$CLUSTER_NAME"
  echo "Rama cluster deployed, have fun."
  return 0
}

run_plan() {
  local tfvars
  tfvars=$(find_rama_tfvars)
  cd "$TF_ROOT_DIR"
  prepare_workspace
  terraform plan \
    -var-file "$tfvars" \
    -var-file "$HOME/.rama/auth.tfvars" \
    -var="cluster_name=$CLUSTER_NAME" \
    "${tf_apply_args[@]:-}"
}

case "${OP_NAME}" in
  deploy)
    run_deploy
    ;;
  destroy)
    confirm_destroy
    ;;
  plan)
    run_plan
    ;;
  *)
    usage
    ;;
esac
