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

  [switch]$EnableNewSessions
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
}
