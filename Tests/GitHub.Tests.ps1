# Pester tests for GitHub module
$env:DDGitHubModulePath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../modules')).Path

Describe 'Get-GitHubRepos' {
    BeforeAll {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'GitHub.ps1')
    }

    BeforeEach {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'Logging.ps1')
        Remove-Item Env:GITHUB_PAT -ErrorAction SilentlyContinue
        $script:TestLogDir = Join-Path $TestDrive 'logs'
        Initialize-Log -LogDirectory $script:TestLogDir -LogFileName 'github-tests.log' -Overwrite
        $script:TestLogFile = Join-Path $script:TestLogDir 'github-tests.log'
    }

    It 'Throws when organizations are not specified' {
        $config = @{
            GitHub = @{
                Orgs = @()
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }

        { Get-GitHubRepos } | Should -Throw 'GitHub organizations not specified.'
    }

    It 'Throws when the GitHub token is missing' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }

        { Get-GitHubRepos } | Should -Throw 'Missing GitHub API token (GITHUB_PAT).'
    }

    It 'Returns non-archived repositories and sets ResolvedOrg' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @(' OrgOne ')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Invoke-GitHubPagedJson {
            @(
                [pscustomobject]@{ name = 'active'; archived = $false; full_name = 'OrgOne/active' },
                [pscustomobject]@{ name = 'archived'; archived = $true; full_name = 'OrgOne/archived' }
            )
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=100' }

        $repos = Get-GitHubRepos

        $repos.Count | Should -Be 1
        $repos[0].name | Should -Be 'active'
        $repos[0].ResolvedOrg | Should -Be 'OrgOne'
        Assert-MockCalled Invoke-GitHubPagedJson -Times 1 -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=100' }
    }

    It 'Keeps archived repositories when SkipArchivedRepos is false' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
                SkipArchivedRepos = $false
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Invoke-GitHubPagedJson {
            @(
                [pscustomobject]@{ name = 'active'; archived = $false; full_name = 'OrgOne/active' },
                [pscustomobject]@{ name = 'archive-me'; archived = $true; full_name = 'OrgOne/archive-me' }
            )
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=100' }

        $repos = Get-GitHubRepos

        $repos.Count | Should -Be 2
        ($repos | Where-Object { $_.name -eq 'archive-me' }).Count | Should -Be 1
    }

    It 'Applies include and exclude patterns' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
                IncludeRepos = @('app*')
                ExcludeRepos = @('app-old')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Invoke-GitHubPagedJson {
            @(
                [pscustomobject]@{ name = 'app-main'; archived = $false; full_name = 'OrgOne/app-main' },
                [pscustomobject]@{ name = 'app-old'; archived = $false; full_name = 'OrgOne/app-old' },
                [pscustomobject]@{ name = 'toolkit'; archived = $false; full_name = 'OrgOne/toolkit' }
            )
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=100' }

        $repos = Get-GitHubRepos

        $repos.Count | Should -Be 1
        $repos[0].name | Should -Be 'app-main'
    }

    It 'Skips blank owner inputs when Owners parameter is provided' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @()
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Invoke-GitHubPagedJson {
            @([pscustomobject]@{ name = 'app'; archived = $false; full_name = 'OrgOne/app' })
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=50' }

        $repos = Get-GitHubRepos -Owners @('OrgOne','  ') -Limit 50

        $repos.Count | Should -Be 1
        Assert-MockCalled Invoke-GitHubPagedJson -Times 1 -ParameterFilter { $InitialUri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=50' }
    }
}

