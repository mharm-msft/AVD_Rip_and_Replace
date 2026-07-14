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

## Naming and idempotency

Both implementations generate names using this format:

```text
{hostNamePrefix}-{generationName}-{NNN}
```

Examples:

- `avd-g2407-101`
- `avd-g2408-001`

Using a new `generationName` and `startHostNumber` for each rollout guarantees deterministic, non-colliding host names while keeping old and new generations independently manageable.
