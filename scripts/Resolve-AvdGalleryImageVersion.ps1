[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory)]
  [string]$GalleryName,

  [Parameter(Mandatory)]
  [string]$ImageDefinitionName,

  [string]$SubscriptionId,

  [string]$Location,

  [string]$RequiredTagName,

  [string]$RequiredTagValue,

  [ValidateSet('Terraform', 'Bicep', 'Json', 'Plain')]
  [string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($SubscriptionId) {
  Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null
}

$versions = Get-AzGalleryImageVersion -ResourceGroupName $ResourceGroupName -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinitionName

if ($Location) {
  $versions = $versions | Where-Object {
    $_.PublishingProfile.TargetRegions.Name -contains $Location
  }
}

if ($RequiredTagName) {
  $versions = $versions | Where-Object {
    $_.Tags.ContainsKey($RequiredTagName) -and $_.Tags[$RequiredTagName] -eq $RequiredTagValue
  }
}

$selected = $versions |
  Sort-Object -Property @{ Expression = { $_.PublishingProfile.PublishedDate } ; Descending = $true }, @{ Expression = { $_.Name } ; Descending = $true } |
  Select-Object -First 1

if (-not $selected) {
  throw 'No Azure Compute Gallery image version matched the supplied filters.'
}

$result = [pscustomobject]@{
  Name        = $selected.Name
  Id          = $selected.Id
  Location    = $selected.Location
  Published   = $selected.PublishingProfile.PublishedDate
  ExcludeFromLatest = $selected.PublishingProfile.ExcludeFromLatest
}

switch ($OutputFormat) {
  'Terraform' { 'gallery_image_version_id = "{0}"' -f $selected.Id }
  'Bicep'     { '{"galleryImageVersionId":{"value":"{0}"}}' -f $selected.Id }
  'Plain'     { $selected.Id }
  default     { $result | ConvertTo-Json -Depth 5 }
}
