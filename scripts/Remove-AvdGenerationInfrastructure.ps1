[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GenerationName,

  [switch]$DeleteDetachedOsDisks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$generationVms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status |
  Where-Object { $_.Tags['avd.generation'] -eq $GenerationName }

$generationNics = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName |
  Where-Object { $_.Tags['avd.generation'] -eq $GenerationName }

if (-not $generationVms -and -not $generationNics) {
  throw "No generation-tagged infrastructure was found in resource group '$ResourceGroupName' for generation '$GenerationName'."
}

foreach ($vm in $generationVms) {
  if ($PSCmdlet.ShouldProcess($vm.Name, 'Delete session host virtual machine')) {
    Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Force
  }

  if ($DeleteDetachedOsDisks.IsPresent -and $vm.StorageProfile.OsDisk.ManagedDisk.Id) {
    $diskName = ($vm.StorageProfile.OsDisk.ManagedDisk.Id -split '/')[-1]
    if ($PSCmdlet.ShouldProcess($diskName, 'Delete detached OS disk')) {
      Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $diskName -Force
    }
  }
}

foreach ($nic in $generationNics) {
  if ($nic.VirtualMachine) {
    Write-Warning ("Skipping NIC {0} because it is still attached to a virtual machine." -f $nic.Name)
    continue
  }

  if ($PSCmdlet.ShouldProcess($nic.Name, 'Delete session host NIC')) {
    Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nic.Name -Force
  }
}
