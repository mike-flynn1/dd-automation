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
