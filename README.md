# AVD Rip and Replace

Production-oriented Infrastructure-as-Code for Azure Virtual Desktop (AVD) session-host **rip-and-replace patching**. The repository is designed for customers that publish a newly patched, application-baked image, deploy a new generation of session hosts beside the current one, validate and pilot the new generation, place the old generation in drain mode, and retire it only as a separate, explicit step.

## What this repository does

- Deploys **1-100** newly numbered AVD session hosts per rollout with deployment-time validation.
- Uses deterministic **generation-based names** and a configurable **starting host number** so new hosts never collide with the previous generation.
- Prefers **immutable Azure Compute Gallery image version IDs** and only allows pinned marketplace versions as an alternative.
- Supports an **existing host pool** or optional creation of the host pool, desktop application group, and workspace.
- Supports **Microsoft Entra ID sign-in**, **traditional Active Directory domain join**, or no join action.
- Creates VMs, NICs, managed identity, Trusted Launch settings, boot diagnostics, tags, zones, and optional post-deployment custom-script hooks.
- Keeps **deployment** and **retirement** separate so a standard apply/deploy cannot delete the old generation.
- Adds safe operator scripts for validation, drain mode, session handling, and retirement.
- Adds GitHub Actions validation that does **not require Azure credentials** on pull requests.

> The solution **consumes a tested image**. It does **not** patch Windows or customer applications during deployment and it does **not** claim that "selecting the latest image" updates baked applications. You must publish and approve a new immutable image version before rollout.

## Repository layout

```text
.
├── .github/workflows/validate.yml
├── bicep/
│   ├── bicepconfig.json
│   ├── main.bicep
│   ├── modules/
│   │   ├── hostPool.bicep
│   │   └── sessionHostGeneration.bicep
│   └── parameters/example.parameters.json
├── docs/
│   ├── diagrams/
│   │   ├── architecture.md
│   │   └── process.md
│   ├── reference.md
│   └── runbook.md
├── scripts/
│   ├── Get-AvdGenerationSessionHosts.ps1
│   ├── Get-AvdGenerationUserSessions.ps1
│   ├── Remove-AvdGenerationInfrastructure.ps1
│   ├── Remove-AvdRetiredSessionHostRegistrations.ps1
│   ├── Resolve-AvdGalleryImageVersion.ps1
│   ├── Set-AvdGenerationDrainMode.ps1
│   ├── Test-AvdGenerationReadiness.ps1
│   └── Modules/AvdRipReplace/AvdRipReplace.psm1
└── terraform/
    ├── environments/example/
    └── modules/
        ├── host-pool/
        └── session-host-generation/
```

## Architecture

See the Mermaid sources in [docs/diagrams/architecture.md](docs/diagrams/architecture.md) and [docs/diagrams/process.md](docs/diagrams/process.md).

## Assumptions and prerequisites

- Azure Virtual Desktop control-plane provider registrations already exist in the target subscription.
- An **approved** Azure Compute Gallery image version is available, or a pinned marketplace version is intentionally selected.
- A virtual network and subnet already exist for session hosts.
- Operators authenticate with Azure by using Azure CLI or Az PowerShell before executing deployment or lifecycle commands.
- Session-host generations are best managed with **separate state files / deployment names / resource groups**. The example layout and runbook show one resource group and one state entry per generation.

### Required Azure RBAC and identity permissions

At minimum, the deployment identity should be able to:

- Create and manage VMs, NICs, managed identities, diagnostics, and extensions in the session-host resource group.
- Create or manage AVD host pools, workspaces, and application groups when `create_host_pool` / `createHostPool` is used.
- Read Azure Compute Gallery image versions.
- Join devices to Microsoft Entra ID or Active Directory according to your chosen pattern.
- Generate or rotate a short-lived host-pool registration token.

### Tool versions

- Terraform `>= 1.8.0`
- AzureRM provider `~> 4.8`
- Bicep CLI `0.44+`
- PowerShell `7+`
- Az PowerShell modules for `Az.Compute`, `Az.DesktopVirtualization`, `Az.Network`, and `Az.Resources`

## Cost and security considerations

- Never deploy more than **100 session hosts in a single rollout**.
- Use **short-lived registration tokens** and pass them as secure variables/parameters only.
- Do not commit `.tfvars`, real parameter files, passwords, or tokens.
- Prefer **Trusted Launch**, managed identities, and private networking.
- Keep old and new generations independently manageable so rollback only requires toggling drain state and session routing, not emergency rebuilds.

