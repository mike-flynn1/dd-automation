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

Describe 'Get-TenableWASScanConfigs (Unit)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')
    }

    Context 'When credentials are missing' {
        BeforeAll {
            $script:OriginalGetConfig_NoCredsScanConfigs = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{ ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-scanconfigs-nocreds.log' -Overwrite
            Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($script:OriginalGetConfig_NoCredsScanConfigs) {
                Set-Item function:Get-Config -Value $script:OriginalGetConfig_NoCredsScanConfigs
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
        It 'Throws an error when credentials are missing' {
            { Get-TenableWASScanConfigs } | Should -Throw 'Missing Tenable WAS API credentials.'
        }
    }

    Context 'When API returns scan configurations' {
        BeforeAll {
            $script:OriginalGetConfig_WithScanConfigs = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{ ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-scanconfigs-api.log' -Overwrite
            $env:TENWAS_ACCESS_KEY = 'test-key'
            $env:TENWAS_SECRET_KEY = 'test-secret'
        }
        AfterAll {
            if ($script:OriginalGetConfig_WithScanConfigs) {
                Set-Item function:Get-Config -Value $script:OriginalGetConfig_WithScanConfigs
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

        It 'Returns scan configurations and filters out trashed items' {
            Mock Invoke-RestMethod {
                return @{
                    items = @(
                        @{ config_id = 'config-1'; name = 'Production Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-1' } },
                        @{ config_id = 'config-2'; name = 'Trashed Scan'; in_trash = $true; last_scan = @{ scan_id = 'scan-2' } },
                        @{ config_id = 'config-3'; name = 'Development Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-3' } }
                    )
                    pagination = @{ total = 3; limit = 200 }
                }
            }

            $result = Get-TenableWASScanConfigs
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'Development Scan'
            $result[1].Name | Should -Be 'Production Scan'
            ($result | Where-Object { $_.Name -eq 'Trashed Scan' }) | Should -BeNullOrEmpty
        }

        It 'Handles pagination with duplicate detection' {
            $script:callCount = 0
            Mock Invoke-RestMethod {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return @{
                        items = @(
                            @{ config_id = 'config-1'; name = 'Scan 1'; in_trash = $false; last_scan = @{ scan_id = 'scan-1' } }
                        )
                        pagination = @{ total = 400; limit = 200 }
                    }
                } else {
                    # Return same item again (duplicate pagination issue)
                    return @{
                        items = @(
                            @{ config_id = 'config-1'; name = 'Scan 1'; in_trash = $false; last_scan = @{ scan_id = 'scan-1' } }
                        )
                        pagination = @{ total = 400; limit = 200 }
                    }
                }
            }

            $result = Get-TenableWASScanConfigs
            # Should stop after detecting duplicates and return only one unique scan
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 'scan-1'
        }

        It 'Returns sorted results by Name and Id' {
            Mock Invoke-RestMethod {
                return @{
                    items = @(
                        @{ config_id = 'config-z'; name = 'Zebra Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-z' } },
                        @{ config_id = 'config-a'; name = 'Alpha Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-a' } },
                        @{ config_id = 'config-m'; name = 'Middle Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-m' } }
                    )
                    pagination = @{ total = 3; limit = 200 }
                }
            }

            $result = Get-TenableWASScanConfigs
            $result.Count | Should -Be 3
            $result[0].Name | Should -Be 'Alpha Scan'
            $result[1].Name | Should -Be 'Middle Scan'
            $result[2].Name | Should -Be 'Zebra Scan'
        }

        It 'Skips configurations without last_scan' {
            Mock Invoke-RestMethod {
                return @{
                    items = @(
                        @{ config_id = 'config-1'; name = 'Active Scan'; in_trash = $false; last_scan = @{ scan_id = 'scan-1' } },
                        @{ config_id = 'config-2'; name = 'Never Run Scan'; in_trash = $false; last_scan = $null },
                        @{ config_id = 'config-3'; name = 'No Last Scan'; in_trash = $false },
                        @{ config_id = 'config-4'; name = 'Another Active'; in_trash = $false; last_scan = @{ scan_id = 'scan-4' } }
                    )
                    pagination = @{ total = 4; limit = 200 }
                }
            }

            $result = Get-TenableWASScanConfigs
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'Active Scan'
            $result[1].Name | Should -Be 'Another Active'
            ($result | Where-Object { $_.Name -eq 'Never Run Scan' }) | Should -BeNullOrEmpty
            ($result | Where-Object { $_.Name -eq 'No Last Scan' }) | Should -BeNullOrEmpty
        }

        It 'Throws an error when API call fails' {
            Mock Invoke-RestMethod { throw "API Error" }

            { Get-TenableWASScanConfigs } | Should -Throw -ExpectedMessage "Failed to fetch Tenable WAS configs*"
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
