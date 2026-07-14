param location string
param hostPoolName string
@secure()
param hostPoolRegistrationToken string
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
param customScript object = {
  enabled: false
  fileUris: []
  commandToExecute: ''
}
param tags object = {}
param avdAgentExtensionVersion string = '1.0'
param avdBootloaderExtensionVersion string = '1.0'

var hostNumbers = [for i in range(0, sessionHostCount): startHostNumber + i]
var hostDefinitions = [for (hostNumber, i) in hostNumbers: {
  vmName: '${hostNamePrefix}-${generationName}-${padLeft(string(hostNumber), 3, '0')}'
  zone: length(availabilityZones) == 0 ? '' : availabilityZones[i % length(availabilityZones)]
}]
var baseTags = union(tags, {
  'avd.generation': generationName
  'avd.hostpool': hostPoolName
  'avd.role': 'session-host'
})
var diagnosticsProfile = enableBootDiagnostics ? {
  bootDiagnostics: empty(bootDiagnosticsStorageAccountUri) ? {
    enabled: true
  } : {
    enabled: true
    storageUri: bootDiagnosticsStorageAccountUri
  }
} : null
var securityProfile = securityType == 'TrustedLaunch' ? {
  securityType: securityType
  uefiSettings: {
    secureBootEnabled: secureBootEnabled
    vTpmEnabled: vtpmEnabled
  }
} : null
var imageReference = imageSourceType == 'gallery' ? {
  id: galleryImageVersionId
} : {
  publisher: marketplaceImage.publisher
  offer: marketplaceImage.offer
  sku: marketplaceImage.sku
  version: marketplaceImage.version
}

resource sessionHostNic 'Microsoft.Network/networkInterfaces@2024-05-01' = [for host in hostDefinitions: {
  name: '${host.vmName}-nic'
  location: location
  tags: baseTags
  properties: {
    enableAcceleratedNetworking: acceleratedNetworking
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}]

resource sessionHostVm 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (host, i) in hostDefinitions: {
  name: host.vmName
  location: location
  tags: baseTags
  zones: empty(host.zone) ? null : [host.zone]
  identity: managedIdentityType == 'None' ? null : {
    type: managedIdentityType
    userAssignedIdentities: userAssignedIdentities
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: securityProfile
    osProfile: {
      computerName: host.vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    storageProfile: {
      imageReference: imageReference
      osDisk: {
        createOption: 'FromImage'
        caching: osDisk.caching
        managedDisk: {
          storageAccountType: osDisk.storageAccountType
        }
        diskSizeGB: osDisk.diskSizeGB
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: sessionHostNic[i].id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: diagnosticsProfile
  }
}]

resource entraLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'entra') {
  name: '${sessionHostVm[i].name}/entraLogin'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {}
  }
}]

resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'ad') {
  name: '${sessionHostVm[i].name}/domainJoin'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      Name: domainJoinSettings.domainName
      OUPath: domainJoinSettings.ouPath
      User: domainJoinSettings.userPrincipalName
      Restart: string(domainJoinSettings.restart)
      Options: string(domainJoinSettings.options)
    }
    protectedSettings: {
      Password: domainJoinPassword
    }
  }
}]

resource avdBootloaderExtensionAd 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'ad') {
  name: '${sessionHostVm[i].name}/avdBootLoader'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgentBootLoader'
    typeHandlerVersion: avdBootloaderExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
  dependsOn: [
    domainJoinExtension[i]
  ]
}]

resource avdBootloaderExtensionEntra 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'entra') {
  name: '${sessionHostVm[i].name}/avdBootLoader'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgentBootLoader'
    typeHandlerVersion: avdBootloaderExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
  dependsOn: [
    entraLoginExtension[i]
  ]
}]

resource avdBootloaderExtensionNone 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'none') {
  name: '${sessionHostVm[i].name}/avdBootLoader'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgentBootLoader'
    typeHandlerVersion: avdBootloaderExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
}]

resource avdAgentExtensionAd 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'ad') {
  name: '${sessionHostVm[i].name}/avdAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgent'
    typeHandlerVersion: avdAgentExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
  dependsOn: [
    avdBootloaderExtensionAd[i]
  ]
}]

resource avdAgentExtensionEntra 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'entra') {
  name: '${sessionHostVm[i].name}/avdAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgent'
    typeHandlerVersion: avdAgentExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
  dependsOn: [
    avdBootloaderExtensionEntra[i]
  ]
}]

resource avdAgentExtensionNone 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (joinType == 'none') {
  name: '${sessionHostVm[i].name}/avdAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.VirtualDesktop'
    type: 'WindowsVirtualDesktopAgent'
    typeHandlerVersion: avdAgentExtensionVersion
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      registrationToken: hostPoolRegistrationToken
    }
  }
  dependsOn: [
    avdBootloaderExtensionNone[i]
  ]
}]

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (host, i) in hostDefinitions: if (bool(customScript.enabled)) {
  name: '${sessionHostVm[i].name}/customScript'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: customScript.fileUris
    }
    protectedSettings: {
      commandToExecute: customScript.commandToExecute
    }
  }
  dependsOn: [
    avdAgentExtensionAd
    avdAgentExtensionEntra
    avdAgentExtensionNone
  ]
}]

output sessionHostNames array = [for host in hostDefinitions: host.vmName]
output sessionHostIds array = [for (host, i) in hostDefinitions: sessionHostVm[i].id]
output networkInterfaceIds array = [for (host, i) in hostDefinitions: sessionHostNic[i].id]
