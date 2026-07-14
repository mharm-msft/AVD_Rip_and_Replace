[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)]
  [string]$HostPoolName,

  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GenerationName,

  [string]$HostNamePrefix,

  [string]$SessionHostResourceGroupName,

  [switch]$EnableNewSessions,

  [switch]$TagAutoDelete,

  [switch]$ResetDrainTimestamp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/AvdRipReplace/AvdRipReplace.psm1') -Force

$allowNewSession = $EnableNewSessions.IsPresent
$hosts = Get-AvdGenerationSessionHostRecord `
  -HostPoolName $HostPoolName `
  -ResourceGroupName $ResourceGroupName `
  -GenerationName $GenerationName `
  -HostNamePrefix $HostNamePrefix `
  -SessionHostResourceGroupName $SessionHostResourceGroupName

if (-not $hosts) {
  throw "No session hosts were found for generation '$GenerationName'."
}

foreach ($sessionHostRecord in $hosts) {
  if ($PSCmdlet.ShouldProcess($sessionHostRecord.SessionHostName, (if ($allowNewSession) { 'Enable new sessions' } else { 'Disable new sessions (drain mode)' }))) {
    Update-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $sessionHostRecord.SessionHostName -AllowNewSession:$allowNewSession | Out-Null
  }

  # Tag backing VMs with drain retirement metadata when entering drain mode.
  # Requires SessionHostResourceGroupName so VMs can be located.
  if (-not $allowNewSession -and -not [string]::IsNullOrWhiteSpace($SessionHostResourceGroupName) -and $sessionHostRecord.VmId) {
    $vm = Get-AzVM -ResourceGroupName $SessionHostResourceGroupName -Name $sessionHostRecord.VmName -ErrorAction SilentlyContinue
    if ($vm) {
      $existingTags = $vm.Tags
      if ($null -eq $existingTags) { $existingTags = @{} }

      # Preserve existing drain-start timestamp on idempotent re-runs unless the operator
      # explicitly requests a reset.  This prevents accidentally shortening the retention window.
      $drainStartedAt = $existingTags['AVDDrainStartedAt']
      if ([string]::IsNullOrWhiteSpace($drainStartedAt) -or $ResetDrainTimestamp.IsPresent) {
        $drainStartedAt = [datetime]::UtcNow.ToString('o')
      }

      $updatedTags = $existingTags.Clone()
      $updatedTags['AVDDrainMode']      = 'true'
      $updatedTags['AVDDrainStartedAt'] = $drainStartedAt
      $updatedTags['AVDGeneration']     = $GenerationName
      $updatedTags['AVDAutoDelete']     = if ($TagAutoDelete.IsPresent) { 'true' } else { 'false' }

      $action = if ($ResetDrainTimestamp.IsPresent -or [string]::IsNullOrWhiteSpace($existingTags['AVDDrainStartedAt'])) {
        "Tag VM with drain metadata (drain started $drainStartedAt, AVDAutoDelete=$($updatedTags['AVDAutoDelete']))"
      }
      else {
        "Update VM drain tags (preserving existing drain timestamp $drainStartedAt, AVDAutoDelete=$($updatedTags['AVDAutoDelete']))"
      }

      if ($PSCmdlet.ShouldProcess($vm.Name, $action)) {
        Update-AzTag -ResourceId $vm.Id -Tag $updatedTags -Operation Merge | Out-Null
        Write-Verbose ("Tagged $($vm.Name): AVDDrainStartedAt=$drainStartedAt  AVDAutoDelete=$($updatedTags['AVDAutoDelete'])")
      }
    }
    else {
      Write-Warning "Session host '$($sessionHostRecord.SessionHostName)' backing VM '$($sessionHostRecord.VmName)' was not found in resource group '$SessionHostResourceGroupName'; skipping tag update."
    }
  }
}

