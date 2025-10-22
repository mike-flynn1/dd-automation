# Pester tests for TenableWAS module
$Global:TenableWasModuleDir = Join-Path $PSScriptRoot '../modules'
. (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
. (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
. (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')

$Global:OriginalTenwasAccessKey = $env:TENWAS_ACCESS_KEY
$Global:OriginalTenwasSecretKey = $env:TENWAS_SECRET_KEY

Describe 'Export-TenableWASScan (Unit)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')
    }

    Context 'When no scan ID is provided via parameter or config' {
        BeforeAll {
            $script:OriginalGetConfig_NoScan = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{} }
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-noscan.log' -Overwrite
            $env:TENWAS_ACCESS_KEY = 'dummy'
            $env:TENWAS_SECRET_KEY = 'dummy'
        }
        AfterAll {
            if ($script:OriginalGetConfig_NoScan) {
                Set-Item function:Get-Config -Value $script:OriginalGetConfig_NoScan
            } else {
                Remove-Item function:Get-Config -ErrorAction SilentlyContinue
            }

            if ($null -ne $Global:OriginalTenwasAccessKey) {
                $env:TENWAS_ACCESS_KEY = $Global:OriginalTenwasAccessKey
            } else {
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            }

            if ($null -ne $Global:OriginalTenwasSecretKey) {
                $env:TENWAS_SECRET_KEY = $Global:OriginalTenwasSecretKey
            } else {
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
            }
        }
        It 'Throws an error indicating missing ScanId' {
            { Export-TenableWASScan } | Should -Throw 'No TenableWAS ScanId specified.'
        }
    }

    Context 'When credentials are missing' {
        BeforeAll {
            $script:OriginalGetConfig_MissingCreds = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{ TenableWAS = @{ ScanId = 'dummy-scan-id' }; ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-missingcreds.log' -Overwrite
            Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($script:OriginalGetConfig_MissingCreds) {
                Set-Item function:Get-Config -Value $script:OriginalGetConfig_MissingCreds
            } else {
                Remove-Item function:Get-Config -ErrorAction SilentlyContinue
            }

            if ($null -ne $Global:OriginalTenwasAccessKey) {
                $env:TENWAS_ACCESS_KEY = $Global:OriginalTenwasAccessKey
            } else {
                Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            }

            if ($null -ne $Global:OriginalTenwasSecretKey) {
                $env:TENWAS_SECRET_KEY = $Global:OriginalTenwasSecretKey
            } else {
                Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
            }
        }
        It 'Throws an error indicating missing credentials' {
            { Export-TenableWASScan -ScanId 'dummy-id' } | Should -Throw 'Missing Tenable WAS API credentials*'
        }
    }
}

if (-not ($env:TENWAS_ACCESS_KEY -and $env:TENWAS_SECRET_KEY)) {
    Write-Warning 'Skipping TenableWAS integration tests: TENWAS_ACCESS_KEY and TENWAS_SECRET_KEY environment variables must be set.'
    return
}

Describe 'Export-TenableWASScan (Integration)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')

        $tempLogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'tenablewas-tests'
        Initialize-Log -LogDirectory $tempLogDir -LogFileName 'integration.log' -Overwrite

        $script:integrationConfig = Get-Config
        $script:integrationScanId = $null
        if ($script:integrationConfig.TenableWAS -and $script:integrationConfig.TenableWAS.ScanId) {
            $script:integrationScanId = $script:integrationConfig.TenableWAS.ScanId
        } elseif ($script:integrationConfig.TenableWASScanId) {
            $script:integrationScanId = $script:integrationConfig.TenableWASScanId
        }

        if (-not $script:integrationScanId) {
            Throw 'ScanId not set in configuration (TenableWAS.ScanId or TenableWASScanId).'
        }
    }

    It 'Generates and downloads a report CSV file' {
        $outPath = Export-TenableWASScan -ScanId $script:integrationScanId
        if ($outPath -is [System.IO.FileSystemInfo]) {
            $outPath = $outPath.FullName
        } elseif ($outPath) {
            $outPath = [string]$outPath
        }

        $expectedPath = Join-Path ([System.IO.Path]::GetTempPath()) ("${script:integrationScanId}-report.csv")
        $candidatePaths = @($outPath, $expectedPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $resolvedOutPath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $resolvedOutPath) {
            $resolvedOutPath = $candidatePaths | Select-Object -First 1
        }

        $resolvedOutPath | Should -Not -BeNullOrEmpty
        [System.IO.Path]::GetFileName($resolvedOutPath) | Should -Match "${script:integrationScanId}-report\.csv$"
        Test-Path $resolvedOutPath | Should -BeTrue
        (Get-Item $resolvedOutPath).Length | Should -BeGreaterThan 0
    }
}
