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

    Context 'When saving Notifications configuration' {
        It 'Saves WebhookUrl when provided' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
                Notifications = @{
                    WebhookUrl = 'https://hooks.slack.com/services/TEST123'
                }
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "Notifications = @\{"
            $savedContent | Should -Match "WebhookUrl = 'https://hooks.slack.com/services/TEST123'"
        }

        It 'Comments out empty WebhookUrl' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
                Notifications = @{
                    WebhookUrl = ''
                }
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "Notifications = @\{"
            $savedContent | Should -Match "# WebhookUrl = ''"
        }

        It 'Does not include Notifications section when not present in config' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Not -Match "Notifications"
        }

        It 'Preserves webhook URL across save/load cycle' {
            $originalConfig = @{
                Tools = @{ 
                    TenableWAS = $true 
                    SonarQube = $false
                    BurpSuite = $false
                    DefectDojo = $false
                    GitHub = @{ CodeQL = $false; SecretScanning = $false; Dependabot = $false }
                }
                ApiBaseUrls = @{ 
                    TenableWAS = 'https://example.com'
                    SonarQube = 'https://sonar.example.com'
                    BurpSuite = 'https://burp.example.com'
                    DefectDojo = 'https://dd.example.com'
                    GitHub = 'https://api.github.com'
                }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
                DefectDojo = @{ ProductId = 1 }
                GitHub = @{ Orgs = @('TestOrg') }
                Notifications = @{
                    WebhookUrl = 'https://hooks.slack.com/services/PRESERVED'
                }
            }

            Save-Config -Config $originalConfig -ConfigPath $script:tempConfigPath
            $loadedConfig = Get-Config -ConfigPath $script:tempConfigPath -TemplatePath ''

            $loadedConfig.Notifications | Should -Not -BeNullOrEmpty
            $loadedConfig.Notifications.WebhookUrl | Should -Be 'https://hooks.slack.com/services/PRESERVED'
        }

        It 'Handles special characters in webhook URL' {
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
                Notifications = @{
                    WebhookUrl = "https://example.com/webhook?token=abc'def&key=123"
                }
            }

            Save-Config -Config $config -ConfigPath $script:tempConfigPath

            $script:tempConfigPath | Should -Exist
            $savedContent = Get-Content $script:tempConfigPath -Raw
            $savedContent | Should -Match "WebhookUrl = 'https://example.com/webhook\?token=abc''def&key=123'"
        }
    }

    Context 'When no ConfigPath is provided' {
        It 'Uses the active config path when set' {
            $script:tempConfigPath = Join-Path $TestDrive 'active-config.psd1'
            $config = @{
                Tools = @{ TenableWAS = $true }
                ApiBaseUrls = @{ TenableWAS = 'https://example.com' }
                Paths = @{ BurpSuiteXmlFolder = 'C:\temp' }
            }

            $originalActivePath = $global:DDAutomation_ActiveConfigPath
            try {
                Set-ActiveConfigPath -Path $script:tempConfigPath
                Save-Config -Config $config

                $script:tempConfigPath | Should -Exist
                $savedContent = Get-Content $script:tempConfigPath -Raw
                $savedContent | Should -Match "Tools = @\{" 
            }
            finally {
                if ($null -ne $originalActivePath) {
                    $global:DDAutomation_ActiveConfigPath = $originalActivePath
                }
                else {
                    $global:DDAutomation_ActiveConfigPath = $null
                }
            }
        }
    }
}

Describe 'Resolve-TenableWASScans' {
    It 'Resolves matching scan names' {
        # Arrange
        $config = @{
            TenableWASScanNames = @('Scan A','Scan C')
        }

        Set-Item -Path function:Get-TenableWASScanConfigs -Value {
            return @(
                [pscustomobject]@{ Name = 'Scan A'; Id = 'id-a' },
                [pscustomobject]@{ Name = 'Scan B'; Id = 'id-b' },
                [pscustomobject]@{ Name = 'Scan C'; Id = 'id-c' }
            )
        }

        try {
            # Act
            $result = Resolve-TenableWASScans -Config $config

            # Assert
            $result.Count | Should -Be 2
            ($result | Where-Object Name -eq 'Scan A').Id | Should -Be 'id-a'
            ($result | Where-Object Name -eq 'Scan C').Id | Should -Be 'id-c'
        } finally {
            # Clean up
            Remove-Item -Path function:Get-TenableWASScanConfigs -ErrorAction SilentlyContinue
        }
    }

    It 'Returns empty for null scan names' {
        $config = @{ TenableWASScanNames = $null }
        $result = Resolve-TenableWASScans -Config $config
        $result | Should -BeNullOrEmpty
    }

    It 'Returns empty when no matching scans found' {
        # Arrange
        $config = @{
            TenableWASScanNames = @('NonexistentScan')
        }

        Set-Item -Path function:Get-TenableWASScanConfigs -Value {
            return @(
                [pscustomobject]@{ Name = 'Scan A'; Id = 'id-a' }
            )
        }

        try {
            # Act
            $result = Resolve-TenableWASScans -Config $config

            # Assert
            $result | Should -BeNullOrEmpty
        } finally {
            # Clean up
            Remove-Item -Path function:Get-TenableWASScanConfigs -ErrorAction SilentlyContinue
        }
    }
}
