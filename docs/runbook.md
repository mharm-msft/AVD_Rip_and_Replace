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

## 7. Mark the replacement generation as approved

Record the new generation name as the explicit replacement validation marker. This value must be provided to the drain and retirement scripts to confirm readiness — the automation does **not** infer readiness from VM age or image version alone.

```text
replacement_generation = "g2408"
```

## 8. Drain the old generation (with drain timestamp tagging)

The drain script now tags the backing VMs with authoritative retirement metadata. The
**30-hour clock starts at this step**, not when the new generation was deployed.

```powershell
# Drain and record the drain-start timestamp; opt in to automatic deletion
./scripts/Set-AvdGenerationDrainMode.ps1 `
  -HostPoolName hp-avd-prod `
  -ResourceGroupName rg-avd-controlplane-prod `
  -GenerationName g2407 `
  -SessionHostResourceGroupName rg-avd-sh-g2407 `
  -TagAutoDelete
```

The VM tags set are:

| Tag | Value |
| --- | --- |
| `AVDDrainMode` | `true` |
| `AVDDrainStartedAt` | UTC ISO-8601 timestamp (e.g. `2024-07-14T19:00:00.0000000Z`) |
| `AVDGeneration` | `g2407` |
| `AVDAutoDelete` | `true` (only when `-TagAutoDelete` is supplied) |

> **Idempotency**: Re-running the drain script preserves the existing `AVDDrainStartedAt` timestamp
> so the retention clock is not accidentally reset. To intentionally reset the clock, pass `-ResetDrainTimestamp`.
> **Cancelling auto-deletion**: Remove the `AVDAutoDelete=true` tag from the VM or re-enable the
> session host for new sessions before the retention period elapses.

## 9. Review and optionally log off sessions

```powershell
./scripts/Get-AvdGenerationUserSessions.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407
```

Only when your change process explicitly allows it:

```powershell
./scripts/Get-AvdGenerationUserSessions.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407   -ForceLogoff -Confirm
```

## 10. Retire old infrastructure

### Option A — Manual retirement (separate change window)

Use a separate change window after validation and session handling:

- Terraform: run `terraform destroy` against the **old generation state**.
- Bicep / generic cleanup: use the explicit infrastructure cleanup script or your approved delete process.

```powershell
./scripts/Remove-AvdGenerationInfrastructure.ps1   -ResourceGroupName rg-avd-sh-g2407   -GenerationName g2407   -WhatIf
```

### Option B — Automated opt-in retirement (after 30 hours)

The automated retirement runbook (`Invoke-AvdAutoRetirement.ps1`) checks all eligible hosts once
per hour and deletes them only when **all safety guards pass**. The process is **disabled by default**.

#### Dry run (no Azure credentials required for WhatIf output)

```powershell
./scripts/Invoke-AvdAutoRetirement.ps1 `
  -HostPoolName hp-avd-prod `
  -ResourceGroupName rg-avd-controlplane-prod `
  -GenerationName g2407 `
  -SessionHostResourceGroupName rg-avd-sh-g2407 `
  -ReplacementGenerationValidationMarker g2408 `
  -EnableAutomaticRetirement `
  -WhatIf
```

#### Live run (operator-initiated, after 30 hours)

```powershell
./scripts/Invoke-AvdAutoRetirement.ps1 `
  -HostPoolName hp-avd-prod `
  -ResourceGroupName rg-avd-controlplane-prod `
  -GenerationName g2407 `
  -SessionHostResourceGroupName rg-avd-sh-g2407 `
  -ReplacementGenerationValidationMarker g2408 `
  -EnableAutomaticRetirement `
  -DeleteNetworkInterfaces `
  -DeleteManagedDisks `
  -MaxDeletionsPerRun 10 `
  -Confirm
```

#### Scheduled Azure Automation runbook

Deploy the Automation Account with Terraform or Bicep (see IaC reference) and assign the managed
identity the RBAC roles listed below. The runbook passes `-UseAutomationManagedIdentity` automatically.

#### Required RBAC permissions for the Automation Account managed identity

| Scope | Role | Purpose |
| --- | --- | --- |
| Session host resource group | `Virtual Machine Contributor` | Read, delete VMs |
| Session host resource group | `Network Contributor` | Read, delete NICs |
| Session host resource group | `Disk Snapshot Contributor` or `Contributor` | Read, delete managed disks |
| Control-plane resource group | `Desktop Virtualization Session Host Operator` | Read/update drain mode |
| Control-plane resource group | `Desktop Virtualization Contributor` | Remove session host registrations |
| Session host resource group | `Tag Contributor` | Read VM tags written by drain script |

#### Kill switch

Pass `-KillSwitch` to exit immediately without deleting anything. This overrides
`-EnableAutomaticRetirement` and is safe to use at any time.

```powershell
./scripts/Invoke-AvdAutoRetirement.ps1 ... -KillSwitch
```

#### Cancelling automatic retirement

To cancel retirement before the retention period elapses:

1. Remove the `AVDAutoDelete` tag from the VM, or set it to `false`.
2. Alternatively, re-enable the session host for new sessions:

   ```powershell
   ./scripts/Set-AvdGenerationDrainMode.ps1 -HostPoolName hp-avd-prod -ResourceGroupName rg-avd-controlplane-prod -GenerationName g2407 -EnableNewSessions
   ```

## 11. Remove stale AVD registrations

```powershell
./scripts/Remove-AvdRetiredSessionHostRegistrations.ps1   -HostPoolName hp-avd-prod   -ResourceGroupName rg-avd-controlplane-prod   -GenerationName g2407   -SessionHostResourceGroupName rg-avd-sh-g2407   -Force -Confirm
```

> The automated retirement script removes AVD registrations as part of its deletion sequence,
> so this step is only needed for manual retirement or cleanup after partial failures.

## 12. Terraform state considerations

Automated deletion of VMs, NICs, and disks occurs **outside Terraform state**. After the
retirement runbook completes:

- The resources are deleted from Azure but still appear in the old generation state file.
- Run `terraform state rm` for each deleted resource, or destroy the old generation state
  entirely with `terraform destroy` (it will find nothing to delete if resources are already gone).
- Alternatively, use a **generation-per-resource-group** model: once all hosts in a resource group
  are retired, delete the resource group and discard the old state file.

## 13. Roll back if necessary

1. Re-enable the previous generation for new sessions.
2. Drain the failed new generation.
3. Stop/deallocate or remove the failed new generation only after confirming users are safe.
4. Keep the gallery image version pin and state/deployment boundaries intact so rollback remains deterministic.
