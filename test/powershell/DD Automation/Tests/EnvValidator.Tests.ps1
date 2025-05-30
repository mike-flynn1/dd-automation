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
Mock Get-Config { return $mockConfig }

Describe 'Get-EnvVariables' {
    It 'Returns variables only for enabled tools' {
        $vars = Get-EnvVariables
        $vars | Should -Contain 'DOJO_API_KEY'
        $vars | Should -Contain 'TENWAS_ACCESS_KEY'
        $vars | Should -Not -Contain 'SONARQUBE_API_TOKEN'
    }
}

Describe 'Validate-Environment' {
    Context 'When required variables for enabled tools are set' {
        BeforeAll {
            $env:DOJO_API_KEY = 'test-key'
            $env:TENWAS_ACCESS_KEY = 'test-access'
            $env:TENWAS_SECRET_KEY = 'test-secret'
        }


        It 'Should not throw any errors' {
            { Validate-Environment } | Should -Not -Throw
        }

        
        AfterAll {
            Remove-Item Env:DOJO_API_KEY
            Remove-Item Env:TENWAS_ACCESS_KEY
            Remove-Item Env:TENWAS_SECRET_KEY
        }
    }

    Context 'When variables are missing for enabled tools' {
        BeforeAll {
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
        }

        It 'Should throw error with missing variable names' {
            { Validate-Environment } | Should -Throw -ExpectedMessage '*DOJO_API_KEY*'
        }
    }
}
