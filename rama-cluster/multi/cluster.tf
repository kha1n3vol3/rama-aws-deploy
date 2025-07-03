###
# variables & configuration
###

## Required vars

variable "region" { type = string }

variable "cluster_name" { type = string } # from rama-cluster.sh
variable "key_name" { type = string }     # from ~/.rama/auth.tfvars

# From rama.tfvars
variable "username" { type = string }
variable "vpc_security_group_ids" { type = list(string) }


variable "rama_source_path" {
  type = string

  validation {
    condition     = can(regex("^https?://", var.rama_source_path))
    error_message = "rama_source_path must be an absolute URL (e.g. https://...)"
  }
}
variable "license_source_path" {
  type    = string
  default = ""
}
variable "zookeeper_url" { type = string }

variable "conductor_ami_id" { type = string }
variable "supervisor_ami_id" { type = string }
variable "zookeeper_ami_id" { type = string }

variable "zookeeper_instance_type" { type = string }
variable "conductor_instance_type" { type = string }
variable "supervisor_instance_type" { type = string }

variable "supervisor_num_nodes" { type = number }

## Optional vars

variable "zookeeper_num_nodes" {
  type    = number
  default = 1
}

variable "supervisor_volume_size_gb" {
  type    = number
  default = 100
}

variable "use_private_ip" {
  type    = bool
  default = false
}

variable "private_ssh_key" {
  type    = string
  default = null
}

variable "private_key_file" {
  type        = string
  default     = ""
  description = "(legacy) alias for private_ssh_key; set private_ssh_key instead"
}

provider "aws" {
  region      = var.region
  max_retries = 25
}


locals {
  zk_public_ips  = aws_instance.zookeeper[*].public_ip
  zk_private_ips = aws_instance.zookeeper[*].private_ip

  conductor_public_ip  = aws_instance.conductor.public_ip
  conductor_private_ip = aws_instance.conductor.private_ip

  home_dir    = "/home/${var.username}"
  systemd_dir = "/etc/systemd/system"

  # networking
  vpc_security_group_ids = var.vpc_security_group_ids

  # merge legacy private_key_file into private_ssh_key
  private_ssh_key_final = var.private_ssh_key != null ? var.private_ssh_key : (var.private_key_file != "" ? var.private_key_file : null)
  #vpc_security_group_ids = [module.vpc.default_security_group_id]
  #vpc_id                 = module.vpc.vpc_id
  #subnet_id              = module.vpc.public_subnets[0]
}

###
# VPC
###

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

###
# Create EC2 instances
#
# These resources are defined to have no dependencies on other resouces. This
# way the EC2 instances can be created in parallel, which saves time.
###

resource "aws_instance" "zookeeper" {
  ami           = var.zookeeper_ami_id
  instance_type = var.zookeeper_instance_type
  # subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name
  count                  = var.zookeeper_num_nodes

  tags = {
    Name = "${terraform.workspace}-cluster-zookeeper"
  }

  root_block_device {
    volume_size = 100
  }

  # Wait for SSH availability before copying files
  provisioner "remote-exec" {
    inline = ["echo Waiting for SSH to become available"]
  }

  provisioner "file" {
    destination = "${local.home_dir}/zookeeper.service"
    content = templatefile("../common/zookeeper/zookeeper.service", {
      username = var.username
    })
  }

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? self.private_ip : self.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }
}

# Conductor

