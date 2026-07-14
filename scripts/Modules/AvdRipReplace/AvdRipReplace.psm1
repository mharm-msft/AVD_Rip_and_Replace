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
      Where-Object { $_.Tags['avd.generation'] -eq $GenerationName }

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

Export-ModuleMember -Function @(
  'Get-AvdGenerationHostPattern',
  'Get-AvdShortHostName',
  'Get-AvdGenerationSessionHostRecord'
)
