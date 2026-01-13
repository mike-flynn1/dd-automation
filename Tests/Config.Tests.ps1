# Pester tests for Config module
BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../modules'
    . (Join-Path $moduleDir 'Config.ps1')

    $exampleConfigPath = Join-Path (Join-Path $PSScriptRoot '../config') 'config.psd1.example'
    $invalidPath       = Join-Path $PSScriptRoot 'nonexistent.psd1'
}

Describe 'Get-Config' {
    Context 'When config file exists' {
        It 'Loads configuration as a hashtable' {
            $config = Get-Config -ConfigPath $exampleConfigPath -TemplatePath $invalidPath
            $config | Should -BeOfType Hashtable
            $config.ContainsKey('Tools') | Should -BeTrue
        }
    }
    Context 'When config file missing, example exists' {
        It 'Loads example config without throwing' {
            { Get-Config -ConfigPath $invalidPath -TemplatePath $exampleConfigPath } | Should -Not -Throw
        }
    }
    Context 'When both config and example missing' {
        It 'Throws an error' {
            { Get-Config -ConfigPath $invalidPath -TemplatePath (Join-Path $PSScriptRoot 'anothernonexistent.psd1') } | Should -Throw
        }
    }
}

Describe 'Validate-Config' {
    It 'Returns true for valid config' {
        $config = Import-PowerShellDataFile -Path $exampleConfigPath
        Validate-Config -Config $config | Should -BeTrue
    }
    It 'Throws error for missing keys' {
        $badConfig = @{}
        { Validate-Config -Config $badConfig } | Should -Throw
    }
}

Describe 'Save-Config' {
    BeforeEach {
        $script:tempConfigPath = Join-Path $TestDrive 'test-config.psd1'
    }

    Context 'When saving TenableWASScanNames configuration' {
        It 'Saves array of scan names correctly' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                TenableWASScanNames = @('Scan One', 'Scan Two', 'Scan Three')
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "TenableWASScanNames = @\("
            $savedContent | Should -Match "'Scan One'"
            $savedContent | Should -Match "'Scan Two'"
            $savedContent | Should -Match "'Scan Three'"
        }

        It 'Saves empty array when no scan names are provided' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                TenableWASScanNames = @()
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "TenableWASScanNames = @\(\)"
        }

        It 'Saves empty array when scan names are null' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                TenableWASScanNames = $null
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "TenableWASScanNames = @\(\)"
        }

        It 'Handles scan names with special characters' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                TenableWASScanNames = @("Scan's Name", 'Scan "With" Quotes')
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "TenableWASScanNames = @\("
        }
    }

    Context 'When TenableWASScanNames key is not present' {
        It 'Does not include TenableWASScanNames in output' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Not -Match "TenableWASScanNames"
        }
    }
}
