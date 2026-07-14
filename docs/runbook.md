# Patch Tuesday / application update runbook

## 1. Build and test the new image

1. Patch Windows and baked applications in the image pipeline.
2. Run security scanning, functional testing, and approval gates.
3. Publish a **new Azure Compute Gallery image version**.
4. Mark or tag the image version according to your approval process.

## 2. Resolve and pin the approved image version

Use the gallery-image script so the deployment consumes an immutable version ID instead of a mutable `latest` reference.

```powershell
./scripts/Resolve-AvdGalleryImageVersion.ps1   -ResourceGroupName rg-image-prod   -GalleryName cgavd   -ImageDefinitionName win11-m365-avd   -RequiredTagName approval   -RequiredTagValue approved   -OutputFormat Json
```

Update Terraform or Bicep inputs with the emitted version ID.

## 3. Plan / what-if the new generation

### Terraform

- Use a **new generation name** and **new state key**.
- Run `terraform plan` before `terraform apply`.
- Never reuse the old generation's state file for the new rollout.

### Bicep

- Use a **new deployment name**.
- Run `az deployment group what-if` before `az deployment group create`.

## 4. Deploy the new generation

- Set `session_host_count` / `sessionHostCount` to a value from **1 to 100**.
- Set `start_host_number` / `startHostNumber` so the new generation gets a new number range.
- Supply a short-lived registration token expiration time and secure secret inputs.

## 5. Validate the new generation

```powershell
./scripts/Test-AvdGenerationReadiness.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2408   -ExpectedCount 5   -SessionHostResourceGroupName rg-avd-sh-g2408
```

Optionally run additional application smoke tests through the custom script hook or your own validation pipeline.

## 6. Pilot the new generation

- Keep the old generation enabled while pilot users validate the new hosts.
- Validate application launches, profile containers, printer mappings, domain/Entra identity behavior, and monitoring signals.

## 7. Drain the old generation

```powershell
./scripts/Set-AvdGenerationDrainMode.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407
```

This disables new sessions without deleting the old infrastructure.

## 8. Review and optionally log off sessions

```powershell
./scripts/Get-AvdGenerationUserSessions.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407
```

Only when your change process explicitly allows it:

```powershell
./scripts/Get-AvdGenerationUserSessions.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407   -ForceLogoff -Confirm
```

## 9. Retire old infrastructure

Use a separate change window after validation and session handling:

- Terraform: run `terraform destroy` against the **old generation state**.
- Bicep / generic cleanup: use the explicit infrastructure cleanup script or your approved delete process.

```powershell
./scripts/Remove-AvdGenerationInfrastructure.ps1   -ResourceGroupName rg-avd-sh-g2407   -GenerationName g2407   -WhatIf
```

## 10. Remove stale AVD registrations

```powershell
./scripts/Remove-AvdRetiredSessionHostRegistrations.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407   -SessionHostResourceGroupName rg-avd-sh-g2407   -Force -Confirm
```

## 11. Roll back if necessary

1. Re-enable the previous generation for new sessions.
2. Drain the failed new generation.
3. Stop/deallocate or remove the failed new generation only after confirming users are safe.
4. Keep the gallery image version pin and state/deployment boundaries intact so rollback remains deterministic.
