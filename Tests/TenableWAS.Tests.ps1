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
    }
}

Describe 'Process-TenableWAS (Unit)' {
    BeforeAll {
        # Load all required modules for Process-TenableWAS testing
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')
        . (Join-Path $PSScriptRoot '../modules/DefectDojo.ps1')
        . (Join-Path $PSScriptRoot '../modules/Uploader.ps1')

        # Load Launch.ps1 to get Process-TenableWAS function
        # We need to suppress the GUI initialization and just load the functions
        $script:SkipGuiInit = $true

        # Define Write-GuiMessage stub before loading Launch.ps1 to avoid GUI dependencies
        if (-not (Get-Command Write-GuiMessage -ErrorAction SilentlyContinue)) {
            function global:Write-GuiMessage {
                param([string]$Message, [string]$Level = 'INFO')
                Write-Log -Message $Message -Level $Level
            }
        }

        # Source the Launch.ps1 to get Process-TenableWAS, but we need to handle the GUI initialization
        # Extract just the function definition instead of running the entire script
        $launchScript = Get-Content (Join-Path $PSScriptRoot '../Launch.ps1') -Raw

        # Extract Process-TenableWAS function from Launch.ps1
        $functionPattern = '(?s)function Process-TenableWAS\s*\{.*?\n\}\s*(?=\n\s*function|\n\s*#|$)'
        if ($launchScript -match $functionPattern) {
            $functionDef = $Matches[0]
            Invoke-Expression $functionDef
        }

        Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'process-tenablewas.log' -Overwrite

        # Set up environment for testing
        $env:TENWAS_ACCESS_KEY = 'test-key'
        $env:TENWAS_SECRET_KEY = 'test-secret'
        $env:DOJO_API_KEY = 'test-dojo-key'
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

    Context 'When no scans are selected' {
        It 'Returns early with warning message' {
            Mock Write-GuiMessage { }

            $config = @{
                TenableWASSelectedScans = @()
                Tools = @{ DefectDojo = $true }
            }

            # Should not throw, just log warning
            { Process-TenableWAS -Config $config } | Should -Not -Throw

            # Verify warning was logged
            Should -Invoke Write-GuiMessage -ParameterFilter { $Level -eq 'WARNING' -and $Message -match 'No TenableWAS scans selected' }
        }
    }

    Context 'When no DefectDojo engagement is selected' {
        It 'Returns early with error message' {
            Mock Write-GuiMessage { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Test Scan'; Id = 'scan-1' }
                )
                Tools = @{ DefectDojo = $true }
            }

            # Create mock cmbDDEng with no selection
            $script:cmbDDEng = [PSCustomObject]@{ SelectedItem = $null }

            # Should not throw, just log error
            { Process-TenableWAS -Config $config } | Should -Not -Throw

            # Verify error was logged
            Should -Invoke Write-GuiMessage -ParameterFilter { $Level -eq 'ERROR' -and $Message -match 'No DefectDojo engagement selected' }
        }
    }

    Context 'When processing single scan with new test creation' {
        It 'Creates new test and uploads scan successfully' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests { return @() }  # No existing tests
            Mock New-DefectDojoTest {
                return [PSCustomObject]@{ Id = 100; Name = $TestName }
            }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Production Scan'; Id = 'scan-123' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            Process-TenableWAS -Config $config

            # Verify export was called
            Should -Invoke Export-TenableWASScan -Times 1 -ParameterFilter { $ScanName -eq 'Production Scan' }

            # Verify test creation was called with correct parameters
            Should -Invoke New-DefectDojoTest -Times 1 -ParameterFilter {
                $EngagementId -eq 10 -and
                $TestName -eq 'Production Scan (Tenable WAS)' -and
                $TestType -eq 89
            }

            # Verify upload was called
            Should -Invoke Upload-DefectDojoScan -Times 1 -ParameterFilter {
                $TestId -eq 100 -and
                $ScanType -eq 'Tenable Scan'
            }

            # Verify success message
            Should -Invoke Write-GuiMessage -ParameterFilter { $Message -match 'All 1 TenableWAS scans uploaded successfully' }
        }
    }

    Context 'When processing scan with existing test (exact match)' {
        It 'Reuses existing test instead of creating new one' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests {
                return @(
                    [PSCustomObject]@{
                        id = 50
                        title = 'Production Scan (Tenable WAS)'
                        test_type_name = 'Tenable Scan'
                    }
                )
            }
            Mock New-DefectDojoTest { throw 'Should not be called' }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Production Scan'; Id = 'scan-123' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            Process-TenableWAS -Config $config

            # Verify export was called
            Should -Invoke Export-TenableWASScan -Times 1

            # Verify test creation was NOT called
            Should -Invoke New-DefectDojoTest -Times 0

            # Verify upload used existing test ID
            Should -Invoke Upload-DefectDojoScan -Times 1 -ParameterFilter { $TestId -eq 50 }

            # Verify message indicates existing test was used
            Should -Invoke Write-GuiMessage -ParameterFilter { $Message -match 'Using existing DefectDojo test' }
        }
    }

    Context 'When processing scan with existing test (legacy name match)' {
        It 'Matches test with scan name only (backward compatibility)' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests {
                return @(
                    [PSCustomObject]@{
                        id = 75
                        title = 'Production Scan'  # Legacy naming without suffix
                        test_type_name = 'Tenable Scan'
                    }
                )
            }
            Mock New-DefectDojoTest { throw 'Should not be called' }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Production Scan'; Id = 'scan-123' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            Process-TenableWAS -Config $config

            # Verify test creation was NOT called (matched legacy name)
            Should -Invoke New-DefectDojoTest -Times 0

            # Verify upload used existing test ID
            Should -Invoke Upload-DefectDojoScan -Times 1 -ParameterFilter { $TestId -eq 75 }
        }
    }

    Context 'When processing multiple scans' {
        It 'Creates/uses separate test for each scan' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan {
                param($ScanName)
                return "C:\Temp\$ScanName.csv"
            }
            Mock Get-DefectDojoTests {
                return @(
                    [PSCustomObject]@{ id = 60; title = 'Scan A (Tenable WAS)' }
                )
            }
            Mock New-DefectDojoTest {
                return [PSCustomObject]@{ Id = 101; Name = $TestName }
            }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Scan A'; Id = 'scan-a' },
                    @{ Name = 'Scan B'; Id = 'scan-b' },
                    @{ Name = 'Scan C'; Id = 'scan-c' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            Process-TenableWAS -Config $config

            # Verify each scan was exported
            Should -Invoke Export-TenableWASScan -Times 3

            # Verify Scan A used existing test (no creation)
            # Verify Scan B and C created new tests
            Should -Invoke New-DefectDojoTest -Times 2

            # Verify all scans were uploaded
            Should -Invoke Upload-DefectDojoScan -Times 3

            # Verify success message shows all 3 scans
            Should -Invoke Write-GuiMessage -ParameterFilter { $Message -match 'All 3 TenableWAS scans uploaded successfully' }
        }
    }

    Context 'When test creation fails' {
        It 'Logs error and continues to next scan' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests { return @() }
            Mock New-DefectDojoTest { throw 'API Error: Test creation failed' }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Scan 1'; Id = 'scan-1' },
                    @{ Name = 'Scan 2'; Id = 'scan-2' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            Process-TenableWAS -Config $config

            # Verify both scans were attempted
            Should -Invoke Export-TenableWASScan -Times 2
            Should -Invoke New-DefectDojoTest -Times 2

            # Verify no uploads occurred (test creation failed)
            Should -Invoke Upload-DefectDojoScan -Times 0

            # Verify error summary
            Should -Invoke Write-GuiMessage -ParameterFilter {
                $Level -eq 'WARNING' -and $Message -match '0 successful, 2 failed'
            }
        }
    }

    Context 'When scan export fails' {
        It 'Logs error and continues to next scan' {
            Mock Write-GuiMessage { }
            # Make Export fail only for 'Failing Scan', succeed for 'Working Scan'
            Mock Export-TenableWASScan {
                param($ScanName)
                if ($ScanName -eq 'Failing Scan') {
                    throw 'API Error: Export failed'
                }
                return 'C:\Temp\Working Scan.csv'
            }
            Mock Get-DefectDojoTests { return @() }
            Mock New-DefectDojoTest { return [PSCustomObject]@{ Id = 100; Name = $TestName } }
            Mock Upload-DefectDojoScan { }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Failing Scan'; Id = 'scan-fail' },
                    @{ Name = 'Working Scan'; Id = 'scan-ok' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            # Should complete without throwing
            { Process-TenableWAS -Config $config } | Should -Not -Throw

            # Verify export was attempted for both scans
            Should -Invoke Export-TenableWASScan -Times 2

            # Verify error message for failed scan
            Should -Invoke Write-GuiMessage -ParameterFilter {
                $Level -eq 'ERROR' -and $Message -match 'TenableWAS processing failed for Failing Scan'
            }

            # Verify summary shows partial success
            Should -Invoke Write-GuiMessage -ParameterFilter {
                $Level -eq 'WARNING' -and $Message -match '1 successful, 1 failed'
            }
        }
    }

    Context 'When upload fails' {
        It 'Logs error and continues to next scan' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests { return @() }
            Mock New-DefectDojoTest { return [PSCustomObject]@{ Id = 100; Name = $TestName } }
            Mock Upload-DefectDojoScan { throw 'API Error: Upload failed' }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Scan 1'; Id = 'scan-1' }
                )
                Tools = @{ DefectDojo = $true }
            }

            $script:cmbDDEng = [PSCustomObject]@{
                SelectedItem = [PSCustomObject]@{ Id = 10; Name = 'Test Engagement' }
            }

            # Should complete without throwing
            { Process-TenableWAS -Config $config } | Should -Not -Throw

            # Verify error was logged
            Should -Invoke Write-GuiMessage -ParameterFilter {
                $Level -eq 'ERROR' -and $Message -match 'TenableWAS processing failed'
            }

            # Verify error summary
            Should -Invoke Write-GuiMessage -ParameterFilter {
                $Level -eq 'WARNING' -and $Message -match '0 successful, 1 failed'
            }
        }
    }

    Context 'When DefectDojo is disabled' {
        It 'Only exports scans without uploading' {
            Mock Write-GuiMessage { }
            Mock Export-TenableWASScan { return 'C:\Temp\test-scan.csv' }
            Mock Get-DefectDojoTests { throw 'Should not be called' }
            Mock New-DefectDojoTest { throw 'Should not be called' }
            Mock Upload-DefectDojoScan { throw 'Should not be called' }

            $config = @{
                TenableWASSelectedScans = @(
                    @{ Name = 'Scan 1'; Id = 'scan-1' }
                )
                Tools = @{ DefectDojo = $false }  # DefectDojo disabled
            }

            Process-TenableWAS -Config $config

            # Verify export was called
            Should -Invoke Export-TenableWASScan -Times 1

            # Verify DefectDojo functions were not called
            Should -Invoke Get-DefectDojoTests -Times 0
            Should -Invoke New-DefectDojoTest -Times 0
            Should -Invoke Upload-DefectDojoScan -Times 0

            # Should not have DefectDojo-specific success message
            Should -Invoke Write-GuiMessage -ParameterFilter { $Message -match 'uploaded successfully to DefectDojo' } -Times 0
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

        $outPath = Export-TenableWASScan -ScanName $testScanName
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
