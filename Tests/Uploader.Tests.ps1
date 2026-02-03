# Pester tests for Uploader module
BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../modules'
    . (Join-Path $moduleDir 'Logging.ps1')
    . (Join-Path $moduleDir 'Config.ps1')
    . (Join-Path $moduleDir 'Uploader.ps1')
    
    # Initialize logging for tests
    $testLogDir = Join-Path $TestDrive 'logs'
    New-Item -ItemType Directory -Path $testLogDir -Force | Out-Null
    Initialize-Log -LogDirectory $testLogDir -LogFileName 'uploader-tests.log' -Overwrite
    
    # Preserve environment variables
    $script:OriginalDojoApiKey = $env:DOJO_API_KEY
}

AfterAll {
    # Restore environment variables
    if ($null -ne $script:OriginalDojoApiKey) {
        $env:DOJO_API_KEY = $script:OriginalDojoApiKey
    } else {
        Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
    }
}

Describe 'Upload-DefectDojoScan' {
    
    Context 'When uploading with tags' {
        BeforeAll {
            # Set up test environment
            $env:DOJO_API_KEY = 'test-api-key-12345'
            
            # Create test file
            $script:testFile = Join-Path $TestDrive 'test-scan.csv'
            Set-Content -Path $script:testFile -Value 'test,scan,data'
            
            # Mock Get-Config
            Mock Get-Config {
                return @{
                    ApiBaseUrls = @{
                        DefectDojo = 'https://defectdojo.example.com/api/v2'
                    }
                    DefectDojo = @{
                        MinimumSeverity = 'Low'
                    }
                }
            }
            
            # Mock Invoke-RestMethod
            Mock Invoke-RestMethod {
                return @{
                    success = $true
                    test_id = 123
                }
            }
            
            # Mock Write-Log
            Mock Write-Log {}
        }
        
        It 'Includes tags in form data when Tags parameter provided' {
            $tags = @('security-scan', 'automated')
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'Tenable Scan' `
                                   -Tags $tags
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form.ContainsKey('tags') -and 
                $Form['tags'].Count -eq 2 -and
                $Form['tags'] -contains 'security-scan' -and
                $Form['tags'] -contains 'automated'
            }
        }
        
        It 'Sets apply_tags_to_findings when ApplyTagsToFindings is true' {
            $tags = @('test-tag')
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'Burp Scan' `
                                   -Tags $tags `
                                   -ApplyTagsToFindings $true
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form.ContainsKey('apply_tags_to_findings') -and 
                $Form['apply_tags_to_findings'] -eq $true
            }
        }
        
        It 'Sets apply_tags_to_endpoints when ApplyTagsToEndpoints is true' {
            $tags = @('endpoint-tag')
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'SARIF' `
                                   -Tags $tags `
                                   -ApplyTagsToEndpoints $true
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form.ContainsKey('apply_tags_to_endpoints') -and 
                $Form['apply_tags_to_endpoints'] -eq $true
            }
        }
        
        It 'Filters out empty tags from array' {
            $tags = @('valid-tag', '', '  ', 'another-tag', $null)
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'Tenable Scan' `
                                   -Tags $tags
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form.ContainsKey('tags') -and 
                $Form['tags'].Count -eq 2 -and
                $Form['tags'] -contains 'valid-tag' -and
                $Form['tags'] -contains 'another-tag'
            }
        }
        
        It 'Logs tag information when tags are applied' {
            $tags = @('log-test-tag')
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'Burp Scan' `
                                   -Tags $tags
            
            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like '*Uploading with tags: log-test-tag*' -and 
                $Level -eq 'INFO'
            }
        }
        
        It 'Includes both flags when ApplyTagsToFindings and ApplyTagsToEndpoints are true' {
            $tags = @('multi-flag-tag')
            
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 123 `
                                   -ScanType 'SARIF' `
                                   -Tags $tags `
                                   -ApplyTagsToFindings $true `
                                   -ApplyTagsToEndpoints $true
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form.ContainsKey('apply_tags_to_findings') -and 
                $Form['apply_tags_to_findings'] -eq $true -and
                $Form.ContainsKey('apply_tags_to_endpoints') -and 
                $Form['apply_tags_to_endpoints'] -eq $true
            }
        }
    }
    
    Context 'When uploading without tags' {
        BeforeAll {
            $env:DOJO_API_KEY = 'test-api-key-12345'
            $script:testFile = Join-Path $TestDrive 'test-scan-no-tags.csv'
            Set-Content -Path $script:testFile -Value 'test,scan,data'
            
            Mock Get-Config {
                return @{
                    ApiBaseUrls = @{
                        DefectDojo = 'https://defectdojo.example.com/api/v2'
                    }
                    DefectDojo = @{
                        MinimumSeverity = 'Low'
                    }
                }
            }
            
            Mock Invoke-RestMethod {
                return @{ success = $true }
            }
            
            Mock Write-Log {}
        }
        
        It 'Does not include tags in form data when Tags parameter omitted' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 456 `
                                   -ScanType 'Tenable Scan'
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                -not $Form.ContainsKey('tags')
            }
        }
        
        It 'Does not include tags when Tags parameter is empty array' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 456 `
                                   -ScanType 'Burp Scan' `
                                   -Tags @()
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                -not $Form.ContainsKey('tags')
            }
        }
        
        It 'Does not include tags when all tags are empty strings' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 456 `
                                   -ScanType 'SARIF' `
                                   -Tags @('', '  ', $null)
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                -not $Form.ContainsKey('tags')
            }
        }
        
        It 'Does not log tag information when no tags applied' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 456 `
                                   -ScanType 'Tenable Scan' `
                                   -Tags @()
            
            Assert-MockCalled Write-Log -Times 0 -ParameterFilter {
                $Message -like '*Uploading with tags:*'
            }
        }
        
        It 'Does not include tag flags when no tags provided' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 456 `
                                   -ScanType 'Burp Scan' `
                                   -ApplyTagsToFindings $true `
                                   -ApplyTagsToEndpoints $true
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                -not $Form.ContainsKey('tags') -and
                -not $Form.ContainsKey('apply_tags_to_findings') -and
                -not $Form.ContainsKey('apply_tags_to_endpoints')
            }
        }
    }
    
    Context 'Tag parameter validation' {
        BeforeAll {
            $env:DOJO_API_KEY = 'test-api-key-12345'
            $script:testFile = Join-Path $TestDrive 'test-validation.csv'
            Set-Content -Path $script:testFile -Value 'test,data'
            
            Mock Get-Config {
                return @{
                    ApiBaseUrls = @{
                        DefectDojo = 'https://defectdojo.example.com/api/v2'
                    }
                    DefectDojo = @{
                        MinimumSeverity = 'Low'
                    }
                }
            }
            
            Mock Invoke-RestMethod { return @{ success = $true } }
            Mock Write-Log {}
        }
        
        It 'Accepts single tag' {
            { Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags @('single') } | 
                Should -Not -Throw
        }
        
        It 'Accepts multiple tags' {
            { Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags @('tag1', 'tag2', 'tag3') } | 
                Should -Not -Throw
        }
        
        It 'Accepts tags with special characters' {
            $specialTags = @('tag-with-dash', 'tag_with_underscore', 'tag.with.dot')
            { Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags $specialTags } | 
                Should -Not -Throw
        }
        
        It 'Handles very long tag strings' {
            $longTag = 'x' * 100
            { Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags @($longTag) } | 
                Should -Not -Throw
        }
        
        It 'Handles tags with spaces' {
            $spaceTags = @('tag with spaces', 'another tag')
            { Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags $spaceTags } | 
                Should -Not -Throw
        }
    }
    
    Context 'Core upload functionality with tags' {
        BeforeAll {
            $env:DOJO_API_KEY = 'test-api-key-12345'
            $script:testFile = Join-Path $TestDrive 'core-test.csv'
            Set-Content -Path $script:testFile -Value 'test,data'
            
            Mock Get-Config {
                return @{
                    ApiBaseUrls = @{
                        DefectDojo = 'https://defectdojo.example.com/api/v2/'
                    }
                    DefectDojo = @{
                        MinimumSeverity = 'Medium'
                    }
                }
            }
            
            Mock Invoke-RestMethod { return @{ success = $true } }
            Mock Write-Log {}
        }
        
        It 'Sends request to correct endpoint' {
            Upload-DefectDojoScan -FilePath $script:testFile -TestId 1 -Tags @('test')
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://defectdojo.example.com/api/v2/reimport-scan/'
            }
        }
        
        It 'Includes all required form fields with tags' {
            Upload-DefectDojoScan -FilePath $script:testFile `
                                   -TestId 999 `
                                   -ScanType 'Custom Scan' `
                                   -CloseOldFindings $true `
                                   -Tags @('required-fields-test')
            
            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
                $Form['test'] -eq 999 -and
                $Form['scan_type'] -eq 'Custom Scan' -and
                $Form['close_old_findings'] -eq $true -and
                $Form['minimum_severity'] -eq 'Medium' -and
                $Form.ContainsKey('file') -and
                $Form.ContainsKey('tags')
            }
        }
    }
}
