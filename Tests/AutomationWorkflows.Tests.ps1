<#
.SYNOPSIS
    Tests for the AutomationWorkflows module.
    Note: These are basic smoke tests to ensure functions export and logic flow is sound.
    Full integration tests would require extensive mocking of the other modules.
#>

$scriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $scriptDir 'modules\AutomationWorkflows.ps1')

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
}
