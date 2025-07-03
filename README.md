# rama-aws-deploy

This repository provides Terraform configurations and helper scripts to deploy a Rama cluster (single-node for testing or multi-node for production) on AWS. You can run these scripts from your local workstation or an AWS Cloud9 environment as a bastion host.
- [Prerequisites](#prerequisites)
- [Deploying](#deploying)
  - [Deploying a Rama Cluster and Modules](#deploying-a-rama-cluster-and-modules)
- [Cluster Configuration and Debugging](#cluster-configuration-and-debugging)
  - [AMI requirements](#ami-requirements)
  - [systemd and journalctl](#systemd-and-journalctl)
  - [file system layout](#file-system-layout)
- [rama.tfvars variables](#ramatfvars-variables)
  - [username](#username)
  - [vpc\_security\_group\_ids](#vpc_security_group_ids)
  - [rama\_source\_path](#rama_source_path)
  - [license\_source\_path](#license_source_path)
  - [zookeeper\_url](#zookeeper_url)
  - [conductor\_ami\_id](#conductor_ami_id)
  - [supervisor\_ami\_id](#supervisor_ami_id)
  - [zookeeper\_ami\_id](#zookeeper_ami_id)
  - [conductor\_instance\_type](#conductor_instance_type)
  - [supervisor\_instance\_type](#supervisor_instance_type)
  - [zookeeper\_instance\_type](#zookeeper_instance_type)
  - [supervisor\_num\_nodes](#supervisor_num_nodes)
  - [zookeeper\_num\_nodes](#zookeeper_num_nodes)
  - [supervisor\_volume\_size\_gb](#supervisor_volume_size_gb)
  - [use\_private\_ip](#use_private_ip)
  - [private\_ssh\_key](#private_ssh_key)

## Prerequisites

Terraform must be installed.

If you haven't already, create a new EC2 key pair in your AWS Console.
It should automatically download a new `.pem` file. Add the downloaded `.pem`
file to your your private key identities with `ssh-add path/to/file.pem`.

Create a file `~/.rama/auth.tfvars` containing your EC2 keypair name:

```hcl
key_name = "<name of your EC2 key pair>"
```

> **Note:** Only `key_name` belongs in your `auth.tfvars`. If you need to supply a private SSH key for node access, set the `private_ssh_key` variable in your **rama.tfvars**, not in `auth.tfvars`.

Make sure your `~/.rama` directory is in your `PATH`, so that cluster helper commands (e.g., `rama-<cluster-name>`) are available.

For AWS authentication, we recommend setting up [aws-vault](https://github.com/99designs/aws-vault).

### AWS Cloud9 (optional)

You can use an AWS Cloud9 environment as a bastion host to run Terraform and helper scripts without configuring your local machine. For example:

```bash
aws cloud9 create-environment-ec2 \
  --name rama-setup \
  --description "Bastion for Rama AWS Deploy" \
  --instance-type t3.small \
  --automatic-stop-time-minutes 60 \
  --region us-west-2
```

In the AWS Console, open the new Cloud9 environment, assign an IAM role with permissions to manage EC2, S3, and other required services, then clone this repository and follow the remaining steps below.

You can download a Rama release [from our website](https://redplanetlabs.com/download).

## Infrastructure Setup (optional)

This repository includes Terraform to set up auxiliary AWS infrastructure (IAM roles, S3 bucket for artifacts):

```bash
# Deploy IAM resources (admin)
bin/rama-infra.sh admin

# Deploy S3 bucket for artifacts (user)
bin/rama-infra.sh user
```

## Deploying

`rama-aws-deploy` can be used to create either multi-node or single-node Rama deployments.

### Deploying a multi-node Rama cluster

1. Make sure you have your zip file of Rama and license downloaded.
2. Copy the example tfvars and edit it:

   ```bash
   cp rama.tfvars.multi.example rama.tfvars
   ```
   **Tip:** If running Terraform within the same VPC (e.g., AWS Cloud9), set `use_private_ip = true` so provisioning uses the private IP.
   Then open `rama.tfvars` and update the required variables (region, username, vpc_security_group_ids, etc).
3. Run `bin/rama-cluster.sh deploy <cluster-name> [opt-args]`.
   `opt-args` are passed to `terraform apply`.
   For example, if you wanted to just deploy zookeeper servers, you would run
   `bin/rama-cluster.sh deploy my-cluster -target=aws_instance.zookeeper`.

### Deploying a single-node Rama cluster

This option deploys Zookeeper, Conductor, and one supervisor onto the same node.

We recommend using a Graviton2 instance for testing (e.g., `t4g.2xlarge` with 32 GB RAM) and setting `volume_size_gb` at least 20 GB larger than the OS requirements (e.g., 50 GB total).

1. Make sure you have your zip file of Rama and license downloaded.
2. Copy the example tfvars and edit it:

   ```bash
   cp rama.tfvars.single.example rama.tfvars
   ```
   **Tip:** If running Terraform within the same VPC (e.g., AWS Cloud9), set `use_private_ip = true` so provisioning uses the private IP.
   Then open `rama.tfvars` and update the required variables (region, username, vpc_security_group_ids, etc).
  3. Run `bin/rama-cluster.sh deploy --singleNode <cluster-name>`.

### Terraform debug logs on the bastion / jump server

Every invocation of the helper scripts (`bin/rama-cluster.sh` and
`bin/rama-infra.sh`) now records a detailed Terraform log to
`$HOME/.rama/terraform-logs/`.  The log file name contains the operation
(deploy / destroy / plan / infra-admin / infra-user), the cluster (when
applicable) and a timestamp.  You can raise or lower the verbosity by exporting
`TF_LOG` before running the script, or override the destination by setting
`TF_LOG_PATH` yourself.

For example:

```bash
# Only log warnings and errors and write to a custom location
export TF_LOG=WARN
export TF_LOG_PATH=$HOME/tmp/terraform.log
bin/rama-cluster.sh plan my-cluster
```

If `TF_LOG` / `TF_LOG_PATH` are not provided, the scripts default to `INFO`
level and store logs under `~/.rama/terraform-logs/`.


### Deploying modules

Documentation on how to deploy modules is [on this page](https://redplanetlabs.com/docs/~/operating-rama.html#_launching_modules). `rama-aws-deploy` sets up a symlink in `~/.rama` to a `rama` script pointing to the cluster with the name `rama-<cluster-name>`. Here's an example of deploying self-monitoring for a cluster named "staging":

```
rama-staging deploy \
  --action launch \
  --systemModule monitoring \
  --tasks 8 \
  --threads 2 \
  --workers 2
```


### Destroying a cluster

To destroy a cluster run `bin/rama-cluster.sh destroy <cluster-name>` or `bin/rama-cluster.sh --singleNode destroy <cluster-name>` depending on whether it's a multi-node or single node cluster.

## Cluster Configuration and Debugging

### AMI requirements

Zookeeper and Rama require Java to be present on the system to run.
Rama supports LTS versions of Java - 8, 11, 17 and 21. One of these needs to
be installed on the AMI.

`unzip` and `curl` must also be present on the AMI.

### systemd and journalctl

All deployed processes (zookeeper, conductor rama, supervisor rama) are managed
using systemd. systemd is used to start the processes and restart them if they
exit. Some useful snippets include (substitute `conductor` or `supervisor` for
`zookeeper`):

``` sh
sudo systemctl status zookeeper.service # check if service is running
sudo systemctl start zookeeper.service
sudo systemctl stop zookeeper.service
```

systemd uses journald for logging. Our processes configure their own logging,
but logs related to starting and stopping will be captured by journald. To read
logs:

``` sh
journalctl -u zookeeper.service    # view all logs
journalctl -u zookeeper.service -f # follow logs
```

An application's systemd config file is located at

``` sh
/etc/systemd/system/zookeeper.service
```

### file system layout

Each cluster node has one main application process; zookeeper nodes run
zookeeper, conductor nodes run a rama conductor, supervisor nodes run a rama
supervisor.

The relevant directories to look at are the `$HOME` directory, as well as
`/data/rama`.  In particular, the supervisor download script logs any retry
failures to `/data/rama/download.log`, and the conductor/unpack steps record
startup errors in systemd.  You can inspect these via:

```sh
sudo journalctl -u conductor.service
sudo journalctl -u supervisor.service
```

Any health-check failures during Terraform provisioning will also be printed
directly in the Terraform console output via the inline `journalctl` commands.

## rama.tfvars variables

### region
- type: `string`
- required: `true`

The AWS region to deploy the cluster to.

### username
- type: `string`
- required: `true`

The login username to use for the nodes. Needed to know how to SSH into them and know where the
home directory is located.

### vpc_security_group_ids
- type: `list(string)`
- required: `true`

The security groups that the nodes are members of.

### rama_source_path
- type: `string`
- required: `true`

An absolute path or URL pointing to the location of your `rama.zip`. If this is a URL (e.g. S3), the node will download it via `curl`.

### license_source_path
- type: `string`
- required: `false`

An absolute path pointing to the location on the local disk of your Rama license file. If this is empty or the file does not exist,
no license will be injected and the cluster will still deploy (single-node and up to two supervisors work without a license).

### zookeeper_url
- type: `string`
- required: `true`

The URL to download a zookeeper tar ball from to install on the zookeeper node(s).

### conductor_ami_id
- type: `string`
- required: `true`

The AMI ID that the conductor node should use.

### supervisor_ami_id
- type: `string`
- required: `true`

The AMI ID that the supervisor node(s) should use.

### zookeeper_ami_id
- type: `string`
- required: `true`

The AMI ID that the zookeeper node(s) should use.

### conductor_instance_type
- type: `string`
- required: `true`

The AWS instance type that the conductor node should use.

Ex. m6g.medium

### supervisor_instance_type
- type: `string`
- required: `true`

The AWS instance type that the supervisor node(s) should use.

### zookeeper_instance_type
- type: `string`
- required: `true`

The AWS instance type that the zookeeper node(s) should use.

### supervisor_num_nodes
- type: `number`
- required: `true`

The number of supervisor nodes you want to use.

### zookeeper_num_nodes
- type: `number`
- required: `false`
- default: `1`

The number of zookeeper nodes you want to use.

Note: Zookpeeer recommends setting this to an odd number

### supervisor_volume_size_gb
- type: `number`
- required: `false`
- default: `100`

The size of the supervisors' disks on the nodes.

### use_private_ip
- type: `bool`
- required: `false`
- default: `false`

Whether to use the instance's public IP (false) or private IP (true) for provisioning.

If you are running Terraform within the same VPC (e.g., an AWS Cloud9 bastion), set this to `true`
so that SSH/provisioners use the node's private IP address.

### private_ssh_key
- type: `string`
- required: `false`
- default: `null`
