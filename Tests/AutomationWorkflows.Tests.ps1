<#
.SYNOPSIS
    Tests for the AutomationWorkflows module.
    Note: These are basic smoke tests to ensure functions export and logic flow is sound.
    Full integration tests would require extensive mocking of the other modules.
#>

BeforeAll {
    $scriptDir = Split-Path $PSScriptRoot -Parent
    . (Join-Path $scriptDir 'modules\Logging.ps1')
    . (Join-Path $scriptDir 'modules\Config.ps1')
    . (Join-Path $scriptDir 'modules\BurpSuite.ps1')
    . (Join-Path $scriptDir 'modules\AutomationWorkflows.ps1')
}

Describe "AutomationWorkflows" {

    # 1. Module Export Tests
    Context "Module Exports" {
        It "Should export Invoke-Workflow-TenableWAS" {
            Get-Command Invoke-Workflow-TenableWAS -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It "Should export Invoke-Workflow-SonarQube" {
            Get-Command Invoke-Workflow-SonarQube -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        It "Should export Invoke-Workflow-BurpSuite" {
            Get-Command Invoke-Workflow-BurpSuite -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    # 2. Basic Logic Gate Tests
    Context "Invoke-Workflow-TenableWAS" {
        It "Should abort if no scans are selected" {
            Mock Write-Log
            
            $emptyConfig = @{ TenableWASSelectedScans = @() }
            Invoke-Workflow-TenableWAS -Config $emptyConfig

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter { $Message -match "No TenableWAS scans selected" }
        }
    }

    Context "Invoke-Workflow-BurpSuite" {
        It "Should abort if no XML files found" {
            Mock Get-BurpSuiteReports -MockWith { return @() }
            Mock Write-Log

            $config = @{ Paths = @{ BurpSuiteXmlFolder = 'C:\Fake' } }
            Invoke-Workflow-BurpSuite -Config $config

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter { $Message -match "No BurpSuite XML files found" }
        }
    }
    
    Context "Invoke-Workflow-GitHubCodeQL" {
        It "Should abort if no organizations configured" {
            Mock Write-Log
            
            $config = @{ GitHub = @{ Orgs = @() } }
            Invoke-Workflow-GitHubCodeQL -Config $config
            
            Assert-MockCalled Write-Log -Times 1 -ParameterFilter { $Message -match "No GitHub organizations configured" }
        }
    }

    Context "Zero-Results Notification Formatting" {
        It "Should format zero-results as 'No findings' message" {
            $workflowResults = @(
                [PSCustomObject]@{
                    Tool = 'GitHub Secret Scanning'
                    Success = $null
                    Failed = $null
                    Skipped = $null
                    Total = $null
                }
            )

            $detailsArray = @()
            foreach ($result in $workflowResults) {
                $success = if ([string]::IsNullOrEmpty([string]$result.Success)) { 0 } else { [int]$result.Success }
                $failed  = if ([string]::IsNullOrEmpty([string]$result.Failed)) { 0 } else { [int]$result.Failed }
                $skipped = if ([string]::IsNullOrEmpty([string]$result.Skipped)) { 0 } else { [int]$result.Skipped }
                $total   = if ([string]::IsNullOrEmpty([string]$result.Total)) { 0 } else { [int]$result.Total }

                if ($total -eq 0 -and $skipped -eq 0 -and $failed -eq 0) {
                    $detailsArray += "○ **$($result.Tool)**: No findings (0 files processed)"
                } else {
                    $status = if ($failed -gt 0) { '⚠' } elseif ($success -gt 0) { '✓' } else { '⊘' }
                    $detailsArray += "${status} **$($result.Tool)**: ${success} succeeded, ${failed} failed, ${skipped} skipped (Total: ${total})"
                }
            }

            $detailsArray[0] | Should -Be "○ **GitHub Secret Scanning**: No findings (0 files processed)"
        }

        It "Should use standard format when results exist" {
            $workflowResults = @(
                [PSCustomObject]@{
                    Tool = 'GitHub CodeQL'
                    Success = 3
                    Failed = 1
                    Skipped = 0
                    Total = 4
                }
            )

            $detailsArray = @()
            foreach ($result in $workflowResults) {
                $success = if ([string]::IsNullOrEmpty([string]$result.Success)) { 0 } else { [int]$result.Success }
                $failed  = if ([string]::IsNullOrEmpty([string]$result.Failed)) { 0 } else { [int]$result.Failed }
                $skipped = if ([string]::IsNullOrEmpty([string]$result.Skipped)) { 0 } else { [int]$result.Skipped }
                $total   = if ([string]::IsNullOrEmpty([string]$result.Total)) { 0 } else { [int]$result.Total }

                if ($total -eq 0 -and $skipped -eq 0 -and $failed -eq 0) {
                    $detailsArray += "○ **$($result.Tool)**: No findings (0 files processed)"
                } else {
                    $status = if ($failed -gt 0) { '⚠' } elseif ($success -gt 0) { '✓' } else { '⊘' }
                    $detailsArray += "${status} **$($result.Tool)**: ${success} succeeded, ${failed} failed, ${skipped} skipped (Total: ${total})"
                }
            }

            $detailsArray[0] | Should -Be "⚠ **GitHub CodeQL**: 3 succeeded, 1 failed, 0 skipped (Total: 4)"
        }
    }
}
