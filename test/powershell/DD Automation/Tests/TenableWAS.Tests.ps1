# Pester tests for TenableWAS module
$moduleDir = Join-Path $PSScriptRoot '../modules'
. (Join-Path $moduleDir 'Config.ps1')
. (Join-Path $moduleDir 'Logging.ps1')
. (Join-Path $moduleDir 'TenableWAS.ps1')

Describe 'Export-TenableWASScan (Unit)' {
    Context 'When no scan ID is provided via parameter or config' {
        BeforeAll {
            Mock Get-Config { return @{} }
            $env:TENWAS_ACCESS_KEY = 'dummy'
            $env:TENWAS_SECRET_KEY = 'dummy'
        }
        It 'Throws an error indicating missing ScanId' {
            { Export-TenableWASScan } | Should -Throw 'No TenableWAS ScanId specified.'
        }
    }

    Context 'When credentials are missing' {
        BeforeAll {
            Mock Get-Config { return @{ TenableWAS = @{ ScanId = 'dummy-scan-id' }; ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
        }
        It 'Throws an error indicating missing credentials' {
            { Export-TenableWASScan -ScanId 'dummy-id' } | Should -Throw 'Missing Tenable WAS API credentials'
        }
    }
}

if (-not ($env:TENWAS_ACCESS_KEY -and $env:TENWAS_SECRET_KEY)) {
    Write-Warning 'Skipping TenableWAS integration tests: TENWAS_ACCESS_KEY and TENWAS_SECRET_KEY environment variables must be set.'
    return
}

Describe 'Export-TenableWASScan (Integration)' {
    BeforeAll {
        $config = Get-Config
        if (-not $config.TenableWAS.ScanId) {
            Throw 'ScanId not set in configuration (TenableWAS.ScanId).'
        }
        $scanId = $config.TenableWAS.ScanId
    }

    It 'Generates and downloads a report CSV file' {
        $outPath = Export-TenableWASScan -ScanId $scanId
        $outPath | Should -Match "$scanId-report\.csv$"
        Test-Path $outPath | Should -BeTrue
        (Get-Item $outPath).Length | Should -BeGreaterThan 0
    }
}