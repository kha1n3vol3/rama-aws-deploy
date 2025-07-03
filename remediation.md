# Rama AWS Deploy – Unpack Script Race Condition Remediation

## July 2025 – Conductor service fails to start (systemd race condition)

### Symptoms

Terraform stops in the `remote-exec` phase with:

```
systemctl is-active --quiet conductor.service
Conductor service failed to start
-- No entries --
```

`journalctl` returns *No entries* which means the unit file was never loaded
by `systemd` when the health-check ran.

### Root cause

The health-check was executed **before** cloud-init / the `start.sh` helper
finished creating & enabling the `conductor.service` unit.  In other words we
were checking too early – a classic provisioning race condition.

### Remediation / best-practice updates

1. **Move service validation to the very end** of the provisioning sequence.  
   *Removed* the early `remote-exec` check on the `aws_instance` resource and
   added a new check *after* `start.sh` (or, in the multi-node template, a
   dedicated `null_resource` that depends_on the instance).

2. **Add blocking loops to `start.sh`.**  Each script now waits up to
   ~30 seconds for its `systemd` unit to enter the *active* state and prints
   useful logs if it does not.

3. **Keep the Terraform plan idempotent.**  All loops exit successfully once
   the service is up, so rerunning `terraform apply` remains a no-op when the
   cluster is healthy.

4. **General systemd provisioning guidelines**
   • Always `systemctl enable` *and* `systemctl start` during bootstrap.  
   • Verify with a bounded retry loop instead of a single `is-active` call.  
   • Export logs with `journalctl` when a service fails – this greatly speeds
     up debugging.

These changes are implemented in commit bcbee5d and later.


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

---

# July 2025 follow-up – “Invalid escape sequence” in `single/main.tf`

## Observed error

Running `bin/rama-cluster.sh deploy --singleNode` fails during `terraform init` with:

```
│ Error: Invalid escape sequence
│   on main.tf line 125, in resource "aws_instance" "rama":
│  125: … \$(grep 'local.dir' rama.yaml | cut -d':' -f2 | xargs); if [ -n \"$local_dir\" ]; …
│ The symbol "$" is not a valid escape sequence selector.
```

Terraform treats *any* back-slash followed by a non-whitelisted character inside a double-quoted
string as an **illegal escape sequence**.  In our case we attempted to “escape” the Bash subshell
`$( … )` with `\$(`.  That is unnecessary (and wrong) in HCL: the only construct we *must* protect
is the interpolation form `${ … }`.

## Remediation

1. **Stop back-slashing `$`**

   Replace

   ```hcl
   local_dir=\$(grep 'local.dir' … )
   ```

   with

   ```hcl
   local_dir=$$(grep 'local.dir' … )
   ```

   • `$$` is an idiomatic way to emit a literal `$` inside a Terraform string.
   • We *keep* the back-slash in front of the **double quotes** (`\"`) because those really need to
     be escaped inside the outer HCL string.

2. **Prefer a heredoc for long shell one-liners**

   When the command grows past a few tokens, readability quickly degrades and escaping becomes
   error-prone.  Terraform allows a [*literal heredoc*](https://developer.hashicorp.com/terraform/language/expressions/strings#heredoc-templates)
   that disables interpolation by quoting the delimiter – an approach that eliminates 100 % of the
   back-slash spaghetti:

   ```hcl
   provisioner "remote-exec" {
     inline = [ <<-"SCRIPT"
       bash -euxo pipefail -c '
       # Wait until the EBS volume is mounted
       while [ ! -d /data/rama ]; do sleep 2; done

       sudo mv -f /home/${var.username}/rama.zip /data/rama/
       cd /data/rama
       sudo unzip -n rama.zip

       local_dir=$(grep "local.dir" rama.yaml | cut -d":" -f2 | xargs)
       if [ -n "$local_dir" ]; then
         sudo mkdir -p "$local_dir/conductor/jars"
         sudo cp -f rama.zip "$local_dir/conductor/jars"
       fi
       '
     SCRIPT
     ]
   }
   ```

   Key points:
   • The delimiter is quoted (`"SCRIPT"`), which tells Terraform *not* to process `${…}` or `$$` –
     the block is passed verbatim to the remote shell.
   • The Bash script is now readable, testable and free from double escaping.

3. **General best-practice checklist for Terraform + shell**

   • Keep complex logic in separate scripts or templates (use `templatefile()`), not inline strings.
   • Use *literal* heredocs (`<<-"EOF"`) whenever you need verbatim content.
   • Avoid mixing `cloud-init` and `remote-exec` for the same task; pick one.
   • Always enable `set -euo pipefail` (or `-euxo pipefail`) in your shell code.
   • Make every step idempotent so that `terraform apply` remains repeatable.

## Migration steps

1. Replace the offending `inline` entry in `rama-cluster/single/main.tf` with the heredoc form above.
2. Run `terraform fmt` to re-format the file.
3. `terraform init` should now succeed; follow with `terraform apply` for a full validation.

---
