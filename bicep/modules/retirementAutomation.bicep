/*
  retirementAutomation.bicep
  Optional Azure Automation Account module that deploys the AVD auto-retirement
  runbook and a recurring schedule.

  The Automation Account uses a system-assigned managed identity.  After deployment,
  grant the identity the minimum RBAC roles documented in the README.

  PARAMETERS
  ----------
  enableAutomaticRetirement      - Must be true to activate the schedule (opt-in safety gate).
  drainRetentionHours            - Hours a host must be in drain mode before it is eligible. Default 30.
  maxDeletionsPerRun             - Maximum VMs deleted per runbook execution. Default 10, max 100.
  scheduleFrequencyHours         - How often (hours) the schedule fires. Default 1.
  replacementGenerationValidationMarker - Explicit approval marker for the replacement generation.
*/

param location string = resourceGroup().location
param automationAccountName string

@allowed([
  'Basic'
  'Free'
])
param skuName string = 'Basic'

param hostPoolName string
param hostPoolResourceGroupName string
param generationName string
param sessionHostResourceGroupName string

@description('Explicit marker confirming the replacement generation is approved, e.g. the new generation name.')
param replacementGenerationValidationMarker string

param hostNamePrefix string = ''

@minValue(1)
@maxValue(720)
param drainRetentionHours int = 30

param enableAutomaticRetirement bool = false
param deleteNetworkInterfaces bool = false
param deleteManagedDisks bool = false

@minValue(1)
@maxValue(100)
param maxDeletionsPerRun int = 10

@minValue(1)
@maxValue(24)
param scheduleFrequencyHours int = 1

param tags object = {}

// Embed the retirement script so the runbook is always in sync with the operator script.
// loadTextContent paths in Bicep are resolved at compile time, relative to this file.
// This module must be compiled from its location within the repository at
// bicep/modules/retirementAutomation.bicep so that ../../scripts/ resolves correctly.
var runbookContent = loadTextContent('../../scripts/Invoke-AvdAutoRetirement.ps1')

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: skuName
    }
    publicNetworkAccess: true
  }
}

resource retirementRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Invoke-AvdAutoRetirement'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    logVerbose: false
    logProgress: true
    description: 'Automatically retires eligible drained AVD session hosts after the configured retention period.'
    publishContentLink: {
      uri: 'data:text/plain;base64,${base64(runbookContent)}'
    }
  }
}

// Build the runbook parameter object from Bicep parameters.
var runbookParameters = union(
  {
    HostPoolName: hostPoolName
    ResourceGroupName: hostPoolResourceGroupName
    GenerationName: generationName
    SessionHostResourceGroupName: sessionHostResourceGroupName
    ReplacementGenerationValidationMarker: replacementGenerationValidationMarker
    DrainRetentionHours: string(drainRetentionHours)
    MaxDeletionsPerRun: string(maxDeletionsPerRun)
    UseAutomationManagedIdentity: 'true'
  },
  enableAutomaticRetirement ? { EnableAutomaticRetirement: 'true' } : {},
  !empty(hostNamePrefix) ? { HostNamePrefix: hostNamePrefix } : {},
  deleteNetworkInterfaces ? { DeleteNetworkInterfaces: 'true' } : {},
  deleteManagedDisks ? { DeleteManagedDisks: 'true' } : {}
)

resource retirementSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (enableAutomaticRetirement) {
  parent: automationAccount
  name: 'avd-retirement-hourly'
  properties: {
    description: 'Triggers the AVD auto-retirement runbook every ${scheduleFrequencyHours} hour(s).'
    frequency: 'Hour'
    interval: scheduleFrequencyHours
    timeZone: 'UTC'
    startTime: dateTimeAdd(utcNow(), 'PT5M')
  }
}

resource retirementJobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (enableAutomaticRetirement) {
  parent: automationAccount
  name: guid(automationAccount.id, retirementRunbook.name, 'schedule')
  properties: {
    schedule: {
      name: retirementSchedule.name
    }
    runbook: {
      name: retirementRunbook.name
    }
    parameters: runbookParameters
  }
}

output automationAccountId string = automationAccount.id
output automationAccountName string = automationAccount.name
output automationAccountPrincipalId string = automationAccount.identity.principalId
output runbookName string = retirementRunbook.name
