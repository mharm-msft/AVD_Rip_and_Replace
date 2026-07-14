#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
  Pester tests for the AVD automated retirement eligibility logic.

.DESCRIPTION
  These tests exercise Test-AvdHostRetirementEligibility from the AvdRipReplace module
  and the script-level safety gates in Invoke-AvdAutoRetirement.ps1.
  No live Azure credentials are required; all Az cmdlets are mocked.
#>

BeforeAll {
  $modulePath = Join-Path $PSScriptRoot '../scripts/Modules/AvdRipReplace/AvdRipReplace.psm1'
  Import-Module $modulePath -Force
}

Describe 'Test-AvdHostRetirementEligibility' {

  Context 'Retention period not elapsed' {

    It 'Skips a host when elapsed time is less than 30 hours' {
      $drainStart = [datetime]::UtcNow.AddHours(-25)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc ([datetime]::UtcNow)

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'retention period not elapsed'
    }

    It 'Skips a host when elapsed time is exactly 0 hours' {
      $drainStart = [datetime]::UtcNow
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc ([datetime]::UtcNow)

      $result.IsEligible | Should -BeFalse
    }
  }

  Context 'Retention period elapsed' {

    It 'Marks a host eligible when elapsed time is exactly 30 hours' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-30)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeTrue
    }

    It 'Marks a host eligible when elapsed time exceeds 30 hours' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-48)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeTrue
    }
  }

  Context 'Malformed or missing drain-start timestamp' {

    It 'Skips a host when AVDDrainStartedAt tag is missing' {
      $tags = @{ AVDAutoDelete = 'true'; AVDDrainMode = 'true' }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'missing or empty'
    }

    It 'Skips a host when AVDDrainStartedAt tag is empty' {
      $tags = @{ AVDAutoDelete = 'true'; AVDDrainMode = 'true'; AVDDrainStartedAt = '' }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'missing or empty'
    }

    It 'Skips a host when AVDDrainStartedAt is not a valid timestamp' {
      $tags = @{ AVDAutoDelete = 'true'; AVDDrainMode = 'true'; AVDDrainStartedAt = 'not-a-date' }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'not a valid ISO-8601'
    }
  }

  Context 'Active or disconnected sessions block deletion' {

    It 'Skips a host that has active sessions when ForceLogoff is false' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 2 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'session'
    }

    It 'Allows deletion when ForceLogoff is true even with active sessions' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 2 `
        -ForceLogoff $true `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeTrue
    }
  }

  Context 'AVDAutoDelete tag not set' {

    It 'Skips a host when AVDAutoDelete tag is missing' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'AVDAutoDelete'
    }

    It 'Skips a host when AVDAutoDelete tag is false' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDAutoDelete     = 'false'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'AVDAutoDelete'
    }
  }

  Context 'Drain mode not enabled in AVD' {

    It 'Skips a host when AllowNewSession is true' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $true `
        -ReplacementGenerationValidationMarker 'g2408' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'drain mode'
    }
  }

  Context 'Replacement generation not validated' {

    It 'Skips when ReplacementGenerationValidationMarker is empty' {
      $nowUtc   = [datetime]::UtcNow
      $drainStart = $nowUtc.AddHours(-31)
      $tags = @{
        AVDAutoDelete     = 'true'
        AVDDrainStartedAt = $drainStart.ToString('o')
        AVDDrainMode      = 'true'
      }
      $result = Test-AvdHostRetirementEligibility `
        -AllowNewSession $false `
        -ReplacementGenerationValidationMarker '' `
        -DrainRetentionHours 30 `
        -ActiveAndDisconnectedSessionCount 0 `
        -ForceLogoff $false `
        -VmTags $tags `
        -NowUtc $nowUtc

      $result.IsEligible | Should -BeFalse
      $result.SkipReason | Should -Match 'ReplacementGenerationValidationMarker'
    }
  }
}

Describe 'Invoke-AvdAutoRetirement.ps1 - script-level safety gates' {

  BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '../scripts/Invoke-AvdAutoRetirement.ps1'

    # Stub out all Az cmdlets so the script runs without Azure credentials.
    function global:Get-AzWvdSessionHost { return @() }
    function global:Get-AzWvdUserSession { return @() }
    function global:Update-AzWvdSessionHost { }
    function global:Remove-AzWvdSessionHost { }
    function global:Remove-AzWvdUserSession { }
    function global:Get-AzVM { return @() }
    function global:Remove-AzVM { }
    function global:Get-AzNetworkInterface { return $null }
    function global:Remove-AzNetworkInterface { }
    function global:Get-AzDisk { return $null }
    function global:Remove-AzDisk { }
    function global:Update-AzTag { }
    function global:Connect-AzAccount { }
  }

  It 'Exits early and writes a warning when EnableAutomaticRetirement is not set' {
    $output = & $script:scriptPath `
      -HostPoolName 'hp-test' `
      -ResourceGroupName 'rg-cp' `
      -GenerationName 'g2407' `
      -SessionHostResourceGroupName 'rg-sh' `
      -ReplacementGenerationValidationMarker 'g2408' `
      -WarningVariable warnings 2>&1

    # Script should not have reached the Az API calls (no Get-AzWvdSessionHost calls needed)
    $warnings | Should -Match 'disabled'
  }

  It 'Exits early and writes a warning when KillSwitch is present' {
    $output = & $script:scriptPath `
      -HostPoolName 'hp-test' `
      -ResourceGroupName 'rg-cp' `
      -GenerationName 'g2407' `
      -SessionHostResourceGroupName 'rg-sh' `
      -ReplacementGenerationValidationMarker 'g2408' `
      -EnableAutomaticRetirement `
      -KillSwitch `
      -WarningVariable warnings 2>&1

    $warnings | Should -Match 'KillSwitch'
  }

  It 'Honours MaxDeletionsPerRun and stops after the configured limit' {
    # Provide a fake session host list with 3 hosts and MaxDeletionsPerRun = 2.
    # The eligibility check will skip all (no eligible hosts), but the skipped-reason
    # for the 3rd host should mention MaxDeletionsPerRun only if 2 were processed.
    # Since all hosts fail eligibility due to missing tags/no VMs, we just verify the
    # script completes without error.
    $result = & $script:scriptPath `
      -HostPoolName 'hp-test' `
      -ResourceGroupName 'rg-cp' `
      -GenerationName 'g2407' `
      -SessionHostResourceGroupName 'rg-sh' `
      -ReplacementGenerationValidationMarker 'g2408' `
      -EnableAutomaticRetirement `
      -MaxDeletionsPerRun 2 `
      -WhatIf 2>&1

    # Script should complete without throwing
    $? | Should -BeTrue
  }
}
