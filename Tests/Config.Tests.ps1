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

Describe 'Resolve-TenableWASScans' {
    BeforeAll {
        # Mock Tenable module function
        $script:originalFn = $null
        if (Get-Command Get-TenableWASScanConfigs -ErrorAction SilentlyContinue) {
            $script:originalFn = (Get-Command Get-TenableWASScanConfigs).ScriptBlock
        }
    }

    AfterAll {
        if ($script:originalFn) {
            Set-Item -Path function:Get-TenableWASScanConfigs -Value $script:originalFn
        } else {
            Remove-Item -Path function:Get-TenableWASScanConfigs -ErrorAction SilentlyContinue
        }
    }

    It 'Resolves matching scan names' {
        # Arrange
        $config = @{
            TenableWASScanNames = @('Scan A','Scan C')
        }

        function Get-TenableWASScanConfigs {
            return @(
                [pscustomobject]@{ Name = 'Scan A'; Id = 'id-a' },
                [pscustomobject]@{ Name = 'Scan B'; Id = 'id-b' },
                [pscustomobject]@{ Name = 'Scan C'; Id = 'id-c' }
            )
        }

        # Act
        $result = Resolve-TenableWASScans -Config $config

        # Assert
        $result.Count | Should -Be 2
        ($result | Where-Object Name -eq 'Scan A').Id | Should -Be 'id-a'
        ($result | Where-Object Name -eq 'Scan C').Id | Should -Be 'id-c'
    }

    It 'Returns empty when names missing' {
        $config = @{ TenableWASScanNames = @() }
        function Get-TenableWASScanConfigs { @() }

        $result = Resolve-TenableWASScans -Config $config
        $result | Should -BeEmpty
    }

    It 'Warns and skips when function unavailable' {
        Remove-Item -Path function:Get-TenableWASScanConfigs -ErrorAction SilentlyContinue
        function Get-TenableWASScanConfigs { param(); throw 'Should not be called' }

        $config = @{ TenableWASScanNames = @('Scan A') }

        { Resolve-TenableWASScans -Config $config } | Should -Not -Throw
        $result = Resolve-TenableWASScans -Config $config
        $result | Should -BeEmpty
    }
}
