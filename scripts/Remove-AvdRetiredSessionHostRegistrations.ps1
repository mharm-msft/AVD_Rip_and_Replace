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

  [switch]$Force
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

foreach ($sessionHostRecord in $hosts) {
  $hasBackingVm = -not [string]::IsNullOrWhiteSpace($sessionHostRecord.VmId)
  if ($hasBackingVm -and -not $Force.IsPresent) {
    Write-Warning ("Skipping {0} because backing VM {1} still exists. Use -Force after infrastructure is intentionally retired." -f $sessionHostRecord.SessionHostName, $sessionHostRecord.VmName)
    continue
  }

  if ($PSCmdlet.ShouldProcess($sessionHostRecord.SessionHostName, 'Remove AVD session host registration')) {
    Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $sessionHostRecord.SessionHostName -Force | Out-Null
  }
}
