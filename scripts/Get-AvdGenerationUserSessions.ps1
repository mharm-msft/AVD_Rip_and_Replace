[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)]
  [string]$HostPoolName,

  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GenerationName,

  [string]$HostNamePrefix,

  [switch]$ForceLogoff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/AvdRipReplace/AvdRipReplace.psm1') -Force

$pattern = Get-AvdGenerationHostPattern -GenerationName $GenerationName -HostNamePrefix $HostNamePrefix
$sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName
$targetHostNames = $sessionHosts |
  Where-Object { (Get-AvdShortHostName -SessionHostName $_.Name) -match $pattern } |
  Select-Object -ExpandProperty Name

$userSessions = foreach ($hostName in $targetHostNames) {
  Get-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -SessionHostName $hostName |
    Select-Object @{ Name = 'SessionHostName' ; Expression = { $hostName } }, *, @{ Name = 'Generation' ; Expression = { $GenerationName } }
}

$userSessions | Sort-Object SessionHostName, Id

if ($ForceLogoff.IsPresent) {
  if (-not $userSessions) {
    Write-Information 'No user sessions matched the requested generation.' -InformationAction Continue
    return
  }

  foreach ($session in $userSessions) {
    $target = '{0} session {1}' -f $session.SessionHostName, $session.Id
    if ($PSCmdlet.ShouldProcess($target, 'Log off user session')) {
      Remove-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -SessionHostName $session.SessionHostName -Id $session.Id -Force | Out-Null
    }
  }
}
