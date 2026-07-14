[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$HostPoolName,

  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GenerationName,

  [int]$ExpectedCount,

  [string]$HostNamePrefix,

  [string]$SessionHostResourceGroupName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/AvdRipReplace/AvdRipReplace.psm1') -Force

$hosts = Get-AvdGenerationSessionHostRecord `
  -HostPoolName $HostPoolName `
  -ResourceGroupName $ResourceGroupName `
  -GenerationName $GenerationName `
  -HostNamePrefix $HostNamePrefix `
  -SessionHostResourceGroupName $SessionHostResourceGroupName

if (-not $hosts) {
  throw "No session hosts were found for generation '$GenerationName'."
}

if ($PSBoundParameters.ContainsKey('ExpectedCount') -and $hosts.Count -ne $ExpectedCount) {
  throw "Expected $ExpectedCount session hosts, but found $($hosts.Count)."
}

$notReady = $hosts | Where-Object {
  $_.Status -ne 'Available' -or $_.AllowNewSession -ne $true
}

$hosts | Sort-Object ShortName | Format-Table -AutoSize

if ($notReady) {
  throw ('Generation {0} is not ready. Non-ready hosts: {1}' -f $GenerationName, (($notReady.ShortName | Sort-Object) -join ', '))
}

Write-Information ('Generation {0} is ready with {1} available session hosts.' -f $GenerationName, $hosts.Count) -InformationAction Continue
