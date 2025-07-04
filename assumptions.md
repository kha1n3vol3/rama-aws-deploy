# Deployment Assumptions & Hard-coded Paths

This document enumerates all hard-coded paths, implicit pre-conditions and
external dependencies that the Terraform templates and bootstrap scripts rely
on.  The information is useful when porting the deployment to a different
Linux distribution / cloud provider or integrating it into an automated CI
pipeline.

---

## 1. File-system layout

Path | Usage | Component(s)
---- | ----- | ------------
`/data/rama` | Location where `rama.zip` is copied and extracted.  The Rama binaries are expected at `/data/rama/rama` and the working directory of the Conductor/Supervisor services is set to this path. | `single/main.tf`, `multi/cluster.tf`, systemd service template
`/home/${username}` | Home directory of the SSH user that Terraform connects as.  Multiple files are written here during provisioning – e.g. `rama.zip`, `zookeeper.service`, temporary scripts. | Many provisioners
`~/zookeeper` (i.e. `/home/${username}/zookeeper`) | Target directory where the ZooKeeper tarball is unpacked.  The systemd unit expects `~/zookeeper/bin/zkServer.sh`. | `common/zookeeper/setup.sh`, systemd unit
`/etc/systemd/system` | Destination for systemd unit files (`conductor.service`, `supervisor.service`, `zookeeper.service`). | cloud-init `write_files`

## 2. System services

Service | Description | Defined in | Expectation
------- | ----------- | ---------- | -----------
`conductor.service` | Runs Rama Conductor (`/data/rama/rama conductor`). | `common/systemd-service-template.service` | systemd present and functioning.
`supervisor.service` | Runs Rama Supervisor (`/data/rama/rama supervisor`). | same as above | systemd present.
`zookeeper.service` | Runs ZooKeeper in foreground mode using scripts under `~/zookeeper`. | `common/zookeeper/zookeeper.service` | systemd present.

All templates assume **systemd** is the init system.

## 3. Required binaries on the AMI / base image

Binary | Why it is needed
------ | ---------------
`curl` | Download Rama zip.
`wget` | Download ZooKeeper tarball.
`unzip` | Extract Rama zip.
`tar`   | Extract ZooKeeper archive.
`sudo`  | All scripts use `sudo` for privileged operations.
`systemctl` | Managing services.

> The scripts do **not** attempt to install these packages – they must exist on
> the base image.

## 4. Java runtime

Neither Rama nor ZooKeeper will start without a JDK/JRE (≥ Java 8).  The
scripts assume Java is pre-installed and available on `$PATH` as `java`.

## 5. Network & AWS prerequisites

1. The IAM role or instance profile must allow outbound HTTPS to download Rama
   and ZooKeeper.
2. Security group(s) allow inbound SSH from the Terraform runner.
3. The `key_name` variable refers to an existing EC2 key pair.

## 6. Cloud-init

The templates make heavy use of _cloud-init_ (`user_data`) for disk setup and
writing unit files. The target AMI **must** include cloud-init.

## 7. Hard-coded time-outs & loops

* ZooKeeper readiness loop: 60 attempts × 2 s = ~120 s.
* Service health-checks in Terraform: loops of up to 30 – 60 s.

These may need tuning for slower instances.

## 8. Unsupported scenarios

* Non-systemd init systems (e.g. sysvinit, openrc).
* Read-only /etc (cannot write unit files).
* No sudo privileges for the connecting SSH user.

---

Last updated: $(date -u +%Y-%m-%d)