data "cloudinit_config" "conductor_config" {
  part {
    content_type = "text/x-shellscript"
    content = templatefile("../common/setup-disks.sh", {
      username = var.username
    })
  }

  part {
    content_type = "cloud-config"
    content = templatefile("conductor/cloud-config.yaml", {
      username = var.username,
      # rama.yaml
      rama_yaml_contents = templatefile("conductor/rama.yaml", {
        zk_public_ips  = local.zk_public_ips
        zk_private_ips = local.zk_private_ips
      }),
      # conductor.service
      service_name             = "conductor",
      service_file_destination = "${local.systemd_dir}/conductor.service",
      service_file_contents = templatefile("../common/systemd-service-template.service", {
        description = "Rama Conductor",
        command     = "conductor"
      }),
      # rama.license
      # If a license file path was provided, read its contents; otherwise, leave empty
      license_file_contents = var.license_source_path != "" ? file(var.license_source_path) : "",
      # unpack_rama_contents removed (handled in remote-exec)
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("conductor/start.sh", {
      username = var.username
    })
  }
}

resource "aws_instance" "conductor" {
  ami           = var.conductor_ami_id
  instance_type = var.conductor_instance_type
  #subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data = data.cloudinit_config.conductor_config.rendered

  tags = {
    Name = "${terraform.workspace}-cluster-conductor"
  }

  root_block_device {
    volume_size = 100
  }

  provisioner "remote-exec" {
    # ensure disk provisioning has completed (cloud-init)
    script = "${path.module}/../common/wait-for-signal.sh"
  }

  provisioner "remote-exec" {
    # ensure SSH is up before uploading rama.zip
    inline = ["echo Waiting for SSH to become available"]
  }

  # Download Rama server zip directly from configured URL
  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'curl -sSLf ${var.rama_source_path} -o /home/${var.username}/rama.zip'"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOR
        bash -euxo pipefail -c "\
        while [ ! -d /data/rama ]; do sleep 2; done;\n\
        sudo mkdir -p /data/rama;\n\
        sudo mv -f /home/${var.username}/rama.zip /data/rama/;\n\
        cd /data/rama;\n\
        sudo unzip -n rama.zip;\n\
        local_dir=$$(grep \"local.dir\" rama.yaml | cut -d':' -f2 | xargs);\n\
        if [ -n \"$$local_dir\" ]; then\n\
          sudo mkdir -p \"$$local_dir/conductor/jars\";\n\
          sudo cp -f rama.zip \"$$local_dir/conductor/jars\";\n\
        fi"
      EOR
    ]
  }

  # health check moved to after start.sh execution to avoid race condition.

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? self.private_ip : self.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }
}

# After the instance bootstraps with cloud-init start.sh, verify that the
# conductor service is active. This check is separated from the instance
# resource so that it runs after the initial provisioning and avoids race
# conditions with systemd startup.
resource "null_resource" "conductor_healthcheck" {
  depends_on = [aws_instance.conductor]

  triggers = {
    instance_id = aws_instance.conductor.id
  }

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? aws_instance.conductor.private_ip : aws_instance.conductor.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }

  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'for i in {1..15}; do if systemctl is-active --quiet conductor.service; then echo \"conductor is running\"; exit 0; fi; sleep 4; done; echo \"conductor failed to start\"; journalctl -u conductor.service --no-pager; exit 1'"
    ]
  }
}

# Supervisors

data "cloudinit_config" "supervisor_config" {
  part {
    content_type = "text/x-shellscript"
    content = templatefile("../common/setup-disks.sh", {
      username = var.username
    })
  }


  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content = templatefile("./cloud-config.yaml", {
      rama_yaml_contents = templatefile("./supervisor/rama.yaml", {
        zk_public_ips        = local.zk_public_ips
        zk_private_ips       = local.zk_private_ips
        conductor_public_ip  = aws_instance.conductor.public_ip
        conductor_private_ip = aws_instance.conductor.private_ip
      })
      service_file_destination = "${local.systemd_dir}/supervisor.service",
      service_file_contents = templatefile("../common/systemd-service-template.service", {
        description = "Rama Supervisor"
        command     = "supervisor"
      })
      service_name = "supervisor"
      username     = var.username
    })
  }

  part {
    # Supervisor's own IP can't be templated into rama.yaml above, so
    # we need to run a script to look it up from the instance metadata
    content_type = "text/x-shellscript"
    content = templatefile("./supervisor/start.sh", {
      username = var.username
    })
  }
}

