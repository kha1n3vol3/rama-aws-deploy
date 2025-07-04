# Suggested Refactor & Best-Practices Guide

This document presents **opinionated recommendations** for refactoring the
Rama AWS deployment so that it aligns with well-established cloud and
Terraform best-practices.  The suggestions build on the observations in
`README.md` and the implicit assumptions captured in `assumptions.md`.

The goal is to make the project:

* **Easier to operate** – predictable, idempotent, observable.
* **Easier to extend** – clear separation of concerns, modular code.
* **More secure** – least-privilege, secrets management, reproducible builds.

---

## 1. Replace per-instance *remote-exec* with immutable AMIs

Current state
-------------
Provisioning is done via a mixture of `cloud-init`, `file` and `remote-exec`
provisioners.  This couples instance boot time to external network I/O (large
downloads) and SSH connectivity, making deployments slow and fragile.

Recommendation
--------------

1. Adopt **Packer** (or EC2 Image Builder) to bake a versioned “Rama Node” AMI
   containing:
   * Rama binaries in `/opt/rama`.
   * Pre-installed Java and ZooKeeper (system packages or container images).
   * Systemd unit files already enabled.
2. Terraform then launches the AMI with *no* additional SSH-time provisioning –
   only minimal `user_data` to inject cluster-specific `rama.yaml`.

Benefits
* Boot time measured in seconds, not minutes.
* Works behind strict firewalls (no outbound Internet needed at boot).
* Eliminates SSH keys and `remote-exec` failures from the critical path.

---

## 2. Model the cluster as Terraform **modules**

Break the monolithic `rama-cluster` directory into small, composable modules:

Module | Responsibility
------ | -------------
`network` | VPC, subnets, security groups.
`zookeeper` | ASG or single instance running ZooKeeper (see §4 for container option).
`conductor` | Launch template / ASG for Conductor nodes.
`supervisor` | Launch template / ASG for Supervisor nodes.

The root module only wires the pieces together.  This structure encourages
re-use and automated testing (e.g. Terratest per module).

---

## 3. Containerise ZooKeeper (and optionally Rama)

Hard-coding paths and writing systemd units *inside* the instance exposes you
to OS differences.  Instead:

* Package ZooKeeper as an **official Docker image** run by ECS/Fargate or
  systemd-nspawn/Podman on the VM.
* The image carries its own binaries – no tarball download logic required.

Advantages
* Version pinning with a simple `image:tag`.
* Unified upgrade path (blue/green deployments, rolling restarts).

---

## 4. Use AWS Autoscaling groups & load balancers

Even a “single” cluster benefits from AutoScaling:

* Health checks performed by the **ASG lifecycle** instead of ad-hoc shell
  loops.
* Zero-downtime upgrades – launch new instances, wait for ELB health
  check, terminate old ones.

Terraform resources: `aws_launch_template`, `aws_autoscaling_group`,
`aws_lb_target_group`, `aws_lb_listener`.

---

## 5. Secrets & configuration management

* Store `rama.license` and any sensitive `rama.yaml` overrides in **AWS
  Secrets Manager** or SSM Parameter Store.
* Pull them at boot using instance-profile IAM instead of embedding plaintext
  in `terraform.tfvars`.

---

## 6. Observability built-in

1. Forward systemd journal and Rama logs to **CloudWatch Logs** via the
   `awslogs` or Fluent Bit agent – no need to SSH for troubleshooting.
2. Emit **CloudWatch metrics** (service up/down, JVM memory) and set alarms.

---

## 7. Harden security

* Drop inbound SSH entirely once the AMI is immutable; use **SSM Session
  Manager** for break-glass access.
* Give each component the **least-privilege IAM role** (e.g. Conductor may
  need to write S3, Supervisors only read).

---

## 8. Terraform hygiene

* Enable a **remote backend** (S3 + DynamoDB lock) – required for team use.
* Pin provider & module versions with `<` upper bounds to avoid surprise
  upgrades.
* Run `terraform validate`, `tflint` and `checkov` in CI.

---

## 9. CI/CD workflow

Pipeline suggestion:

1. **Packer** builds new AMI on each Rama release; AMI id stored in SSM.
2. Terraform plan applies against a staging account – Terratest validates the
   cluster.
3. Manual approval → promote AMI id to production parameter → terraform apply
   in prod account.

---

## 10. Documentation & DX

* Replace long shell heredocs with standalone, version-controlled scripts
  referenced via `templatefile()`.
* Provide a **`make deploy`** that wraps var files, workspace selection and
  pre-commit hooks for consistent local workflow.

---

> **TL;DR** – Baking an immutable AMI (or container image) and using
> AutoScaling groups with proper observability removes the need for 80 % of the
> imperative shell code currently present in the repo, leading to faster and
> more reliable deployments.

