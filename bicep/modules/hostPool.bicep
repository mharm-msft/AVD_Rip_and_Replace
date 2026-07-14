param location string
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
param friendlyName string = hostPoolName
param description string = 'AVD rip-and-replace host pool'
param maximumSessionsAllowed int = 16
param startVmOnConnect bool = false
param validateEnvironment bool = false
param customRdpProperties string = ''
param desktopApplicationGroupName string
param desktopApplicationGroupFriendlyName string = desktopApplicationGroupName
param workspaceName string
param workspaceFriendlyName string = workspaceName
param workspaceDescription string = 'Workspace for AVD rip-and-replace deployments'
param registrationTokenExpirationUtc string
param tags object = {}

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-03' = {
  name: hostPoolName
  location: location
  tags: tags
  properties: {
    friendlyName: friendlyName
    description: description
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    maxSessionLimit: hostPoolType == 'Pooled' ? maximumSessionsAllowed : null
    startVMOnConnect: startVmOnConnect
    validationEnvironment: validateEnvironment
    preferredAppGroupType: 'Desktop'
    customRdpProperty: empty(customRdpProperties) ? null : customRdpProperties
    registrationInfo: {
      expirationTime: registrationTokenExpirationUtc
      registrationTokenOperation: 'Update'
    }
  }
}

resource desktopApplicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2024-04-03' = {
  name: desktopApplicationGroupName
  location: location
  tags: tags
  properties: {
    friendlyName: desktopApplicationGroupFriendlyName
    description: 'Desktop application group for ${hostPoolName}'
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
  }
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-03' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    friendlyName: workspaceFriendlyName
    description: workspaceDescription
    applicationGroupReferences: [
      desktopApplicationGroup.id
    ]
  }
}

output hostPoolId string = hostPool.id
output hostPoolName string = hostPool.name
output hostPoolRegistrationToken string = hostPool.properties.registrationInfo.token
