targetScope = 'resourceGroup'

param location string = resourceGroup().location
param createHostPool bool = false
param hostPoolName string
@allowed([
  'Pooled'
  'Personal'
])
param hostPoolType string = 'Pooled'
@allowed([
  'BreadthFirst'
  'DepthFirst'
  'Persistent'
])
param loadBalancerType string = 'DepthFirst'
param desktopApplicationGroupName string = ''
param workspaceName string = ''
param generationName string
param hostNamePrefix string
@minValue(1)
@maxValue(100)
param sessionHostCount int
@minValue(1)
param startHostNumber int = 1
param subnetId string
param vmSize string
param adminUsername string
@secure()
param adminPassword string
param registrationTokenExpirationUtc string
@allowed([
  'gallery'
  'marketplace'
])
param imageSourceType string = 'gallery'
param galleryImageVersionId string = ''
param marketplaceImage object = {
  publisher: ''
  offer: ''
  sku: ''
  version: ''
}
param availabilityZones array = []
param acceleratedNetworking bool = true
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'
param secureBootEnabled bool = true
param vtpmEnabled bool = true
param osDisk object = {
  storageAccountType: 'Premium_LRS'
  caching: 'ReadWrite'
  diskSizeGB: 128
}
param enableBootDiagnostics bool = true
param bootDiagnosticsStorageAccountUri string = ''
@allowed([
  'None'
  'SystemAssigned'
  'UserAssigned'
  'SystemAssigned, UserAssigned'
])
param managedIdentityType string = 'SystemAssigned'
param userAssignedIdentities object = {}
@allowed([
  'none'
  'entra'
  'ad'
])
param joinType string = 'none'
param domainJoinSettings object = {
  domainName: ''
  ouPath: ''
  userPrincipalName: ''
  restart: true
  options: 3
}
@secure()
param domainJoinPassword string = ''
@secure()
param existingHostPoolRegistrationToken string = ''
param customScript object = {
  enabled: false
  fileUris: []
  commandToExecute: ''
}
param tags object = {}

module hostPool './modules/hostPool.bicep' = if (createHostPool) {
  name: 'hostPool-${uniqueString(resourceGroup().id, hostPoolName)}'
  params: {
    location: location
    hostPoolName: hostPoolName
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    desktopApplicationGroupName: desktopApplicationGroupName
    workspaceName: workspaceName
    registrationTokenExpirationUtc: registrationTokenExpirationUtc
    tags: tags
  }
}

var hostPoolRegistrationToken = createHostPool ? hostPool.outputs.hostPoolRegistrationToken : existingHostPoolRegistrationToken

module sessionHostGeneration './modules/sessionHostGeneration.bicep' = {
  name: 'generation-${generationName}-${uniqueString(resourceGroup().id, generationName)}'
  params: {
    location: location
    hostPoolName: hostPoolName
    hostPoolRegistrationToken: hostPoolRegistrationToken
    generationName: generationName
    hostNamePrefix: hostNamePrefix
    sessionHostCount: sessionHostCount
    startHostNumber: startHostNumber
    subnetId: subnetId
    vmSize: vmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageSourceType: imageSourceType
    galleryImageVersionId: galleryImageVersionId
    marketplaceImage: marketplaceImage
    availabilityZones: availabilityZones
    acceleratedNetworking: acceleratedNetworking
    securityType: securityType
    secureBootEnabled: secureBootEnabled
    vtpmEnabled: vtpmEnabled
    osDisk: osDisk
    enableBootDiagnostics: enableBootDiagnostics
    bootDiagnosticsStorageAccountUri: bootDiagnosticsStorageAccountUri
    managedIdentityType: managedIdentityType
    userAssignedIdentities: userAssignedIdentities
    joinType: joinType
    domainJoinSettings: domainJoinSettings
    domainJoinPassword: domainJoinPassword
    customScript: customScript
    tags: tags
  }
}

output generationName string = generationName
output hostPoolId string = createHostPool ? hostPool.outputs.hostPoolId : resourceId('Microsoft.DesktopVirtualization/hostPools', hostPoolName)
output sessionHostNames array = sessionHostGeneration.outputs.sessionHostNames
output sessionHostIds array = sessionHostGeneration.outputs.sessionHostIds
output networkInterfaceIds array = sessionHostGeneration.outputs.networkInterfaceIds
output imageReference object = imageSourceType == 'gallery' ? {
  type: 'gallery'
  galleryImageVersionId: galleryImageVersionId
} : {
  type: 'marketplace'
  publisher: marketplaceImage.publisher
  offer: marketplaceImage.offer
  sku: marketplaceImage.sku
  version: marketplaceImage.version
}