resource "aws_instance" "supervisor" {
  ami           = var.supervisor_ami_id
  count         = var.supervisor_num_nodes
  instance_type = var.supervisor_instance_type
  #subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data = data.cloudinit_config.supervisor_config.rendered

  tags = {
    Name = "${terraform.workspace}-cluster-supervisor"
  }

  root_block_device {
    volume_size = var.supervisor_volume_size_gb
  }

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? self.private_ip : self.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }

  # Wait for cloud-init to complete before downloading Rama
  provisioner "remote-exec" {
    script = "${path.module}/../common/wait-for-signal.sh"
  }

  # Download and unpack Rama, fail on error
  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'curl -sSLf ${var.rama_source_path} -o /home/${var.username}/rama.zip'"
    ]
  }
  provisioner "remote-exec" {
    inline = [
      <<-EOR
        bash -euxo pipefail -c "\
        while [ ! -d /data/rama ]; do sleep 2; done;\n\
        sudo mkdir -p /data/rama;\n\
        sudo mv -f /home/${var.username}/rama.zip /data/rama/;\n\
        cd /data/rama;\n\
        sudo unzip -n rama.zip;\n\
        local_dir=$$(grep \"local.dir\" rama.yaml | cut -d':' -f2 | xargs);\n\
        if [ -n \"$$local_dir\" ]; then\n\
          sudo mkdir -p \"$$local_dir/conductor/jars\";\n\
          sudo cp -f rama.zip \"$$local_dir/conductor/jars\";\n\
        fi"
      EOR
    ]
  }

  # Verify supervisor service is running
  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'systemctl is-active --quiet supervisor.service || (echo \"Supervisor service failed to start\"; journalctl -u supervisor.service --no-pager; exit 1)'"
    ]
  }
}

###
# Configure the EC2 instances created above
###

resource "null_resource" "zookeeper" {
  count = var.zookeeper_num_nodes

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? aws_instance.zookeeper[count.index].private_ip : aws_instance.zookeeper[count.index].public_ip
    private_key = var.private_ssh_key != null ? file(var.private_ssh_key) : null
  }

  triggers = {
    zookeeper_ids = "${join(",", aws_instance.zookeeper.*.id)}"
  }

  # Ensure SSH is ready before provisioning conductor
  provisioner "remote-exec" {
    inline = ["echo Waiting for SSH to become available"]
  }

  # Ensure SSH is ready before provisioning supervisor
  provisioner "remote-exec" {
    inline = ["echo Waiting for SSH to become available"]
  }

  provisioner "file" {
    source      = "../common/zookeeper/setup.sh"
    destination = "${local.home_dir}/setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.home_dir}/setup.sh",
      "${local.home_dir}/setup.sh ${var.zookeeper_url}"
    ]
  }

  provisioner "file" {
    content = templatefile("../common/zookeeper/zoo.cfg", {
      num_servers    = var.zookeeper_num_nodes,
      zk_private_ips = local.zk_private_ips,
      server_index   = count.index
      username       = var.username
    })
    destination = "${local.home_dir}/zookeeper/conf/zoo.cfg"
  }

  provisioner "file" {
    content = templatefile("../common/zookeeper/myid", {
      zkid = count.index + 1
    })
    destination = "${local.home_dir}/zookeeper/data/myid"
  }

  provisioner "remote-exec" {
    script = "zookeeper/start.sh"
  }
}

###
# Setup local to allow `rama-my-cluster` commands
# TODO find some way to include all ZK ip addresses :(
###
resource "null_resource" "local" {
  # Render to local file on machine
  # https://github.com/hashicorp/terraform/issues/8090#issuecomment-291823613
  provisioner "local-exec" {
    command = format(
      "cat <<\"EOF\" > \"%s\"\n%s\nEOF",
      "/tmp/deployment.yaml",
      templatefile("../common/local.yaml", {
        zk_public_ip         = aws_instance.zookeeper[0].public_ip
        zk_private_ip        = aws_instance.zookeeper[0].private_ip
        conductor_public_ip  = local.conductor_public_ip
        conductor_private_ip = local.conductor_private_ip
      })
    )
  }
}

###
# Output useful info
###
output "zookeeper_ips" {
  value = var.use_private_ip ? local.zk_private_ips : local.zk_public_ips
}

output "conductor_ip" {
  value = var.use_private_ip ? local.conductor_private_ip : local.conductor_public_ip
}

output "supervisor_ids" {
  value = var.use_private_ip ? aws_instance.supervisor.*.private_ip : aws_instance.supervisor.*.public_ip
}

output "conductor_ui" {
  value = "http://${var.use_private_ip ? local.conductor_private_ip : local.conductor_public_ip}:8888"
}

output "ec2_console" {
  value = "https://console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:tag:Name=${var.cluster_name}-cluster-supervisor,${var.cluster_name}-cluster-conductor,${var.cluster_name}-cluster-zookeeper;instanceState=running;sort=desc:tag:Name"
}
