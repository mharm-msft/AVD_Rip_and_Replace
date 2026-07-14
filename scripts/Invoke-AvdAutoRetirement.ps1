<#
.SYNOPSIS
  Automated, opt-in retirement of AVD session hosts that have been in drain mode for a
  configurable retention period.

.DESCRIPTION
  Discovers eligible drained AVD session hosts for a given generation, verifies all safety
  guards, and retires them (VM, optionally NIC and managed disk, then AVD registration).

  SAFETY DEFAULTS:
  - Automatic retirement is DISABLED by default.  Pass -EnableAutomaticRetirement to opt in.
  - Default retention period is 30 hours from the drain-start timestamp on the backing VM.
  - Hosts with active or disconnected sessions are skipped unless -ForceLogoff is provided.
  - A maximum of 10 VMs are deleted per run (configure with -MaxDeletionsPerRun, max 100).
  - NIC and managed-disk deletion are disabled by default (conservative).
  - A global -KillSwitch exits immediately without deleting anything.
  - Full WhatIf/ShouldProcess support.

  ELIGIBILITY REQUIREMENTS (all must be met):
  1. Session host belongs to the specified host pool and generation name.
  2. AVD drain mode is currently enabled (AllowNewSession = false).
  3. Backing VM has AVDAutoDelete tag set to 'true'.
  4. Backing VM has a valid AVDDrainStartedAt UTC timestamp tag.
  5. Time elapsed since drain start >= DrainRetentionHours.
  6. ReplacementGenerationValidationMarker parameter explicitly provided.
  7. Zero active AND disconnected sessions (unless -ForceLogoff).

  RESOURCE DELETION ORDER (per host):
  1. Force-log off any remaining sessions (only when -ForceLogoff).
  2. Delete the Azure VM.
  3. Delete the NIC (only when -DeleteNetworkInterfaces and NIC is detached).
  4. Delete the managed OS disk (only when -DeleteManagedDisks and disk is detached).
  5. Remove the AVD session-host registration.

.PARAMETER HostPoolName
  Name of the AVD host pool.

.PARAMETER ResourceGroupName
  Resource group that contains the AVD host pool (control-plane RG).

.PARAMETER GenerationName
  Generation identifier of the old hosts to retire, e.g. g2407.

.PARAMETER SessionHostResourceGroupName
  Resource group that contains the session host VMs to be retired.

.PARAMETER ReplacementGenerationValidationMarker
  An explicit string that confirms the replacement generation is approved and ready,
  for example the new generation name 'g2408' or an approval ticket number.
  The script does NOT infer readiness from VM age or image version alone.

.PARAMETER HostNamePrefix
  Optional host name prefix used to narrow the session host pattern match.

.PARAMETER DrainRetentionHours
  Minimum hours a host must have been in drain mode before it is eligible for deletion.
  Default: 30.  Valid range: 1-720.

.PARAMETER EnableAutomaticRetirement
  Must be supplied explicitly to permit any deletion.  Disabled by default as a safety gate.

.PARAMETER DeleteNetworkInterfaces
  When present, deletes generation-tagged NICs after the VM is removed (only detached NICs).

.PARAMETER DeleteManagedDisks
  When present, deletes the managed OS disk after the VM is removed.

.PARAMETER ForceLogoff
  When present, logs off active and disconnected sessions before deletion.
  Requires ShouldProcess confirmation per session.

.PARAMETER KillSwitch
  Global kill switch.  When present, exits immediately without deleting anything.

.PARAMETER MaxDeletionsPerRun
  Maximum number of VMs to delete in a single run.  Default: 10.  Range: 1-100.

.PARAMETER UseAutomationManagedIdentity
  When present, authenticates to Azure using the managed identity of an Azure Automation
  Account (Connect-AzAccount -Identity).  Use this when running as an Azure Automation runbook.

.EXAMPLE
  # Dry run - see what would be retired
  ./scripts/Invoke-AvdAutoRetirement.ps1 `
      -HostPoolName hp-avd-prod `
      -ResourceGroupName rg-avd-controlplane-prod `
      -GenerationName g2407 `
      -SessionHostResourceGroupName rg-avd-sh-g2407 `
      -ReplacementGenerationValidationMarker g2408 `
      -EnableAutomaticRetirement `
      -WhatIf

.EXAMPLE
  # Live run with session force-logoff and disk cleanup
  ./scripts/Invoke-AvdAutoRetirement.ps1 `
      -HostPoolName hp-avd-prod `
      -ResourceGroupName rg-avd-controlplane-prod `
      -GenerationName g2407 `
      -SessionHostResourceGroupName rg-avd-sh-g2407 `
      -ReplacementGenerationValidationMarker g2408 `
      -EnableAutomaticRetirement `
      -DeleteNetworkInterfaces `
      -DeleteManagedDisks `
      -ForceLogoff `
      -MaxDeletionsPerRun 5 `
      -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)]
  [string]$HostPoolName,

  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GenerationName,

  [Parameter(Mandatory)]
  [string]$SessionHostResourceGroupName,

  [Parameter(Mandatory)]
  [string]$ReplacementGenerationValidationMarker,

  [string]$HostNamePrefix,

  [ValidateRange(1, 720)]
  [int]$DrainRetentionHours = 30,

  [switch]$EnableAutomaticRetirement,

  [switch]$DeleteNetworkInterfaces,

  [switch]$DeleteManagedDisks,

  [switch]$ForceLogoff,

  [switch]$KillSwitch,

  [ValidateRange(1, 100)]
  [int]$MaxDeletionsPerRun = 10,

  [switch]$UseAutomationManagedIdentity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Authenticate when running inside Azure Automation with a managed identity.