Describe 'GitHub-CodeQLDownload' {
    BeforeAll {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'GitHub.ps1')
    }

    BeforeEach {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'Logging.ps1')
        $env:GITHUB_PAT = 'token'
        $script:OriginalTemp = $env:TEMP
        $script:OriginalTmp = $env:TMP
        $script:OriginalTmpDir = $env:TMPDIR
        $env:TEMP = $TestDrive
        $env:TMP = $TestDrive
        $env:TMPDIR = $TestDrive
        $script:TestLogDir = Join-Path $TestDrive 'codeql'
        Initialize-Log -LogDirectory $script:TestLogDir -LogFileName 'github-tests.log' -Overwrite
        $script:TestLogFile = Join-Path $script:TestLogDir 'github-tests.log'
    }

    AfterEach {
        $env:TEMP = $script:OriginalTemp
        $env:TMP = $script:OriginalTmp
        if ($script:OriginalTmpDir) {
            $env:TMPDIR = $script:OriginalTmpDir
        } else {
            Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue
        }
    }

    It 'Downloads latest analyses per category with results' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            @(
                [pscustomobject]@{ id = 2; category = 'codeql'; created_at = [datetime]'2024-06-01'; results_count = 2; url = 'https://analysis/2'; name = 'repo' },
                [pscustomobject]@{ id = 1; category = 'codeql'; created_at = [datetime]'2024-05-01'; results_count = 1; url = 'https://analysis/1'; name = 'repo' },
                [pscustomobject]@{ id = 3; category = 'alerts'; created_at = [datetime]'2024-04-01'; results_count = 0; url = 'https://analysis/3'; name = 'repo' }
            )
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
        Mock Invoke-WebRequest {}

        GitHub-CodeQLDownload

        Assert-MockCalled Invoke-WebRequest -Times 1 -ParameterFilter {
            $Uri -eq 'https://analysis/2' -and $OutFile.EndsWith('OrgOne-repo-2.sarif')
        }
    }

    It 'Continues when listing analyses fails' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            throw (New-Object System.Exception 'REST failure')
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
        Mock Invoke-WebRequest {}
        Mock Write-Log {}

        { GitHub-CodeQLDownload } | Should -Not -Throw
        Assert-MockCalled Invoke-WebRequest -Times 0
    }

    It 'Skips downloads when no analyses are returned' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson { @() } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
        Mock Invoke-WebRequest {}

        GitHub-CodeQLDownload

        Assert-MockCalled Invoke-WebRequest -Times 0
    }
}

Describe 'GitHub-SecretScanDownload' {
    BeforeAll {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'GitHub.ps1')
    }

    BeforeEach {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'Logging.ps1')
        $env:GITHUB_PAT = 'token'
        $script:OriginalTemp = $env:TEMP
        $script:OriginalTmp = $env:TMP
        $script:OriginalTmpDir = $env:TMPDIR
        $env:TEMP = $TestDrive
        $env:TMP = $TestDrive
        $env:TMPDIR = $TestDrive
        $script:TestLogDir = Join-Path $TestDrive 'secrets'
        Initialize-Log -LogDirectory $script:TestLogDir -LogFileName 'github-tests.log' -Overwrite
        $script:TestLogFile = Join-Path $script:TestLogDir 'github-tests.log'
    }

    AfterEach {
        $env:TEMP = $script:OriginalTemp
        $env:TMP = $script:OriginalTmp
        if ($script:OriginalTmpDir) {
            $env:TMPDIR = $script:OriginalTmpDir
        } else {
            Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue
        }
    }

    It 'Saves secret scanning alerts when present' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            @([pscustomobject]@{ id = 1 })
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

        GitHub-SecretScanDownload

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'Saving 1 secret scanning alerts').Matches.Count | Should -BeGreaterThan 0
        ($logContent | Select-String -Pattern 'Saved secret scanning alerts').Matches.Count | Should -BeGreaterThan 0
    }

    It 'Skips writing files when no alerts are returned' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson { @() } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

        GitHub-SecretScanDownload

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'No open secret scanning alerts').Matches.Count | Should -BeGreaterThan 0
        ($logContent | Select-String -Pattern 'Saving').Matches.Count | Should -Be 0
    }

    It 'Logs a warning when secret scanning is disabled' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            $ex = New-Object System.Exception 'Forbidden'
            Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{ Content = 'Secret Scanning is disabled for this repository.' }) -Force
            throw $ex
        } -ParameterFilter { $InitialUri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

        GitHub-SecretScanDownload

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'WARNING').Matches.Count | Should -BeGreaterThan 0
        ($logContent | Select-String -Pattern 'Secret Scanning not enabled').Matches.Count | Should -BeGreaterThan 0
    }
}