## Quick start - Terraform

1. Copy the sample file and fill in placeholders:

   ```bash
   cp terraform/environments/example/terraform.tfvars.example terraform/environments/example/terraform.tfvars
   ```

2. Resolve and pin the image version:

   ```powershell
   ./scripts/Resolve-AvdGalleryImageVersion.ps1      -ResourceGroupName rg-image-prod      -GalleryName cgavd      -ImageDefinitionName win11-m365-avd      -OutputFormat Terraform
   ```

3. Initialize and validate:

   ```bash
   terraform -chdir=terraform/environments/example init -backend=false
   terraform -chdir=terraform/environments/example fmt -recursive
   terraform -chdir=terraform/environments/example validate
   ```

4. Plan and apply using a generation-specific state key (example backend shown conceptually):

   ```bash
   terraform -chdir=terraform/environments/example plan
   terraform -chdir=terraform/environments/example apply
   ```

### Terraform notes

- The example environment can **create** a host pool for the first rollout or attach to an **existing** host pool for later generations.
- `session_host_count` enforces the **1-100** limit.
- `image_source.gallery_image_version_id` must be a full, immutable image version resource ID.
- Use a **new generation name** and, if needed, a new `start_host_number` for each rollout.
- Treat `terraform destroy` for an old generation as a separate change window after validation, drain, and session handling are complete.

## Quick start - Bicep

1. Copy the example parameter file and replace placeholders:

   ```bash
   cp bicep/parameters/example.parameters.json /tmp/avd.parameters.json
   ```

2. Build and lint:

   ```bash
   bicep build bicep/main.bicep
   bicep lint bicep/main.bicep
   ```

3. Deploy with a **pinned** gallery image version and a short-lived registration token for existing host pools:

   ```bash
   az deployment group create      --resource-group rg-avd-sh-g2407      --template-file bicep/main.bicep      --parameters @/tmp/avd.parameters.json
   ```

### Bicep notes

- `sessionHostCount` enforces the **1-100** limit with decorators and assertions.
- Existing host-pool deployments require `existingHostPoolRegistrationToken` as a secure parameter.
- New host-pool deployments can create the host pool, desktop application group, and workspace in the same template.
- Retirement remains a **separate operator action** and is intentionally not part of `main.bicep`.

## Generation lifecycle guidance

Use a **generation-per-state** or **generation-per-resource-group** operating model:

- Example resource groups: `rg-avd-sh-g2407`, `rg-avd-sh-g2408`
- Example state keys: `prod/g2407.tfstate`, `prod/g2408.tfstate`
- Example Bicep deployment names: `avd-g2407`, `avd-g2408`

This keeps old and new generations side-by-side and prevents a routine apply or deployment from implicitly deleting the previous generation.

## Rollback

1. Stop pilot/cutover activity for the new generation.
2. Re-enable the old generation for new sessions:

   ```powershell
   ./scripts/Set-AvdGenerationDrainMode.ps1 -HostPoolName hp-avd-prod -ResourceGroupName rg-avd-controlplane-prod -GenerationName g2407 -EnableNewSessions
   ```

3. Put the failed new generation in drain mode.
4. If required, stop/deallocate or remove the failed new generation only after confirming no active user sessions remain.
5. Clean up AVD registrations after infrastructure retirement:

   ```powershell
   ./scripts/Remove-AvdRetiredSessionHostRegistrations.ps1 -HostPoolName hp-avd-prod -ResourceGroupName rg-avd-controlplane-prod -GenerationName g2408 -Force
   ```

## Troubleshooting and limitations

- Generated Windows computer names must remain **15 characters or fewer**.
- The repository assumes customer application installation is handled in the **baked image**, not by the custom script extension.
- The PowerShell scripts expect the Az modules and signed-in context to be present on the operator workstation.
- Bicep existing-host-pool deployments expect a secure registration token value to be supplied externally.
- The example files use placeholders and cannot deploy successfully until intentionally configured.

## Runbook and reference documentation

- [End-to-end runbook](docs/runbook.md)
- [Terraform and Bicep variable reference](docs/reference.md)
- [Architecture diagram](docs/diagrams/architecture.md)
- [Process diagram](docs/diagrams/process.md)
