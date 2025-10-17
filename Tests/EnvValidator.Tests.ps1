# Pester tests for EnvValidator module
BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../modules'
    . (Join-Path $moduleDir 'Config.ps1')
    . (Join-Path $moduleDir 'Logging.ps1')
    . (Join-Path $moduleDir 'DefectDojo.ps1')
    . (Join-Path $moduleDir 'EnvValidator.ps1')

    Initialize-Log -LogFileName 'env-validator-tests.log' -Overwrite
}
# Helper to build mock config with overridable tool toggles
function global:New-MockConfig {
    param(
        [hashtable]$ToolsOverride
    )

    $config = @{
        Debug = $false
        Tools = @{
            DefectDojo = $true
            TenableWAS = $true
            SonarQube = $false
            BurpSuite = $true
            GitHub = $true
        }
        Paths = @{ BurpSuiteXmlFolder = 'C:\Scans\Burp' }
        ApiBaseUrls = @{}
    }

    if ($null -ne $ToolsOverride) {
        foreach ($key in $ToolsOverride.Keys) {
            $config.Tools[$key] = $ToolsOverride[$key]
        }
    }

    return $config
}

Describe 'EnvValidator Module Tests' {
    BeforeAll {
        $script:getConfigCalls = 0
        Mock Get-Config { $script:getConfigCalls++; return New-MockConfig }
    }

    Describe 'Get-EnvVariables' {
        It 'Returns variables only for enabled tools' {
            $vars = Get-EnvVariables
            $vars | Should -Contain 'DOJO_API_KEY'
            $vars | Should -Contain 'TENWAS_ACCESS_KEY'
            $vars | Should -Contain 'TENWAS_SECRET_KEY'
            $vars | Should -Contain 'BURP_API_KEY'
            $vars | Should -Contain 'GITHUB_PAT'
            $vars | Should -Not -Contain 'SONARQUBE_API_TOKEN'
        }

        It 'Returns empty array when no tools are enabled' {
            Mock Get-Config {
                $script:getConfigCalls++
                return New-MockConfig -ToolsOverride @{
                    DefectDojo = $false
                    TenableWAS = $false
                    SonarQube = $false
                    BurpSuite = $false
                    GitHub = $false
                }
            }
            $vars = Get-EnvVariables
            $vars | Should -BeNullOrEmpty

            Mock Get-Config { $script:getConfigCalls++; return New-MockConfig }
        }

        It 'Omits GitHub variable when tool disabled' {
            Mock Get-Config {
                $script:getConfigCalls++
                return New-MockConfig -ToolsOverride @{ GitHub = $false }
            }

            $vars = Get-EnvVariables
            $vars | Should -Not -Contain 'GITHUB_PAT'

            Mock Get-Config { $script:getConfigCalls++; return New-MockConfig }
        }
    }

    Describe 'Validate-Environment' {
        Context 'When all required variables are set' {
            BeforeAll {
                $env:DOJO_API_KEY = 'test-dojo-key'
                $env:TENWAS_ACCESS_KEY = 'test-access-key'
                $env:TENWAS_SECRET_KEY = 'test-secret-key'
                $env:BURP_API_KEY = 'test-burp-key'
                $env:GITHUB_PAT = 'test-github-pat'
            }

            It 'Should not throw any errors' {
                { Validate-Environment } | Should -Not -Throw
            }

            It 'Should log success message' {
                Mock Write-Log -Verifiable -ParameterFilter { $Message -eq 'All required environment variables are set.' -and $Level -eq 'INFO' }
                Validate-Environment
                Assert-VerifiableMock
            }

            It 'Should log status for each variable when Test switch is used' {
                Mock Write-Log -MockWith {}

                Validate-Environment -Test

                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq "Environment variable 'DOJO_API_KEY' is set." -and $Level -eq 'INFO' } -Times 1
                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq "Environment variable 'TENWAS_ACCESS_KEY' is set." -and $Level -eq 'INFO' } -Times 1
                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq "Environment variable 'TENWAS_SECRET_KEY' is set." -and $Level -eq 'INFO' } -Times 1
                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq "Environment variable 'BURP_API_KEY' is set." -and $Level -eq 'INFO' } -Times 1
                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq "Environment variable 'GITHUB_PAT' is set." -and $Level -eq 'INFO' } -Times 1
                Assert-MockCalled Write-Log -ParameterFilter { $Message -eq 'All required environment variables are set.' -and $Level -eq 'INFO' } -Times 1
            }
            
            AfterAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:BURP_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:GITHUB_PAT -ErrorAction SilentlyContinue
            }
        }

        Context 'When variables are missing and user declines to enter them' {
            BeforeAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:BURP_API_KEY -ErrorAction SilentlyContinue
            }

            It 'Should throw error when user declines to enter missing variables' {
                Mock Show-MissingVarsPrompt -Verifiable -MockWith { 'No' }
                Mock Write-Log -MockWith {}
                
                { Validate-Environment } | Should -Throw -ExpectedMessage '*Required environment variables missing*'

                Assert-MockCalled Write-Log -ParameterFilter { $Message -like 'Required environment variables missing*' -and $Level -eq 'ERROR' } -Times 1
                Assert-VerifiableMock
            }
        }

        Context 'When variables are missing and user accepts to enter them' {
            BeforeAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:BURP_API_KEY -ErrorAction SilentlyContinue
            }

            It 'Should call Request-MissingApiKeys when user accepts' {
                Mock Show-MissingVarsPrompt -MockWith { 'Yes' }
                Mock Request-MissingApiKeys -Verifiable
                
                { Validate-Environment } | Should -Not -Throw
                Assert-VerifiableMock
            }
        }

        Context 'When required variables are provided explicitly' {
            BeforeEach {
                $env:CUSTOM_VAR = 'custom-value'
            }

            AfterEach {
                Remove-Item Env:CUSTOM_VAR -ErrorAction SilentlyContinue
            }

            It 'Honors explicitly provided variable list' {
                Mock Get-Config {
                    $script:getConfigCalls++
                    throw 'Get-Config should not be called when RequiredVariables are supplied.'
                }
                Mock Write-Log -MockWith {}

                { Validate-Environment -RequiredVariables @('CUSTOM_VAR') } | Should -Not -Throw

                Mock Get-Config { $script:getConfigCalls++; return New-MockConfig }
                Mock Write-Log -MockWith {}
            }
        }
    }

    Describe 'Request-MissingApiKeys' {

        It 'Should prompt for each missing variable' {
            Mock Get-ApiKeyValue -MockWith { 'mock-api-key-value' }
            Mock Write-Log -MockWith {}
            Mock Write-Host -MockWith {}

            $missingVars = @('DOJO_API_KEY', 'TENWAS_ACCESS_KEY')
            $originalSetter = (Get-Command Set-EnvironmentValue).ScriptBlock
            $callTargets = [System.Collections.Generic.List[System.EnvironmentVariableTarget]]::new()
            Set-Item -Path function:Set-EnvironmentValue -Value {
                param($Name, $Value, $Target)
                $callTargets.Add($Target) | Out-Null
            }

            try {
                Request-MissingApiKeys -MissingVars $missingVars
            }
            finally {
                Set-Item -Path function:Set-EnvironmentValue -Value $originalSetter
            }
            
            Assert-MockCalled Get-ApiKeyValue -Times 2
        }

        It 'Should set environment variables in both User and Process scope' {
            Mock Get-ApiKeyValue -MockWith { 'mock-api-key-value' }
            Mock Write-Log -MockWith {}
            Mock Write-Host -MockWith {}

            $missingVars = @('DOJO_API_KEY')
            $originalSetter = (Get-Command Set-EnvironmentValue).ScriptBlock
            $callTargets = [System.Collections.Generic.List[System.EnvironmentVariableTarget]]::new()
            Set-Item -Path function:Set-EnvironmentValue -Value {
                param($Name, $Value, $Target)
                $callTargets.Add($Target) | Out-Null
            }

            try {
                Request-MissingApiKeys -MissingVars $missingVars
            }
            finally {
                Set-Item -Path function:Set-EnvironmentValue -Value $originalSetter
            }

            $callTargets | Should -Contain ([EnvironmentVariableTarget]::User)
            $callTargets | Should -Contain ([EnvironmentVariableTarget]::Process)
        }

        It 'Should skip empty or null values' {
            Mock Get-ApiKeyValue -MockWith { '' }
            Mock Write-Log -Verifiable -ParameterFilter { $Message -like '*skipping*' -and $Level -eq 'WARNING' }
            Mock Write-Host -MockWith {}

            $originalSetter = (Get-Command Set-EnvironmentValue).ScriptBlock
            $callTargets = [System.Collections.Generic.List[System.EnvironmentVariableTarget]]::new()
            Set-Item -Path function:Set-EnvironmentValue -Value {
                param($Name, $Value, $Target)
                $callTargets.Add($Target) | Out-Null
            }
            
            try {
                Request-MissingApiKeys -MissingVars @('EMPTY_KEY')
            }
            finally {
                Set-Item -Path function:Set-EnvironmentValue -Value $originalSetter
            }
            
            Assert-VerifiableMock
            $callTargets.Count | Should -Be 0
        }

        It 'Should handle errors gracefully' {
            Mock Get-ApiKeyValue -MockWith { 'test-value' }
            Mock Write-Log -Verifiable -ParameterFilter { $Level -eq 'ERROR' }
            Mock Write-Host -MockWith {}

            $originalSetter = (Get-Command Set-EnvironmentValue).ScriptBlock
            Set-Item -Path function:Set-EnvironmentValue -Value {
                param($Name, $Value, $Target)
                throw 'Access denied'
            }
            
            try {
                { Request-MissingApiKeys -MissingVars @('ERROR_KEY') } | Should -Not -Throw
            }
            finally {
                Set-Item -Path function:Set-EnvironmentValue -Value $originalSetter
            }
            Assert-VerifiableMock
        }
    }

    Describe 'Integration Tests' {
        Context 'Complete workflow with missing variables' {
            It 'Should successfully validate after user provides missing keys' {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Mock Show-MissingVarsPrompt -MockWith { 'Yes' }
                Mock Get-ApiKeyValue -MockWith { 'integration-test-key' }
                $originalSetter = (Get-Command Set-EnvironmentValue).ScriptBlock
                Set-Item -Path function:Set-EnvironmentValue -Value {
                    param($Name, $Value, $Target)
                    if ($Target -eq [EnvironmentVariableTarget]::Process) {
                        Set-Item "Env:$Name" $Value
                    }
                }

                try {
                    { Validate-Environment -RequiredVariables @('DOJO_API_KEY') } | Should -Not -Throw
                }
                finally {
                    Set-Item -Path function:Set-EnvironmentValue -Value $originalSetter
                }
            }
        }
    }
}