if ($UseAutomationManagedIdentity.IsPresent) {
  Write-Output 'Connecting to Azure using managed identity...'
  Connect-AzAccount -Identity | Out-Null
}

Import-Module (Join-Path $PSScriptRoot 'Modules/AvdRipReplace/AvdRipReplace.psm1') -Force

# -------------------------------------------------------------------------
# Global kill switch
# -------------------------------------------------------------------------
if ($KillSwitch.IsPresent) {
  Write-Warning 'KillSwitch is active. Exiting without deleting any resources.'
  return
}

# -------------------------------------------------------------------------
# Opt-in gate
# -------------------------------------------------------------------------
if (-not $EnableAutomaticRetirement.IsPresent) {
  Write-Warning ('Automatic retirement is disabled. Pass -EnableAutomaticRetirement to opt in. ' +
    'Use -WhatIf to preview what would be retired without this flag.')
  return
}

Write-Verbose "Replacement generation validation marker: '$ReplacementGenerationValidationMarker'"
Write-Verbose "Drain retention: $DrainRetentionHours hours | Max deletions per run: $MaxDeletionsPerRun"

# -------------------------------------------------------------------------
# Discover session hosts for the target generation
# -------------------------------------------------------------------------
$hosts = Get-AvdGenerationSessionHostRecord `
  -HostPoolName $HostPoolName `
  -ResourceGroupName $ResourceGroupName `
  -GenerationName $GenerationName `
  -HostNamePrefix $HostNamePrefix `
  -SessionHostResourceGroupName $SessionHostResourceGroupName

if (-not $hosts) {
  Write-Warning "No session hosts found for generation '$GenerationName' in host pool '$HostPoolName'."
  return
}

Write-Verbose "Found $($hosts.Count) session host(s) for generation '$GenerationName'."

# -------------------------------------------------------------------------
# Evaluate each host for eligibility then retire
# -------------------------------------------------------------------------
$deletedCount  = 0
$skippedHosts  = [System.Collections.Generic.List[pscustomobject]]::new()
$retiredHosts  = [System.Collections.Generic.List[pscustomobject]]::new()
$failedHosts   = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($record in $hosts) {
  if ($deletedCount -ge $MaxDeletionsPerRun) {
    $skippedHosts.Add([pscustomobject]@{
        Host   = $record.ShortName
        Reason = "MaxDeletionsPerRun ($MaxDeletionsPerRun) reached for this run"
      })
    continue
  }

  Write-Verbose "Evaluating '$($record.ShortName)'..."

  # ------- Fetch VM tags -------
  $vmTags = @{}
  if ($record.VmId) {
    $vm = Get-AzVM -ResourceGroupName $SessionHostResourceGroupName -Name $record.VmName -ErrorAction SilentlyContinue
    if ($vm -and $vm.Tags) { $vmTags = $vm.Tags }
  }
  else {
    $vm = $null
  }

  # ------- Count active + disconnected sessions -------
  $sessionCount = 0
  $activeSessions = @()
  try {
    $shortName = $record.SessionHostName
    $activeSessions = @(Get-AzWvdUserSession `
      -HostPoolName $HostPoolName `
      -ResourceGroupName $ResourceGroupName `
      -SessionHostName $shortName `
      -ErrorAction Stop |
      Where-Object { $_.SessionState -in @('Active', 'Disconnected') })
    $sessionCount = $activeSessions.Count
  }
  catch {
    Write-Warning "Could not retrieve sessions for '$($record.ShortName)': $_"
  }

  # ------- Test eligibility -------
  $eligibility = Test-AvdHostRetirementEligibility `
    -AllowNewSession ($record.AllowNewSession -eq $true) `
    -ReplacementGenerationValidationMarker $ReplacementGenerationValidationMarker `
    -DrainRetentionHours $DrainRetentionHours `
    -ActiveAndDisconnectedSessionCount $sessionCount `
    -ForceLogoff $ForceLogoff.IsPresent `
    -VmTags $vmTags

  if (-not $eligibility.IsEligible) {
    $skippedHosts.Add([pscustomobject]@{ Host = $record.ShortName; Reason = $eligibility.SkipReason })
    Write-Verbose "Skipping '$($record.ShortName)': $($eligibility.SkipReason)"
    continue
  }

  # ------- Retire this host -------
  Write-Verbose "Host '$($record.ShortName)' is eligible for retirement."

  try {
    # Step 1: Force-logoff any remaining sessions
    if ($ForceLogoff.IsPresent -and $activeSessions.Count -gt 0) {
      foreach ($session in $activeSessions) {
        $sessionTarget = '{0} session {1} (user: {2})' -f $record.ShortName, $session.Id, $session.UserPrincipalName
        if ($PSCmdlet.ShouldProcess($sessionTarget, 'Force log off user session')) {
          Remove-AzWvdUserSession `
            -HostPoolName $HostPoolName `
            -ResourceGroupName $ResourceGroupName `
            -SessionHostName $record.SessionHostName `
            -Id $session.Id `
            -Force | Out-Null
          Write-Verbose "Logged off session $($session.Id) from '$($record.ShortName)'."
        }
      }
    }

    # Step 2: Delete the VM
    if ($vm -and $PSCmdlet.ShouldProcess($record.VmName, 'Delete session host virtual machine')) {
      Remove-AzVM -ResourceGroupName $SessionHostResourceGroupName -Name $record.VmName -Force | Out-Null
      Write-Verbose "Deleted VM '$($record.VmName)'."
    }

    # Step 3: Delete the NIC (only if configured and no longer attached)
    if ($DeleteNetworkInterfaces.IsPresent -and $vm) {
      foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
        $nicName = ($nicRef.Id -split '/')[-1]
        $nic = Get-AzNetworkInterface -ResourceGroupName $SessionHostResourceGroupName -Name $nicName -ErrorAction SilentlyContinue
        if ($nic -and -not $nic.VirtualMachine) {
          if ($PSCmdlet.ShouldProcess($nicName, 'Delete session host NIC')) {
            Remove-AzNetworkInterface -ResourceGroupName $SessionHostResourceGroupName -Name $nicName -Force | Out-Null
            Write-Verbose "Deleted NIC '$nicName'."
          }
        }
        elseif ($nic) {
          Write-Warning "NIC '$nicName' is still attached; skipping deletion."
        }
      }
    }

    # Step 4: Delete the managed OS disk (only if configured)
    if ($DeleteManagedDisks.IsPresent -and $vm -and $vm.StorageProfile.OsDisk.ManagedDisk.Id) {
      $diskName = ($vm.StorageProfile.OsDisk.ManagedDisk.Id -split '/')[-1]
      $disk = Get-AzDisk -ResourceGroupName $SessionHostResourceGroupName -DiskName $diskName -ErrorAction SilentlyContinue
      if ($disk -and $disk.DiskState -in @('Unattached', 'Reserved')) {
        if ($PSCmdlet.ShouldProcess($diskName, 'Delete managed OS disk')) {
          Remove-AzDisk -ResourceGroupName $SessionHostResourceGroupName -DiskName $diskName -Force | Out-Null
          Write-Verbose "Deleted OS disk '$diskName'."
        }
      }
      else {
        Write-Warning "Disk '$diskName' is not in an unattached state (state: $($disk?.DiskState)); skipping deletion."
      }
    }

    # Step 5: Remove the AVD session-host registration
    if ($PSCmdlet.ShouldProcess($record.SessionHostName, 'Remove AVD session host registration')) {
      Remove-AzWvdSessionHost `
        -HostPoolName $HostPoolName `
        -ResourceGroupName $ResourceGroupName `
        -Name $record.SessionHostName `
        -Force | Out-Null
      Write-Verbose "Removed AVD registration for '$($record.SessionHostName)'."
    }

    $retiredHosts.Add([pscustomobject]@{ Host = $record.ShortName; VmName = $record.VmName })
    $deletedCount++
  }
  catch {
    $failedHosts.Add([pscustomobject]@{ Host = $record.ShortName; Error = $_.ToString() })
    Write-Warning "Failed to retire '$($record.ShortName)': $_"
    # One failure does not stop the remaining hosts.
  }
}

# -------------------------------------------------------------------------
# Summary report
# -------------------------------------------------------------------------
Write-Output ''
Write-Output '=== AVD Auto Retirement Run Summary ==='
Write-Output "Generation : $GenerationName"
Write-Output "Host pool  : $HostPoolName"
Write-Output "Evaluated  : $($hosts.Count) host(s)"
Write-Output "Retired    : $($retiredHosts.Count) host(s)"
Write-Output "Skipped    : $($skippedHosts.Count) host(s)"
Write-Output "Failed     : $($failedHosts.Count) host(s)"

if ($retiredHosts.Count -gt 0) {
  Write-Output ''
  Write-Output '-- Retired --'
  $retiredHosts | Format-Table -AutoSize
}

if ($skippedHosts.Count -gt 0) {
  Write-Output ''
  Write-Output '-- Skipped (reason) --'
  $skippedHosts | Format-Table -AutoSize
}

if ($failedHosts.Count -gt 0) {
  Write-Output ''
  Write-Output '-- Failed (partial failure - investigate before re-running) --'
  $failedHosts | Format-Table -AutoSize
  Write-Warning 'One or more hosts failed to retire. See the Failed list above and investigate before re-running.'
}
