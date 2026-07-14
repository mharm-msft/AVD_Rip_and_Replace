# Terraform and Bicep reference

## Terraform highlights

| Variable | Description |
| --- | --- |
| `create_host_pool` | Creates the AVD host pool, desktop application group, and workspace when `true`; otherwise attaches to an existing host pool. |
| `existing_host_pool_id` / `existing_host_pool_name` | Required for later generations when `create_host_pool = false`. |
| `generation_name` | Generation or release identifier used in deterministic naming and tags. |
| `host_name_prefix` | Short prefix used in the Windows computer name. Keep the generated host name at or below 15 characters. |
| `start_host_number` | Starting host number for the new generation. |
| `session_host_count` | Number of new hosts to create. Valid range: **1-100**. |
| `registration_token_expiration_utc` | RFC3339 UTC expiration for the short-lived host-pool registration token. |
| `image_source` | Either a pinned gallery image version ID or a pinned marketplace image reference. |
| `domain_join` | `none`, `entra`, or `ad`; traditional AD join requires secure credentials. |
| `custom_script` | Optional post-deployment validation or final-configuration script settings. |
| `managed_identity` | Managed identity type and optional user-assigned identity IDs. |
| `availability_zones` | Optional list of zones used in round-robin order. |

### Automated retirement variables (opt-in)

| Variable | Default | Description |
| --- | --- | --- |
| `enable_retirement_automation` | `false` | Deploy the Automation Account and runbook. Must be `true` to use automated retirement. |
| `retirement_automation_account_name` | `null` | Name of the Azure Automation Account. Required when `enable_retirement_automation = true`. |
| `retirement_automation_resource_group_name` | `null` | Resource group for the Automation Account. Defaults to `control_plane_resource_group_name`. |
| `enable_automatic_retirement` | `false` | Opt-in gate: activates the scheduled runbook. Must be explicitly `true`. |
| `retirement_generation_name` | `null` | Old generation to retire (e.g. `g2407`). Defaults to `generation_name`. |
| `retirement_session_host_resource_group_name` | `null` | RG containing the VMs to retire. Defaults to `session_host_resource_group_name`. |
| `replacement_generation_validation_marker` | `null` | Explicit approval marker for the new generation (e.g. `g2408`). Required when retiring. |
| `drain_retention_hours` | `30` | Hours a host must remain in drain mode before deletion. Range: 1-720. |
| `retirement_delete_network_interfaces` | `false` | When `true`, deletes NICs after the VM is removed. |
| `retirement_delete_managed_disks` | `false` | When `true`, deletes the managed OS disk after the VM is removed. |
| `retirement_max_deletions_per_run` | `10` | Maximum VMs deleted per runbook execution. Range: 1-100. |
| `retirement_schedule_frequency_hours` | `1` | Runbook schedule frequency in hours. Range: 1-24. |

## Bicep highlights

| Parameter | Description |
| --- | --- |
| `createHostPool` | Creates the host pool control-plane resources when `true`; otherwise uses an existing host pool. |
| `existingHostPoolRegistrationToken` | Secure parameter required for existing-host-pool deployments. |
| `generationName` | Generation or release identifier used in deterministic naming and tags. |
| `hostNamePrefix` | Short prefix used in the Windows computer name. Keep the generated host name at or below 15 characters. |
| `startHostNumber` | Starting host number for the new generation. |
| `sessionHostCount` | Number of new hosts to create. Valid range: **1-100**. |
| `registrationTokenExpirationUtc` | UTC expiration used when the template creates or refreshes a host-pool registration token. |
| `imageSourceType` / `galleryImageVersionId` / `marketplaceImage` | Immutable image reference inputs. `latest` is rejected for marketplace versions. |
| `joinType` / `domainJoinSettings` / `domainJoinPassword` | Entra ID sign-in or traditional AD join settings. |
| `customScript` | Optional post-deployment validation or final-configuration hook. |
| `managedIdentityType` / `userAssignedIdentities` | Managed identity settings for the session hosts. For user-assigned identities, pass the ARM-style object map of identity resource IDs to empty objects. |
| `availabilityZones` | Optional list of zones used in round-robin order. |

### Bicep retirement automation parameters (`retirementAutomation.bicep`)

| Parameter | Default | Description |
| --- | --- | --- |
| `automationAccountName` | required | Name of the Azure Automation Account. |
| `enableAutomaticRetirement` | `false` | Opt-in gate: activates the scheduled runbook. |
| `hostPoolName` | required | AVD host pool name. |
| `hostPoolResourceGroupName` | required | Resource group containing the host pool. |
| `generationName` | required | Old generation to retire (e.g. `g2407`). |
| `sessionHostResourceGroupName` | required | RG containing the session host VMs. |
| `replacementGenerationValidationMarker` | required | Explicit approval marker for the new generation. |
| `drainRetentionHours` | `30` | Hours in drain mode required before deletion. Range: 1-720. |
| `deleteNetworkInterfaces` | `false` | Delete NICs after VM removal. |
| `deleteManagedDisks` | `false` | Delete managed OS disks after VM removal. |
| `maxDeletionsPerRun` | `10` | Maximum VMs deleted per runbook execution. Range: 1-100. |
| `scheduleFrequencyHours` | `1` | Schedule frequency in hours. Range: 1-24. |

## Naming and idempotency

Both implementations generate names using this format:

```text
{hostNamePrefix}-{generationName}-{NNN}
```

Examples:

- `avd-g2407-101`
- `avd-g2408-001`

Using a new `generationName` and `startHostNumber` for each rollout guarantees deterministic, non-colliding host names while keeping old and new generations independently manageable.

## VM retirement tags

The updated `Set-AvdGenerationDrainMode.ps1` script writes the following tags to the backing VMs
when entering drain mode. These tags are the source of truth for the retirement eligibility check.

| Tag | Description |
| --- | --- |
| `AVDDrainMode` | Set to `true` when drain mode is applied. |
| `AVDDrainStartedAt` | UTC ISO-8601 timestamp of when drain mode was first applied. Preserved on re-runs unless `-ResetDrainTimestamp` is passed. |
| `AVDGeneration` | Generation name used to scope the retirement operation. |
| `AVDAutoDelete` | `true` if the VM is opted in to automatic deletion; `false` otherwise. Only set to `true` when `-TagAutoDelete` is passed to the drain script. |
