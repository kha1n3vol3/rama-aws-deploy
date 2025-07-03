# Rama AWS Deploy – Unpack Script Race Condition Remediation

## Problem statement

`terraform apply` intermittently fails during the *Download and unpack Rama* phase with:

```
chmod: cannot access 'unpack-rama.sh': No such file or directory
```

Root cause: the deployment workflow relies on a shell script (`/data/rama/unpack-rama.sh`) being **written by cloud-init** and subsequently executed via a Terraform `remote-exec` provisioner.  The two operations happen in parallel; when the provisioner wins the race, the script does not yet exist and the apply fails.

This affects both the `single` and `multi` cluster templates.

## Current flow (simplified)

1. `cloud-init` (through `write_files`) is asked to place `unpack-rama.sh` under `/data/rama`.
2. Terraform continues immediately after the EC2 instance reports *running*.
3. A `remote-exec` provisioner runs:
   ```bash
   cd /data/rama && chmod +x unpack-rama.sh && ./unpack-rama.sh
   ```
4. Step (3) fails if (1) has not finished.

## Design constraints

* **Idempotency** – A second `terraform apply` should converge without manual cleanup.
* **Minimal moving parts** – Avoid scattering logic across both cloud-init and remote-exec when one mechanism is enough.
* **Security** – Run only the commands required, with the minimum privileges (sudo only where necessary).

## Remediation plan

### 1. Eliminate `unpack-rama.sh`

The script’s body is essentially:

```bash
sudo mv /home/${username}/rama.zip /data/rama
cd /data/rama
sudo unzip -n rama.zip

# copy for supervisors
local_dir=$(grep "local.dir" rama.yaml | cut -d ':' -f2 | xargs)
sudo mkdir -p "$local_dir/conductor/jars"
sudo cp rama.zip "$local_dir/conductor/jars"
```

Instead of writing this file and executing it, perform the same operations **directly inside the provisioner**.  That removes any dependency on file existence and simplifies reasoning.

### 2. Use a single, guarded `remote-exec` block

```
provisioner "remote-exec" {
  inline = [
    <<-EOF
      bash -euxo pipefail -c '
      # Give cloud-init time to finish disk setup (if needed)
      while [ ! -d /data/rama ]; do sleep 2; done

      sudo mv /home/${var.username}/rama.zip /data/rama
      cd /data/rama
      sudo unzip -n rama.zip

      local_dir=$(grep "local.dir" rama.yaml | cut -d":" -f2 | xargs)
      sudo mkdir -p "$local_dir/conductor/jars"
      sudo cp rama.zip "$local_dir/conductor/jars"
      '
    EOF
  ]
}
```

Advantages:
* No race – the commands only depend on directories, not on files created elsewhere.
* Idempotent – `unzip -n` skips already-extracted files.

### 3. Remove `write_files` entry

Delete the `unpack-rama.sh` stanza from `cloud-config.yaml` in both templates.

### 4. Clean up variables / templates

* Remove `../common/conductor/unpack-rama.sh` template (or keep for reference but unused).
* Delete `unpack_rama_contents` variables in `data "cloudinit_config"`.

### 5. Update documentation

Document that unpacking is handled automatically by Terraform and no longer involves an extra script.

## Roll-out strategy

1. Implement changes on a feature branch.
2. Run integration test: `bin/rama-cluster.sh deploy test-cluster --singleNode` and multi-node path.
3. Confirm second `terraform apply` is a no-op.
4. Merge & tag.

## Future hardening suggestions

* Consider moving **all** node-initialisation into cloud-init only, eliminating `remote-exec` from Terraform; or vice-versa. Having both increases complexity.
* Use `aws_launch_template` with user-data instead of individual `aws_instance` + provisioners; this makes the EC2 service responsible for setup and removes SSH provisioning from Terraform entirely.

---

Authored by: GitHub Copilot-based remediation bot 2025-07-03
