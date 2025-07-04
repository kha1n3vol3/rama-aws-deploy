
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

variable "ami_id" { type = string }

variable "instance_type" { type = string }

variable "volume_size_gb" {
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
  home_dir               = "/home/${var.username}"
  systemd_dir            = "/etc/systemd/system"
  vpc_security_group_ids = var.vpc_security_group_ids
  private_ssh_key_final = var.private_ssh_key != null ? var.private_ssh_key : (var.private_key_file != "" ? var.private_key_file : null)
}

###
# VPC
###

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

###
# Create EC2 instance
###

resource "aws_instance" "rama" {
  ami           = var.ami_id
  instance_type = var.instance_type
  # subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data = data.cloudinit_config.rama_config.rendered

  tags = {
    Name = "${terraform.workspace}-rama"
  }

  root_block_device {
    volume_size = var.volume_size_gb
  }

  # Ensure SSH is available before doing any file transfers
  provisioner "remote-exec" {
    inline = ["echo Waiting for SSH to be available"]
  }

  provisioner "remote-exec" {
    # ensure disk provisioning has completed (cloud-init)
    script = "${path.module}/../common/wait-for-signal.sh"
  }

  # Zookeeper setup
  provisioner "file" {
    destination = "${local.home_dir}/zookeeper.service"
    content = templatefile("../common/zookeeper/zookeeper.service", {
      username = var.username
    })
  }

  # Download Rama zip to the home directory
  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'curl -sSLf ${var.rama_source_path} -o /home/${var.username}/rama.zip |& tee -a /var/log/rama-provision.log'"
    ]
  }
  # Move Rama zip to /data/rama and unpack (idempotent)
  provisioner "remote-exec" {
    inline = [
      <<-EOR
        bash -euxo pipefail -c "\
        # Wait until the Rama data directory is ready (cloud-init may create & mount it)\n\
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

  # NOTE: service health checks moved to null_resource after the services
  # are started by start.sh to avoid race conditions during provisioning.

  connection {
    type        = "ssh"
    user        = var.username
    host        = var.use_private_ip ? self.private_ip : self.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }
}

data "cloudinit_config" "rama_config" {
  part {
	content_type = "text/x-shellscript"
	content = templatefile("../common/setup-disks.sh", {
	  username = var.username
	})
  }

  part {
	# Conductor setup
	content_type = "text/cloud-config"
	content = templatefile("./cloud-config.yaml", {
	  username = var.username,

	  # conductor.service
	  conductor_service_name = "conductor",
	  conductor_service_file_destination = "${local.systemd_dir}/conductor.service",
	  conductor_service_file_contents = templatefile("../common/systemd-service-template.service", {
		description = "Rama Conductor",
		command     = "conductor"
	  })
          # rama.license (optional)
          # If a license file path was provided, read its contents; otherwise, leave empty
          license_file_contents = var.license_source_path != "" ? file(var.license_source_path) : "",
	  # unpack_rama_contents removed (unpack handled in remote-exec)

	  supervisor_service_file_destination = "${local.systemd_dir}/supervisor.service",
	  supervisor_service_file_contents = templatefile("../common/systemd-service-template.service", {
		description = "Rama Supervisor"
		command     = "supervisor"
	  })
	  service_name = "supervisor"
	})
  }
}

resource "null_resource" "rama" {
  connection {
	type        = "ssh"
	user        = var.username
	host        = var.use_private_ip ? aws_instance.rama.private_ip : aws_instance.rama.public_ip
    private_key = local.private_ssh_key_final != null ? file(local.private_ssh_key_final) : null
  }

  triggers = {
	zookeeper_id = aws_instance.rama.id
  }

  provisioner "file" {
	source = "../common/zookeeper/setup.sh"
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
	  num_servers    = 1,
	  zk_private_ips = [aws_instance.rama.private_ip],
	  server_index   = 0
	  username       = var.username
	})
	destination = "${local.home_dir}/zookeeper/conf/zoo.cfg"
  }

  provisioner "file" {
	content = templatefile("../common/zookeeper/myid", {
	  zkid = 1
	})
	destination = "${local.home_dir}/zookeeper/data/myid"
  }

  provisioner "file" {
	content = templatefile("./rama.yaml", {
	  zk_private_ip = aws_instance.rama.private_ip
	  conductor_private_ip = aws_instance.rama.private_ip
	  supervisor_private_ip = aws_instance.rama.private_ip
	})
	destination = "/tmp/rama.yaml"
  }

  provisioner "remote-exec" {
    script = "./start.sh"
  }

  # Verify conductor and supervisor services are running now that start.sh
  # has had a chance to enable and start them.
  provisioner "remote-exec" {
    inline = [
      "bash -euxo pipefail -c 'for svc in conductor supervisor; do for i in {1..10}; do if systemctl is-active --quiet ${svc}.service; then echo \"${svc} is running\"; break; fi; sleep 3; done; systemctl is-active --quiet ${svc}.service || (echo \"${svc} service failed to start\"; journalctl -u ${svc}.service --no-pager; exit 1); done'"
    ]
  }
}

###
# Setup local to allow `rama-my-cluster` commands
###
resource "null_resource" "local" {
  # Render to local file on machine
  # https://github.com/hashicorp/terraform/issues/8090#issuecomment-291823613
  provisioner "local-exec" {
    command = format(
      "cat <<\"EOF\" > \"%s\"\n%s\nEOF",
      "/tmp/deployment.yaml",
      templatefile("../common/local.yaml", {
        zk_public_ip         = aws_instance.rama.public_ip
        zk_private_ip        = aws_instance.rama.private_ip
        conductor_public_ip  = aws_instance.rama.public_ip
        conductor_private_ip = aws_instance.rama.private_ip
      })
      )
  }
}

###
# Output useful info
###
output "rama_ip" {
  value = var.use_private_ip ? aws_instance.rama.private_ip : aws_instance.rama.public_ip
}

output "conductor_ui" {
  value = "http://${var.use_private_ip ? aws_instance.rama.private_ip : aws_instance.rama.public_ip}:8888"
}

output "ec2_console" {
  value = "https://console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:tag:Name=${var.cluster_name}-cluster-supervisor,${var.cluster_name}-cluster-conductor,${var.cluster_name}-cluster-zookeeper;instanceState=running;sort=desc:tag:Name"
}
