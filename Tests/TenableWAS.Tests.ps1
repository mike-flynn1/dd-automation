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

    Context 'When credentials are missing' {
        BeforeAll {
            $script:OriginalGetConfig_MissingCreds = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{ ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
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
            Mock Get-TenableWASScanConfigs {
                return @(
                    @{ Name = 'Test Scan'; Id = 'dummy-id' }
                )
            }
            { Export-TenableWASScan -ScanName 'Test Scan' } | Should -Throw 'Missing Tenable WAS API credentials*'
        }
    }

    Context 'When ScanName is provided instead of ScanId' {
        BeforeAll {
            $script:OriginalGetConfig_ScanName = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            $script:OriginalGetTenableWASScanConfigs = (Get-Command Get-TenableWASScanConfigs -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            
            Set-Item function:Get-Config -Value { return @{ ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-scanname.log' -Overwrite
            $env:TENWAS_ACCESS_KEY = 'test-key'
            $env:TENWAS_SECRET_KEY = 'test-secret'
        }
        AfterAll {
            if ($script:OriginalGetConfig_ScanName) {
                Set-Item function:Get-Config -Value $script:OriginalGetConfig_ScanName
            } else {
                Remove-Item function:Get-Config -ErrorAction SilentlyContinue
            }

            if ($script:OriginalGetTenableWASScanConfigs) {
                Set-Item function:Get-TenableWASScanConfigs -Value $script:OriginalGetTenableWASScanConfigs
            } else {
                Remove-Item function:Get-TenableWASScanConfigs -ErrorAction SilentlyContinue
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

        It 'Resolves ScanName to ScanId and uses scan name in filename' {
            Mock Get-TenableWASScanConfigs {
                return @(
                    @{ Name = 'Production Scan'; Id = 'scan-id-123' },
                    @{ Name = 'SBIR DTK Console'; Id = 'scan-id-456' }
                )
            }
            Mock Invoke-RestMethod { }

            $result = Export-TenableWASScan -ScanName 'SBIR DTK Console'
            
            # Verify the result filename contains the scan name (without -report suffix)
            $result | Should -Match 'SBIR DTK Console\.csv$'
        }

        It 'Throws error when ScanName does not exist' {
            Mock Get-TenableWASScanConfigs -MockWith {
                return @(
                    @{ Name = 'Production Scan'; Id = 'scan-id-123' }
                )
            }

            { Export-TenableWASScan -ScanName 'NonExistent Scan' } | Should -Throw 'No scan found with name: NonExistent Scan'
        }

        It 'Skips scan lookup when ScanId is provided' {
            Mock Get-TenableWASScanConfigs { throw 'Lookup should not be called' }
            Mock Invoke-RestMethod { }

            { Export-TenableWASScan -ScanName 'Provided Scan' -ScanId 'scan-id-999' } | Should -Not -Throw
        }

        It 'Surfaces friendly message when report is still generating' {
            Mock Get-TenableWASScanConfigs {
                return @(
                    @{ Name = 'Production Scan'; Id = 'scan-id-123' }
                )
            }

            Mock Invoke-RestMethod -ParameterFilter { $Method -eq 'Put' } { }
            Mock Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } {
                throw [System.Exception]::new('Scan report is still in progress')
            }
            Mock Write-Log { }

            { Export-TenableWASScan -ScanName 'Production Scan' } | Should -Throw '*report not ready*'
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'WARNING' -and $Message -match 'report not ready' }
        }
    }
}

Describe 'Invoke-Workflow-TenableWAS (Unit)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'AutomationWorkflows.ps1')
    }

    BeforeEach {
        # Fresh config per test
        $script:config = @{
            Tools = @{ DefectDojo = $false }
            DefectDojo = @{ CloseOldFindings = $false }
            TenableWASSelectedScans = @()
        }

        # Quiet logging for unit tests
        Mock Write-Log {}

        # Default mocks (overridden per test when needed)
        Mock Export-TenableWASScan {}
        Mock Get-EngagementIdForTool {}
        Mock Get-DefectDojoTestType {}
        Mock Get-DefectDojoTests {}
        Mock New-DefectDojoTest {}
        Mock Upload-DefectDojoScan {}
    }

    It 'Skips when no scans are selected' {
        $script:config.TenableWASSelectedScans = @()

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Tool | Should -Be 'TenableWAS'
        $result.Skipped | Should -Be 1
        $result.Total | Should -Be 0
        $result.Success | Should -Be 0
        $result.Failed | Should -Be 0
        Should -Not -Invoke Export-TenableWASScan
    }

    It 'Skips string scan entries and logs error' {
        $script:config.TenableWASSelectedScans = @('just-a-name')

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Skipped | Should -Be 1
        $result.Total | Should -Be 1
        $result.Success | Should -Be 0
        $result.Failed | Should -Be 0
        Should -Not -Invoke Export-TenableWASScan
        Should -Invoke Write-Log -ParameterFilter { $Level -eq 'ERROR' -and $Message -match 'Scan config is string' }
    }

    It 'Exports scan when DefectDojo is disabled' {
        $script:config.TenableWASSelectedScans = @([pscustomobject]@{ Name = 'Scan A'; Id = 'id-1' })
        $script:config.Tools.DefectDojo = $false

        Mock Export-TenableWASScan { return ' C:\tmp\scanA.csv ' }

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Success | Should -Be 1
        $result.Failed | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Total | Should -Be 1
        Should -Invoke Export-TenableWASScan -Times 1 -ParameterFilter { $ScanName -eq 'Scan A' }
        Should -Not -Invoke Upload-DefectDojoScan
    }

    It 'Reuses existing DefectDojo test when present' {
        $script:config.Tools.DefectDojo = $true
        $script:config.DefectDojo.CloseOldFindings = $true
        $script:config.TenableWASSelectedScans = @([pscustomobject]@{ Name = 'Scan A'; Id = 'id-1' })

        Mock Get-EngagementIdForTool { return 10 }
        Mock Get-DefectDojoTestType { return 99 }
        Mock Get-DefectDojoTests { return @([pscustomobject]@{ Title = 'Scan A (Tenable WAS)'; Id = 123 }) }
        Mock Export-TenableWASScan { return ' C:\tmp\scanA.csv ' }

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Success | Should -Be 1
        $result.Failed | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Total | Should -Be 1

        Should -Invoke Upload-DefectDojoScan -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\tmp\scanA.csv' -and
            $TestId -eq 123 -and
            $ScanType -eq 'Tenable Scan' -and
            $CloseOldFindings -eq $true
        }
        Should -Not -Invoke New-DefectDojoTest
    }

    It 'Creates new DefectDojo test when none exists' {
        $script:config.Tools.DefectDojo = $true
        $script:config.DefectDojo.CloseOldFindings = $false
        $script:config.TenableWASSelectedScans = @([pscustomobject]@{ Name = 'Scan B'; Id = 'id-2' })

        Mock Get-EngagementIdForTool { return 20 }
        Mock Get-DefectDojoTestType { return 88 }
        Mock Get-DefectDojoTests { return @() }
        Mock New-DefectDojoTest { return [pscustomobject]@{ Id = 77; Title = 'Scan B (Tenable WAS)' } }
        Mock Export-TenableWASScan { return 'C:\tmp\scanB.csv' }

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Success | Should -Be 1
        $result.Failed | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Total | Should -Be 1

        Should -Invoke New-DefectDojoTest -Times 1 -ParameterFilter {
            $EngagementId -eq 20 -and
            $TestName -eq 'Scan B (Tenable WAS)' -and
            $TestType -eq 88
        }
        Should -Invoke Upload-DefectDojoScan -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\tmp\scanB.csv' -and
            $TestId -eq 77 -and
            $ScanType -eq 'Tenable Scan'
        }
    }

    It 'Fails early when engagement ID is missing for DefectDojo uploads' {
        $script:config.Tools.DefectDojo = $true
        $script:config.TenableWASSelectedScans = @([pscustomobject]@{ Name = 'Scan C'; Id = 'id-3' })

        Mock Get-EngagementIdForTool { return $null }

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Failed | Should -Be 1
        $result.Success | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Total | Should -Be 0
        Should -Not -Invoke Export-TenableWASScan
        Should -Invoke Write-Log -ParameterFilter { $Level -eq 'ERROR' -and $Message -match 'engagement ID' }
    }

    It 'Counts failure when export throws' {
        $script:config.Tools.DefectDojo = $false
        $script:config.TenableWASSelectedScans = @([pscustomobject]@{ Name = 'Scan D'; Id = 'id-4' })

        Mock Export-TenableWASScan { throw 'Export failed' }

        $result = Invoke-Workflow-TenableWAS -Config $script:config

        $result.Failed | Should -Be 1
        $result.Success | Should -Be 0
        $result.Skipped | Should -Be 0
        $result.Total | Should -Be 1
        Should -Not -Invoke Upload-DefectDojoScan
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
        It 'Returns empty array when credentials are missing' {
            Mock Write-Log { }
            $result = Get-TenableWASScanConfigs
            $result | Should -BeNullOrEmpty
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

        It 'Returns empty array when API call fails' {
            Mock Invoke-RestMethod { throw "API Error" }
            Mock Write-Log { }

            $result = Get-TenableWASScanConfigs
            $result | Should -BeNullOrEmpty
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
        $script:integrationScanNames = @()

        # Get scan names from configuration
        if ($script:integrationConfig.TenableWASScanNames -and $script:integrationConfig.TenableWASScanNames.Count -gt 0) {
            $script:integrationScanNames = @($script:integrationConfig.TenableWASScanNames)
        }

        if ($script:integrationScanNames.Count -eq 0) {
            Throw 'TenableWASScanNames array not set in configuration.'
        }
    }

    It 'Generates and downloads a report CSV file using scan names' {
        # Use first scan name from configuration
        $testScanName = $script:integrationScanNames[0]

        try {
            $outPath = Export-TenableWASScan -ScanName $testScanName
        } catch {
            if ($_.Exception.Message -match 'report not ready|in progress|running') {
                Write-Warning "Skipping TenableWAS integration: scan '$testScanName' is still in progress."
                Set-ItResult -Skipped -Because "Scan '$testScanName' is still in progress; report not ready."
                return
            }

            throw
        }
        if ($outPath -is [System.IO.FileSystemInfo]) {
            $outPath = $outPath.FullName
        } elseif ($outPath) {
            $outPath = [string]$outPath
        }

        # Build expected filename based on scan name
        $expectedFileName = "$testScanName.csv"
        $expectedPath = Join-Path ([System.IO.Path]::GetTempPath()) $expectedFileName
        $candidatePaths = @($outPath, $expectedPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $resolvedOutPath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $resolvedOutPath) {
            $resolvedOutPath = $candidatePaths | Select-Object -First 1
        }

        $resolvedOutPath | Should -Not -BeNullOrEmpty
        $fileName = [System.IO.Path]::GetFileName($resolvedOutPath)
        $fileName | Should -Match ([regex]::Escape($testScanName) + "\.csv$")

        Test-Path $resolvedOutPath | Should -BeTrue
        (Get-Item $resolvedOutPath).Length | Should -BeGreaterThan 0
    }
}
