# Pester tests for EnvValidator module
$moduleDir = Join-Path $PSScriptRoot '../modules'
. (Join-Path $moduleDir 'Config.ps1')
. (Join-Path $moduleDir 'Logging.ps1')
. (Join-Path $moduleDir 'EnvValidator.ps1')

# Mock config with different tool combinations
$mockConfig = @{
    Debug = $false
    Tools = @{
        DefectDojo = $true
        TenableWAS = $true
        SonarQube = $false
        BurpSuite = $true
    }
    Paths = @{ BurpSuiteXmlFolder = 'C:\Scans\Burp' }
    ApiBaseUrls = @{}
}

Describe 'EnvValidator Module Tests' {
    BeforeAll {
        Mock Get-Config { return $mockConfig }
        
        # Mock Windows Forms MessageBox and VB InputBox to avoid GUI interactions during tests
        Mock -CommandName Add-Type -MockWith {} -ParameterFilter { $AssemblyName -eq 'System.Windows.Forms' }
        Mock -CommandName Add-Type -MockWith {} -ParameterFilter { $AssemblyName -eq 'Microsoft.VisualBasic' }
        
        # Create mock objects for GUI components
        $script:mockMessageBoxResult = 'No'
        $script:mockInputBoxResult = ''
    }

    Describe 'Get-EnvVariables' {
        It 'Returns variables only for enabled tools' {
            $vars = Get-EnvVariables
            $vars | Should -Contain 'DOJO_API_KEY'
            $vars | Should -Contain 'TENWAS_ACCESS_KEY'
            $vars | Should -Contain 'TENWAS_SECRET_KEY'
            $vars | Should -Contain 'BURP_API_KEY'
            $vars | Should -Not -Contain 'SONARQUBE_API_TOKEN'
        }

        It 'Returns empty array when no tools are enabled' {
            Mock Get-Config { 
                return @{ 
                    Tools = @{
                        DefectDojo = $false
                        TenableWAS = $false
                        SonarQube = $false
                        BurpSuite = $false
                    }
                }
            }
            $vars = Get-EnvVariables
            $vars | Should -BeNullOrEmpty
        }
    }

    Describe 'Validate-Environment' {
        Context 'When all required variables are set' {
            BeforeAll {
                $env:DOJO_API_KEY = 'test-dojo-key'
                $env:TENWAS_ACCESS_KEY = 'test-access-key'
                $env:TENWAS_SECRET_KEY = 'test-secret-key'
                $env:BURP_API_KEY = 'test-burp-key'
            }

            It 'Should not throw any errors' {
                { Validate-Environment } | Should -Not -Throw
            }

            It 'Should log success message' {
                Mock Write-Log -Verifiable -ParameterFilter { $Message -eq 'All required environment variables are set.' -and $Level -eq 'INFO' }
                Validate-Environment
                Assert-VerifiableMock
            }
            
            AfterAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:BURP_API_KEY -ErrorAction SilentlyContinue
            }
        }

        Context 'When variables are missing and user declines to enter them' {
            BeforeAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
                Remove-Item Env:BURP_API_KEY -ErrorAction SilentlyContinue
                
                # Mock MessageBox to return 'No'
                Mock -CommandName Invoke-Expression -MockWith { 'No' } -ParameterFilter { $Command -like '*MessageBox*' }
                $global:mockMessageBoxCalled = $false
                Add-Type -TypeDefinition @"
                    using System.Windows.Forms;
                    public static class MockMessageBox {
                        public static DialogResult Show(string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon) {
                            return DialogResult.No;
                        }
                    }
"@ -ReferencedAssemblies System.Windows.Forms -ErrorAction SilentlyContinue
            }

            It 'Should throw error when user declines to enter missing variables' {
                # Mock the MessageBox Show method to return 'No'
                Mock -ModuleName EnvValidator -CommandName '[System.Windows.Forms.MessageBox]::Show' -MockWith { 'No' }
                
                { Validate-Environment } | Should -Throw -ExpectedMessage '*Required environment variables missing*'
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
                Mock -ModuleName EnvValidator -CommandName '[System.Windows.Forms.MessageBox]::Show' -MockWith { 'Yes' }
                Mock Request-MissingApiKeys -Verifiable
                
                { Validate-Environment } | Should -Not -Throw
                Assert-VerifiableMock
            }
        }
    }

    Describe 'Request-MissingApiKeys' {
        BeforeAll {
            # Mock the InputBox to avoid GUI interaction
            Mock -CommandName '[Microsoft.VisualBasic.Interaction]::InputBox' -MockWith { 'mock-api-key-value' }
            Mock -CommandName '[Environment]::SetEnvironmentVariable' -MockWith {}
            Mock Write-Host -MockWith {}
        }

        It 'Should prompt for each missing variable' {
            $missingVars = @('DOJO_API_KEY', 'TENWAS_ACCESS_KEY')
            
            Request-MissingApiKeys -MissingVars $missingVars
            
            Assert-MockCalled '[Microsoft.VisualBasic.Interaction]::InputBox' -Times 2
        }

        It 'Should set environment variables in both User and Process scope' {
            $missingVars = @('DOJO_API_KEY')
            
            Request-MissingApiKeys -MissingVars $missingVars
            
            Assert-MockCalled '[Environment]::SetEnvironmentVariable' -ParameterFilter { $args[2] -eq 'User' } -Times 1
            Assert-MockCalled '[Environment]::SetEnvironmentVariable' -ParameterFilter { $args[2] -eq 'Process' } -Times 1
        }

        It 'Should skip empty or null values' {
            Mock -CommandName '[Microsoft.VisualBasic.Interaction]::InputBox' -MockWith { '' }
            Mock Write-Log -Verifiable -ParameterFilter { $Message -like '*skipping*' -and $Level -eq 'WARNING' }
            
            Request-MissingApiKeys -MissingVars @('EMPTY_KEY')
            
            Assert-VerifiableMock
            Assert-MockCalled '[Environment]::SetEnvironmentVariable' -Times 0
        }

        It 'Should handle errors gracefully' {
            Mock -CommandName '[Microsoft.VisualBasic.Interaction]::InputBox' -MockWith { 'test-value' }
            Mock -CommandName '[Environment]::SetEnvironmentVariable' -MockWith { throw 'Access denied' }
            Mock Write-Log -Verifiable -ParameterFilter { $Level -eq 'ERROR' }
            
            { Request-MissingApiKeys -MissingVars @('ERROR_KEY') } | Should -Not -Throw
            Assert-VerifiableMock
        }
    }

    Describe 'Integration Tests' {
        Context 'Complete workflow with missing variables' {
            BeforeAll {
                Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
                Mock -CommandName '[System.Windows.Forms.MessageBox]::Show' -MockWith { 'Yes' }
                Mock -CommandName '[Microsoft.VisualBasic.Interaction]::InputBox' -MockWith { 'integration-test-key' }
                Mock -CommandName '[Environment]::SetEnvironmentVariable' -MockWith {
                    # Simulate setting the environment variable
                    if ($args[2] -eq 'Process') {
                        Set-Item "Env:$($args[0])" $args[1]
                    }
                }
            }

            It 'Should successfully validate after user provides missing keys' {
                { Validate-Environment -RequiredVariables @('DOJO_API_KEY') } | Should -Not -Throw
            }
        }
    }
}
