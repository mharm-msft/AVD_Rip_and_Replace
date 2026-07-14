Set-StrictMode -Version Latest

function Get-AvdGenerationHostPattern {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$GenerationName,

    [string]$HostNamePrefix
  )

  $prefix = if ([string]::IsNullOrWhiteSpace($HostNamePrefix)) {
    '[a-z0-9-]+'
  }
  else {
    [Regex]::Escape($HostNamePrefix)
  }

  return ('^{0}-{1}-\d{{3}}(\..+)?$' -f $prefix, [Regex]::Escape($GenerationName))
}

function Get-AvdShortHostName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$SessionHostName
  )

  $leaf = ($SessionHostName -split '/')[-1]
  return ($leaf -split '\.')[0]
}

function Get-AvdGenerationSessionHostRecord {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$HostPoolName,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$GenerationName,

    [string]$HostNamePrefix,

    [string]$SessionHostResourceGroupName
  )

  $pattern = Get-AvdGenerationHostPattern -GenerationName $GenerationName -HostNamePrefix $HostNamePrefix
  $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName
  $generationHosts = foreach ($sessionHost in $sessionHosts) {
    $shortName = Get-AvdShortHostName -SessionHostName $sessionHost.Name
    if ($shortName -match $pattern) {
      [pscustomobject]@{
        SessionHost = $sessionHost
        ShortName   = $shortName
      }
    }
  }

  $vmIndex = @{}
  if (-not [string]::IsNullOrWhiteSpace($SessionHostResourceGroupName)) {
    $vmCandidates = Get-AzVM -ResourceGroupName $SessionHostResourceGroupName -Status -ErrorAction Stop |
      Where-Object { $_ -and $_.Tags['avd.generation'] -eq $GenerationName }

    foreach ($vm in $vmCandidates) {
      $vmIndex[$vm.Name.ToLowerInvariant()] = $vm
    }
  }

  foreach ($record in $generationHosts) {
    $vm = $null
    $vmIndex.TryGetValue($record.ShortName.ToLowerInvariant(), [ref]$vm) | Out-Null

    [pscustomobject]@{
      Generation      = $GenerationName
      SessionHostName = $record.SessionHost.Name
      ShortName       = $record.ShortName
      Status          = $record.SessionHost.Status
      AllowNewSession = $record.SessionHost.AllowNewSession
      ResourceId      = $record.SessionHost.Id
      VmName          = $vm?.Name
      VmId            = $vm?.Id
      VmPowerState    = $vm?.Statuses[-1]?.DisplayStatus
      ResourceGroup   = $SessionHostResourceGroupName
    }
  }
}

function Test-AvdHostRetirementEligibility {
  <#
  .SYNOPSIS
    Evaluates whether a single AVD session host is eligible for automated retirement.
  .DESCRIPTION
    Returns a PSCustomObject with IsEligible (bool) and SkipReason (string or $null).
    All eligibility data is passed as parameters so the function is testable without
    live Azure API calls.
  #>
  [CmdletBinding()]
  [OutputType([pscustomobject])]
  param(
    [Parameter(Mandatory)]
    [bool]$AllowNewSession,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ReplacementGenerationValidationMarker,

    [Parameter(Mandatory)]
    [ValidateRange(1, 720)]
    [int]$DrainRetentionHours,

    [Parameter(Mandatory)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$ActiveAndDisconnectedSessionCount,

    [Parameter(Mandatory)]
    [bool]$ForceLogoff,

    [hashtable]$VmTags = @{},

    [datetime]$NowUtc = [datetime]::UtcNow
  )

  # Guard 1: drain mode enabled in AVD
  if ($AllowNewSession) {
    return [pscustomobject]@{ IsEligible = $false; SkipReason = 'Session host is not in drain mode (AllowNewSession is true)' }
  }

  # Guard 2: AVDAutoDelete tag must be 'true'
  if ($VmTags['AVDAutoDelete'] -ne 'true') {
    return [pscustomobject]@{ IsEligible = $false; SkipReason = "AVDAutoDelete tag is not set to 'true'" }
  }

  # Guard 3: AVDDrainStartedAt must exist and be a valid timestamp
  $drainStartedAtStr = $VmTags['AVDDrainStartedAt']
  if ([string]::IsNullOrWhiteSpace($drainStartedAtStr)) {
    return [pscustomobject]@{ IsEligible = $false; SkipReason = 'AVDDrainStartedAt tag is missing or empty' }
  }

  $drainStartedAtOffset = [datetimeoffset]::MinValue
  if (-not [datetimeoffset]::TryParse($drainStartedAtStr, [ref]$drainStartedAtOffset)) {
    return [pscustomobject]@{ IsEligible = $false; SkipReason = "AVDDrainStartedAt tag value '$drainStartedAtStr' is not a valid ISO-8601 timestamp" }
  }

  # Guard 4: retention period elapsed
  $drainStartedAtUtc = $drainStartedAtOffset.UtcDateTime
  $elapsedHours = ($NowUtc - $drainStartedAtUtc).TotalHours
  if ($elapsedHours -lt $DrainRetentionHours) {
    $remaining = [Math]::Round($DrainRetentionHours - $elapsedHours, 1)
    return [pscustomobject]@{
      IsEligible = $false
      SkipReason = ('Drain retention period not elapsed ({0:F1}h elapsed of {1}h required; {2}h remaining)' -f $elapsedHours, $DrainRetentionHours, $remaining)
    }
  }

  # Guard 5: explicit replacement generation validation marker
  if ([string]::IsNullOrWhiteSpace($ReplacementGenerationValidationMarker)) {
    return [pscustomobject]@{ IsEligible = $false; SkipReason = 'ReplacementGenerationValidationMarker must be explicitly specified' }
  }

  # Guard 6: no blocking sessions (unless ForceLogoff)
  if ($ActiveAndDisconnectedSessionCount -gt 0 -and -not $ForceLogoff) {
    return [pscustomobject]@{
      IsEligible = $false
      SkipReason = "Host has $ActiveAndDisconnectedSessionCount active/disconnected session(s); use -ForceLogoff to override"
    }
  }

  return [pscustomobject]@{ IsEligible = $true; SkipReason = $null }
}

Export-ModuleMember -Function @(
  'Get-AvdGenerationHostPattern',
  'Get-AvdShortHostName',
  'Get-AvdGenerationSessionHostRecord',
  'Test-AvdHostRetirementEligibility'
)
