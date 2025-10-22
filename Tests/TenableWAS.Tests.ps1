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
            Mock Get-Config { return @{} }
            Mock Write-Log { }
            $env:TENWAS_ACCESS_KEY = 'dummy'
            $env:TENWAS_SECRET_KEY = 'dummy'
        }
        AfterAll {
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
            Mock Get-Config { return @{ TenableWAS = @{ ScanId = 'dummy-scan-id' }; ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Mock Write-Log { }
            Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
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
    }

    BeforeAll {
        $config = Get-Config
        if (-not $config.TenableWASScanId) {
            Throw 'ScanId not set in configuration (TenableWASScanId).'
        }
        $scanId = $config.TenableWASScanId
    }

    It 'Generates and downloads a report CSV file' {
        $outPath = Export-TenableWASScan -ScanId $scanId
        $outPath | Should -Match "$scanId-report.csv$"
        Test-Path $outPath | Should -BeTrue
        (Get-Item $outPath).Length | Should -BeGreaterThan 0
    }
}
