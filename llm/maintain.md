====================================================
Project maintenance & code-base update checklist
(single-node testing mode)
====================================================

This document captures everything needed to maintain a repeatable single-node Rama
cluster deployment on AWS for testing purposes. Once this workflow is solid, we will
refactor and extend to a multi-node architecture.

----------------------------------------------------
1. Repository layout
----------------------------------------------------

```text
rama-aws-deploy/
├─ bin/
│  ├─ rama-cluster.sh        # wrapper for cluster deployments
│  ├─ rama-infra.sh          # bootstrap IAM & S3
│  └─ rama-util              # misc utilities
├─ rama-cluster/
│  ├─ common/                # shared scripts & cloud-init templates
│  └─ single/                # single-node deployment
│     ├─ main.tf
│     ├─ versions.tf         # provider version pinning
│     ├─ cloud-config.yaml
│     ├─ rama.yaml
│     └─ start.sh
├─ rama-infra/
│  ├─ admin/                 # IAM bootstrap (admin)
│  │   └─ main.tf
│  └─ user/                  # IAM/S3 bootstrap (user)
│      └─ main.tf
├─ rama.tfvars.single.example # cluster variables example for single-node
└─ ~/.rama/auth.tfvars         # per-developer secrets (outside repo)
```

• Copy `rama.tfvars.single.example` → `rama.tfvars` at the repo root.  
• Use `bin/rama-cluster.sh deploy --singleNode <cluster-name>` (or manual `cd`
  + and `terraform` commands inside `rama-cluster/single/`) to deploy/destroy.

----------------------------------------------------
2. `.tf` vs `.tfvars`
----------------------------------------------------
* `.tf`     = Terraform configuration (resource, provider, variable, data, locals, etc.).
* `.tfvars` = Values for variables.
Never put blocks (`variable`, `provider`, `resource`, etc.) in `.tfvars` files.

----------------------------------------------------
3. Variable hygiene
----------------------------------------------------
* **Required variables** (no defaults) are declared at the top of `main.tf`. Their
  values come from your `rama.tfvars` and `~/.rama/auth.tfvars`.
* **Optional variables** should have sensible `default` values to avoid prompts.
* When adding a new variable:
  1. Declare it in `main.tf` (or in `variables.tf` if you refactor).
  2. Document and/or provide a default if appropriate.
  3. Update `rama.tfvars.single.example` (and `rama.tfvars.multi.example`).

----------------------------------------------------
4. Provider version pinning
----------------------------------------------------
Pin provider versions in `versions.tf` to silence deprecation warnings — do **not**
use `version` inside the `provider` blocks.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.1.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.2.0"
    }
  }
}
```
Ensure `rama-cluster/single/versions.tf` contains these blocks, and remove any `version`
lines from the `provider "aws"` or `provider "cloudinit"` blocks in `main.tf`.

----------------------------------------------------
5. Security group requirements
----------------------------------------------------
The code does **not** create security groups automatically. In your `rama.tfvars`:
```hcl
vpc_security_group_ids = ["sg-0123456789abcdef0"]
```
Make sure this SG allows SSH (port 22) from your workstation’s IP, and any other
needed ports (e.g. 8888 for Conductor UI).

----------------------------------------------------
6. AMI ⇄ SSH user mapping
----------------------------------------------------
Match the `username` in `rama.tfvars` to the AMI you pick:
* Amazon Linux / AL2         → `ec2-user`
* Ubuntu                     → `ubuntu`
* Bottlerocket (no SSH)      → *N/A*

----------------------------------------------------
7. Non-interactive `apply` / `destroy`
----------------------------------------------------
```bash
cd rama-cluster/single
terraform init
terraform apply \
  -var-file=../../rama.tfvars \
  -var-file=$HOME/.rama/auth.tfvars \
  -auto-approve

terraform destroy \
  -var-file=../../rama.tfvars \
  -var-file=$HOME/.rama/auth.tfvars \
  -auto-approve
```

----------------------------------------------------
8. Output URL adjustments
----------------------------------------------------
Update the `ec2_console` output to use your `region` variable — otherwise
hardcoded links will point to the wrong region.

```hcl
output "ec2_console" {
  value = "https://console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:tag:Name=${var.cluster_name}-cluster-supervisor,${var.cluster_name}-cluster-conductor,${var.cluster_name}-cluster-zookeeper;instanceState=running;sort=desc:tag:Name"
}
```

----------------------------------------------------
9. Checklist for future updates
----------------------------------------------------
□ When adding new variables: declare, default if needed, and update the example tfvars.
□ Bump provider versions in **one** place: `versions.tf`.
□ Ensure the wrapper script still `cd`s into the right folder.
□ Run `terraform validate` on `rama-cluster/single/`.
□ Keep docs (`README.md`, `llm/maintain.md`, examples) in sync.