Describe 'GitHub-DependabotDownload' {
    BeforeAll {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'GitHub.ps1')
    }

    BeforeEach {
        $moduleDir = $env:DDGitHubModulePath
        . (Join-Path $moduleDir 'Logging.ps1')
        Remove-Item Env:GITHUB_PAT -ErrorAction SilentlyContinue
        $script:OriginalTemp = $env:TEMP
        $script:OriginalTmp = $env:TMP
        $script:OriginalTmpDir = $env:TMPDIR
        $env:TEMP = $TestDrive
        $env:TMP = $TestDrive
        $env:TMPDIR = $TestDrive
        $script:TestLogDir = Join-Path $TestDrive 'dependabot'
        Initialize-Log -LogDirectory $script:TestLogDir -LogFileName 'github-tests.log' -Overwrite
        $script:TestLogFile = Join-Path $script:TestLogDir 'github-tests.log'
    }

    AfterEach {
        $env:TEMP = $script:OriginalTemp
        $env:TMP = $script:OriginalTmp
        if ($script:OriginalTmpDir) {
            $env:TMPDIR = $script:OriginalTmpDir
        } else {
            Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue
        }
        $downloadRoot = Join-Path $TestDrive 'GitHubDependabot'
        Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Throws when the GitHub token is missing' {
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }

        { GitHub-DependabotDownload } | Should -Throw 'Missing GitHub API token (GITHUB_PAT).'
    }

    It 'Exports JSON files when open Dependabot alerts exist' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            @([pscustomobject]@{
                number = 1
                state = 'open'
                fix_available = $true
                security_advisory = [pscustomobject]@{
                    ghsa_id = 'GHSA-1234'
                    summary = 'summary'
                    severity = 'medium'
                    cve_id = 'CVE-2024-1234'
                    cvss_vector_string = 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'
                }
                dependency = [pscustomobject]@{
                    manifest_path = 'package.json'
                    vulnerable_version_range = '<2.0.0'
                    package = [pscustomobject]@{
                        name = 'example'
                        ecosystem = 'npm'
                    }
                }
                created_at = '2024-01-01T00:00:00Z'
                updated_at = '2024-01-02T00:00:00Z'
                html_url = 'https://github.com/OrgOne/repo/alerts/1'
            })
        } -ParameterFilter { $InitialUri -like '*dependabot/alerts*' }

        GitHub-DependabotDownload

        $downloadRoot = Join-Path $TestDrive 'GitHubDependabot'
        $jsonFiles = @(Get-ChildItem -Path $downloadRoot -Filter '*-dependabot.json' -Recurse | Select-Object -ExpandProperty FullName)
        $jsonFiles.Count | Should -Be 1
        $jsonPath = $jsonFiles[0].Trim()
        $records = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
        $records.Count | Should -Be 1
        $records[0].number | Should -Be 1
        $records[0].state | Should -Be 'open'
    }

    It 'Logs when no open Dependabot alerts are returned' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson { @() } -ParameterFilter { $InitialUri -like '*dependabot/alerts*' }

        GitHub-DependabotDownload

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'No open Dependabot alerts').Matches.Count | Should -BeGreaterThan 0
    }

    It 'Logs an error when Dependabot alert retrieval fails' {
        $env:GITHUB_PAT = 'token'
        $config = @{
            GitHub = @{
                Orgs = @('OrgOne')
            }
            ApiBaseUrls = @{
                GitHub = 'https://api.github.test'
            }
        }
        Mock Get-Config { return $config }
        Mock Get-GitHubRepos {
            @([pscustomobject]@{ name = 'repo'; ResolvedOrg = 'OrgOne'; full_name = 'OrgOne/repo' })
        }
        Mock Invoke-GitHubPagedJson {
            throw (New-Object System.Exception 'REST failure')
        } -ParameterFilter { $InitialUri -like '*dependabot/alerts*' }
        Mock Write-Error {}  # swallow non-terminating error so Pester treats test as pass

        { GitHub-DependabotDownload } | Should -Not -Throw

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'Failed to retrieve Dependabot alerts').Matches.Count | Should -BeGreaterThan 0
    }
}
