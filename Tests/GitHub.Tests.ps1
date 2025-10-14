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
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ name = 'active'; archived = $false; full_name = 'OrgOne/active' },
                [pscustomobject]@{ name = 'archived'; archived = $true; full_name = 'OrgOne/archived' }
            )
        } -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=200' }

        $repos = Get-GitHubRepos

        $repos.Count | Should -Be 1
        $repos[0].name | Should -Be 'active'
        $repos[0].ResolvedOrg | Should -Be 'OrgOne'
        Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=200' }
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
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ name = 'active'; archived = $false; full_name = 'OrgOne/active' },
                [pscustomobject]@{ name = 'archive-me'; archived = $true; full_name = 'OrgOne/archive-me' }
            )
        } -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=200' }

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
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ name = 'app-main'; archived = $false; full_name = 'OrgOne/app-main' },
                [pscustomobject]@{ name = 'app-old'; archived = $false; full_name = 'OrgOne/app-old' },
                [pscustomobject]@{ name = 'toolkit'; archived = $false; full_name = 'OrgOne/toolkit' }
            )
        } -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=200' }

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
        Mock Invoke-RestMethod {
            @([pscustomobject]@{ name = 'app'; archived = $false; full_name = 'OrgOne/app' })
        } -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=50' }

        $repos = Get-GitHubRepos -Owners @('OrgOne','  ') -Limit 50

        $repos.Count | Should -Be 1
        Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq 'https://api.github.test/orgs/OrgOne/repos?per_page=50' }
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
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ id = 2; category = 'codeql'; created_at = [datetime]'2024-06-01'; results_count = 2; url = 'https://analysis/2'; name = 'repo' },
                [pscustomobject]@{ id = 1; category = 'codeql'; created_at = [datetime]'2024-05-01'; results_count = 1; url = 'https://analysis/1'; name = 'repo' },
                [pscustomobject]@{ id = 3; category = 'alerts'; created_at = [datetime]'2024-04-01'; results_count = 0; url = 'https://analysis/3'; name = 'repo' }
            )
        } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
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
        Mock Invoke-RestMethod {
            throw (New-Object System.Exception 'REST failure')
        } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
        Mock Invoke-WebRequest {}

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
        Mock Invoke-RestMethod { @() } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/code-scanning/analyses?per_page=200' }
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
        Mock Invoke-WebRequest {
            [pscustomobject]@{ Content = '[{"id":1}]' }
        } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

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
        Mock Invoke-WebRequest {
            [pscustomobject]@{ Content = '[]' }
        } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

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
        Mock Invoke-WebRequest {
            $ex = New-Object System.Exception 'Forbidden'
            Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{ Content = 'Secret Scanning is disabled for this repository.' }) -Force
            throw $ex
        } -ParameterFilter { $Uri -eq 'https://api.github.test/repos/OrgOne/repo/secret-scanning/alerts?state=open&per_page=200' }

        GitHub-SecretScanDownload

        $logContent = Get-Content $script:TestLogFile
        ($logContent | Select-String -Pattern 'WARNING').Matches.Count | Should -BeGreaterThan 0
        ($logContent | Select-String -Pattern 'Secret Scanning not enabled').Matches.Count | Should -BeGreaterThan 0
    }
}
