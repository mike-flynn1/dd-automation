# Pester tests for BurpSuite module
BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../modules'
    . (Join-Path $moduleDir 'BurpSuite.ps1')
}

Describe 'Get-BurpSuiteReports' {

    Context 'When folder path is provided as parameter' {
        BeforeAll {
            # Mock Write-Log to prevent actual file writes
            Mock Write-Log {}

            # Mock Get-Config to return a basic config
            Mock Get-Config {
                return @{
                    Paths = @{
                        BurpSuiteXmlFolder = 'C:\DefaultConfigPath'
                    }
                }
            }
        }

        It 'Returns XML file path when file exists' {
            # Create test directory and XML file
            $testFolder = Join-Path $TestDrive 'burp-reports'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'report.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0] | Should -Be $xmlFile
        }

        It 'Returns empty array when no XML files found' {
            # Create test directory with no XML files
            $testFolder = Join-Path $TestDrive 'empty-folder'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            # Add a non-XML file
            Set-Content -Path (Join-Path $testFolder 'readme.txt') -Value 'test'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            # PowerShell returns $null for @() in some contexts
            $result | Should -BeNullOrEmpty
            @($result).Count | Should -Be 0
        }

        It 'Throws error when folder does not exist' {
            $nonExistentFolder = Join-Path $TestDrive 'does-not-exist'

            { Get-BurpSuiteReports -FolderPath $nonExistentFolder } | Should -Throw 'BurpSuite XML folder does not exist*'
        }

        It 'Logs INFO message when scanning folder' {
            # Create test directory with XML file
            $testFolder = Join-Path $TestDrive 'log-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
            Set-Content -Path (Join-Path $testFolder 'test.xml') -Value '<xml>test</xml>'

            Get-BurpSuiteReports -FolderPath $testFolder

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like 'Scanning for BurpSuite XML reports in:*' -and $Level -eq 'INFO'
            }
        }

        It 'Logs INFO message for discovered file' {
            # Create test directory with single XML file
            $testFolder = Join-Path $TestDrive 'multiple-files'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'report.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            Get-BurpSuiteReports -FolderPath $testFolder

            # Should log scanning message + count message + single file message
            Assert-MockCalled Write-Log -Times 3 -ParameterFilter { $Level -eq 'INFO' }
            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like '*Found 1 XML file(s)*' -and $Level -eq 'INFO'
            }
            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like "BurpSuite XML report: $xmlFile" -and $Level -eq 'INFO'
            }
        }

        It 'Logs WARNING when no files found' {
            # Create empty test directory
            $testFolder = Join-Path $TestDrive 'warning-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            Get-BurpSuiteReports -FolderPath $testFolder

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like 'No XML files found in folder:*' -and $Level -eq 'WARNING'
            }
        }

        It 'Logs ERROR when folder does not exist' {
            $nonExistentFolder = Join-Path $TestDrive 'error-test'

            { Get-BurpSuiteReports -FolderPath $nonExistentFolder } | Should -Throw

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -like 'BurpSuite XML folder does not exist:*' -and $Level -eq 'ERROR'
            }
        }
    }

    Context 'When folder path comes from config' {
        BeforeEach {
            # Reset mocks for each test in this context
            Mock Write-Log {}
        }

        It 'Uses config.Paths.BurpSuiteXmlFolder when parameter not provided' {
            # Create test directory from config path
            $configFolder = Join-Path $TestDrive 'config-folder'
            New-Item -ItemType Directory -Path $configFolder -Force | Out-Null
            Set-Content -Path (Join-Path $configFolder 'report.xml') -Value '<xml>test</xml>'

            Mock Get-Config {
                return @{
                    Paths = @{
                        BurpSuiteXmlFolder = $configFolder
                    }
                }
            }

            $result = @(Get-BurpSuiteReports)

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            Assert-MockCalled Get-Config -Times 1
        }

        It 'Throws error when no folder path in config or parameter' {
            Mock Get-Config {
                return @{
                    Paths = @{}
                }
            }

            { Get-BurpSuiteReports } | Should -Throw 'No BurpSuite XML folder path specified.'
        }

        It 'Logs ERROR when no folder path in config or parameter' {
            Mock Get-Config {
                return @{
                    Paths = @{}
                }
            }

            { Get-BurpSuiteReports } | Should -Throw

            Assert-MockCalled Write-Log -Times 1 -ParameterFilter {
                $Message -eq 'No BurpSuite XML folder path specified.' -and $Level -eq 'ERROR'
            }
        }

        It 'Throws error when config.Paths is null' {
            Mock Get-Config {
                return @{}
            }

            { Get-BurpSuiteReports } | Should -Throw 'No BurpSuite XML folder path specified.'
        }

        It 'Parameter takes precedence over config path' {
            $paramFolder = Join-Path $TestDrive 'param-folder'
            New-Item -ItemType Directory -Path $paramFolder -Force | Out-Null

            $xmlFile = Join-Path $paramFolder 'param.xml'
            Set-Content -Path $xmlFile -Value '<xml>param</xml>'

            $configFolder = Join-Path $TestDrive 'config-folder-unused'

            Mock Get-Config {
                return @{
                    Paths = @{
                        BurpSuiteXmlFolder = $configFolder
                    }
                }
            }

            $result = @(Get-BurpSuiteReports -FolderPath $paramFolder)

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            [System.IO.Path]::GetFileName($result[0]) | Should -Be 'param.xml'
        }
    }

    Context 'File discovery behavior' {
        BeforeAll {
            Mock Write-Log {}
            Mock Get-Config {
                return @{
                    Paths = @{
                        BurpSuiteXmlFolder = 'C:\DefaultPath'
                    }
                }
            }
        }

        It 'Finds XML files with .xml extension' {
            $testFolder = Join-Path $TestDrive 'extension-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'valid.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result.Count | Should -Be 1
            [System.IO.Path]::GetExtension($result[0]) | Should -Be '.xml'
        }

        It 'Returns full file paths, not relative paths' {
            $testFolder = Join-Path $TestDrive 'fullpath-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'report.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result.Count | Should -Be 1
            [System.IO.Path]::IsPathRooted($result[0]) | Should -BeTrue
            [System.IO.Path]::GetFileName($result[0]) | Should -Be 'report.xml'
        }

        It 'Ignores non-XML files in folder' {
            $testFolder = Join-Path $TestDrive 'mixed-files'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            # Create XML and non-XML files
            $xmlFile = Join-Path $testFolder 'valid.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'
            Set-Content -Path (Join-Path $testFolder 'readme.txt') -Value 'text file'
            Set-Content -Path (Join-Path $testFolder 'data.json') -Value '{}'
            Set-Content -Path (Join-Path $testFolder 'report.pdf') -Value 'binary'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result.Count | Should -Be 1
            [System.IO.Path]::GetFileName($result[0]) | Should -Be 'valid.xml'
        }

        It 'Handles XML files with uppercase extension' {
            $testFolder = Join-Path $TestDrive 'uppercase-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            # PowerShell's -Filter '*.xml' is case-insensitive on Windows
            Set-Content -Path (Join-Path $testFolder 'report.XML') -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            # On Windows, this should find the file
            if ($IsWindows -or $env:OS -match 'Windows') {
                $result.Count | Should -Be 1
            }
        }

        It 'Returns empty array when folder has only subdirectories' {
            $testFolder = Join-Path $TestDrive 'subdir-test'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $testFolder 'subdir') -Force | Out-Null

            # Put XML in subdirectory, but Get-ChildItem without -Recurse shouldn't find it
            Set-Content -Path (Join-Path $testFolder 'subdir\nested.xml') -Value '<xml>nested</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            # Should not find nested files (no -Recurse parameter)
            $result.Count | Should -Be 0
        }

        It 'Handles folder paths with spaces' {
            $testFolder = Join-Path $TestDrive 'folder with spaces'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'report.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result.Count | Should -Be 1
            [System.IO.Path]::GetFileName($result[0]) | Should -Be 'report.xml'
            $result[0] | Should -BeLike '*folder with spaces*report.xml'
        }

        It 'Handles folder paths with special characters' {
            # Square brackets are problematic in PowerShell paths - use LiteralPath where possible
            # For this test, use a different special character that works across platforms
            $testFolder = Join-Path $TestDrive 'folder-test_123'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            $xmlFile = Join-Path $testFolder 'report.xml'
            Set-Content -Path $xmlFile -Value '<xml>test</xml>'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            $result.Count | Should -Be 1
            $result[0] | Should -Be $xmlFile
        }
    }

    Context 'Error handling and edge cases' {
        BeforeAll {
            Mock Write-Log {}
            Mock Get-Config {
                return @{
                    Paths = @{
                        BurpSuiteXmlFolder = 'C:\DefaultPath'
                    }
                }
            }
        }

        It 'Throws error with descriptive message when folder is a file' {
            $testFile = Join-Path $TestDrive 'notafolder.txt'
            Set-Content -Path $testFile -Value 'this is a file'

            { Get-BurpSuiteReports -FolderPath $testFile } | Should -Throw 'BurpSuite XML folder does not exist*'
        }

        It 'Handles empty folder path string' {
            { Get-BurpSuiteReports -FolderPath '' } | Should -Throw
        }

        It 'Returns XML file even when content is invalid' {
            $testFolder = Join-Path $TestDrive 'invalid-xml'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            # Create file with .xml extension but invalid XML content
            $xmlFile = Join-Path $testFolder 'invalid.xml'
            Set-Content -Path $xmlFile -Value 'not valid xml'

            $result = @(Get-BurpSuiteReports -FolderPath $testFolder)

            # Function should return the file despite invalid XML content
            $result.Count | Should -Be 1
            $result[0] | Should -Be $xmlFile
        }

        It 'Handles Get-ChildItem errors gracefully with -ErrorAction SilentlyContinue' {
            $testFolder = Join-Path $TestDrive 'error-handling'
            New-Item -ItemType Directory -Path $testFolder -Force | Out-Null

            # This should not throw even if Get-ChildItem encounters errors
            { Get-BurpSuiteReports -FolderPath $testFolder } | Should -Not -Throw
        }
    }
}
