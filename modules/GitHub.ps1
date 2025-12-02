<#
.SYNOPSIS
    GitHub API integration module for code scanning imports.
.DESCRIPTION
    Provides functions to retrieve GitHub repositories and download SARIF code scanning analyses.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'Uploader.ps1')

function Get-GitHubContext {
    <#
    .SYNOPSIS
        Retrieves shared configuration values for GitHub API calls.
    .PARAMETER Owners
        Optional override list of organization names; defaults to config.GitHub.Orgs.
    .OUTPUTS
        PSCustomObject with Config, Orgs, BaseUrl, and ApiKey properties.
    #>
    param(
        [string[]]$Owners
    )

    $config = Get-Config
    $targetOrgs = if ($Owners) { @($Owners) } else { @($config.GitHub.Orgs) }
    if (-not $targetOrgs -or $targetOrgs.Count -eq 0) {
        Throw 'GitHub organizations not specified.'
    }

    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) { Throw 'Missing GitHub API token (GITHUB_PAT).' }

    return [pscustomobject]@{
        Config = $config
        Orgs   = $targetOrgs
        BaseUrl = $baseUrl
        ApiKey = $apiKey
    }
}

function New-GitHubHeaders {
    <#
    .SYNOPSIS
        Builds standard headers for GitHub API calls.
    .PARAMETER Token
        GitHub personal access token.
    .PARAMETER Accept
        Accept header value; defaults to application/vnd.github.v3+json.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Token,
        [string]$Accept = 'application/vnd.github.v3+json'
    )

    return @{
        Authorization = "Bearer $Token"
        Accept        = $Accept
        'User-Agent'  = 'DefectDojo-Automation'
    }
}

function Ensure-DownloadRoot {
    <#
    .SYNOPSIS
        Creates and returns a temp folder for GitHub downloads.
    .PARAMETER FolderName
        Name of the subfolder to create under the OS temp directory.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderName
    )

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) $FolderName
    if (-not (Test-Path $downloadRoot)) {
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }
    return $downloadRoot
}

function Get-GitHubRepoIdentity {
    <#
    .SYNOPSIS
        Derives org, name, and full-name values for a GitHub repository object.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Repo
    )

    $orgName = if ($Repo.PSObject.Properties['ResolvedOrg']) {
        $Repo.ResolvedOrg
    } elseif ($Repo.owner -and $Repo.owner.login) {
        $Repo.owner.login
    } else {
        $null
    }

    $repoName = if ($Repo.name) { $Repo.name } else { $Repo.full_name }
    $fullName = if ($Repo.full_name) {
        $Repo.full_name
    } elseif ($orgName -and $repoName) {
        '{0}/{1}' -f $orgName, $repoName
    } else {
        $repoName
    }

    return [pscustomobject]@{
        OrgName  = $orgName
        RepoName = $repoName
        FullName = $fullName
    }
}

function Invoke-GitHubPagedJson {
    <#
    .SYNOPSIS
        Retrieves all pages for a GitHub REST endpoint that returns JSON arrays.
    .PARAMETER InitialUri
        First page URI.
    .PARAMETER Headers
        Headers to use for each request.
    .OUTPUTS
        Array of deserialized JSON objects.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InitialUri,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers
    )

    $items = @()
    $nextUri = $InitialUri
    while ($nextUri) {
        $response = Invoke-WebRequest -Method Get -Uri $nextUri -Headers $Headers -UseBasicParsing
        $pageItems = $response.Content | ConvertFrom-Json
        if ($null -ne $pageItems) {
            if ($pageItems -is [System.Collections.IEnumerable] -and -not ($pageItems -is [string])) {
                $items += @($pageItems)
            } else {
                $items += $pageItems
            }
        }
        $nextUri = Get-GitHubNextPageUri -LinkHeader $response.Headers['Link']
    }

    return $items
}


function Get-GitHubNextPageUri {
    <#
    .SYNOPSIS
        Parses a GitHub Link response header and returns the URI for the next page, if available.
    .PARAMETER LinkHeader
        Full Link header string returned by GitHub REST endpoints (may contain multiple rel entries).
    .OUTPUTS
        string with the next-page URI when present; otherwise $null.
    #>
    param(
        [string]$LinkHeader
    )

    if (-not $LinkHeader) { return $null }

    foreach ($segment in ($LinkHeader -split ',')) {
        $parts = $segment -split ';'
        if ($parts.Count -lt 2) { continue }

        $relPart = $parts[1].Trim()
        if ($relPart -match 'rel="(?<rel>[^"]+)"' -and $Matches['rel'] -eq 'next') {
            $uri = $parts[0].Trim()
            return $uri.Trim('<', '>')
        }
    }

    return $null
}

#DEBUG
#Initialize-Log -LogDirectory (Join-Path $PSScriptRoot 'logs') -LogFileName 'GitHub.log' -Overwrite

function Get-GitHubRepos {
    <#
    .SYNOPSIS
        Retrieves a list of repositories from one or more GitHub organizations.
    .PARAMETER Owners
        GitHub organization names. Uses config.GitHub.Orgs if not provided.
    .PARAMETER Limit
        Maximum number of repositories per page.
    .OUTPUTS
        Array of repository objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Owners,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 200
    )

    $context = Get-GitHubContext -Owners $Owners
    $config = $context.Config
    $targetOrgs = $context.Orgs
    $baseUrl = $context.BaseUrl
    $headers = New-GitHubHeaders -Token $context.ApiKey

    $allRepos = @()
    foreach ($org in $targetOrgs) {
        $trimmedOrg = $org.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedOrg)) { continue }

        $uri = "{0}/orgs/{1}/repos?per_page={2}" -f $baseUrl, $trimmedOrg, $Limit
        Write-Log -Message ("Retrieving GitHub repositories for organization {0}" -f $trimmedOrg) -Level 'INFO'
        try {
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing
            Write-Log -Message ("Retrieved {0} repositories for organization {1}" -f $response.Count, $trimmedOrg) -Level 'INFO'
            foreach ($repo in $response) {
                if (-not $repo.PSObject.Properties['ResolvedOrg']) {
                    $repo | Add-Member -NotePropertyName ResolvedOrg -NotePropertyValue $trimmedOrg -Force
                } else {
                    $repo.ResolvedOrg = $trimmedOrg
                }
                $allRepos += $repo
            }
        }
        catch {
            Write-Log -Message ("Failed to retrieve repositories for organization {0}: {1}" -f $trimmedOrg, $_) -Level 'ERROR'
            throw
        }
    }

    # Apply repository filtering
    $initialCount = $allRepos.Count
    Write-Log -Message ("Total repositories retrieved before filtering: {0}" -f $initialCount) -Level 'INFO'

    # Filter archived repositories (default: skip archived)
    $skipArchived = $true
    if ($config.GitHub.ContainsKey('SkipArchivedRepos') -and $null -ne $config.GitHub.SkipArchivedRepos) {
        $skipArchived = [bool]$config.GitHub.SkipArchivedRepos
    }
    if ($skipArchived) {
        $archivedRepos = @($allRepos | Where-Object { $_.archived -eq $true })
        if ($archivedRepos.Count -gt 0) {
            Write-Log -Message ("Filtering out {0} archived repositories" -f $archivedRepos.Count) -Level 'INFO'
            foreach ($archivedRepo in $archivedRepos) {
                Write-Log -Message ("  Skipped (archived): {0}" -f $archivedRepo.name) -Level 'INFO'
            }
            $allRepos = @($allRepos | Where-Object { $_.archived -ne $true })
        }
    }

    # Apply include filter (whitelist) if specified
    $includePatterns = @()
    if ($config.GitHub.ContainsKey('IncludeRepos') -and $config.GitHub.IncludeRepos) {
        $includePatterns = @($config.GitHub.IncludeRepos | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($includePatterns.Count -gt 0) {
        Write-Log -Message ("Applying include filter with {0} pattern(s): {1}" -f $includePatterns.Count, ($includePatterns -join ', ')) -Level 'INFO'
        $includedRepos = @()
        foreach ($repo in $allRepos) {
            $included = $false
            foreach ($pattern in $includePatterns) {
                if ($repo.name -like $pattern) {
                    $included = $true
                    Write-Log -Message ("  Included (matched '{0}'): {1}" -f $pattern, $repo.name) -Level 'INFO'
                    break
                }
            }
            if ($included) {
                $includedRepos += $repo
            } else {
                Write-Log -Message ("  Skipped (no include match): {0}" -f $repo.name) -Level 'INFO'
            }
        }
        $allRepos = $includedRepos
    }

    # Apply exclude filter (blacklist) if specified
    $excludePatterns = @()
    if ($config.GitHub.ContainsKey('ExcludeRepos') -and $config.GitHub.ExcludeRepos) {
        $excludePatterns = @($config.GitHub.ExcludeRepos | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($excludePatterns.Count -gt 0) {
        Write-Log -Message ("Applying exclude filter with {0} pattern(s): {1}" -f $excludePatterns.Count, ($excludePatterns -join ', ')) -Level 'INFO'
        $filteredRepos = @()
        foreach ($repo in $allRepos) {
            $excluded = $false
            foreach ($pattern in $excludePatterns) {
                if ($repo.name -like $pattern) {
                    $excluded = $true
                    Write-Log -Message ("  Skipped (matched exclude '{0}'): {1}" -f $pattern, $repo.name) -Level 'INFO'
                    break
                }
            }
            if (-not $excluded) {
                $filteredRepos += $repo
            }
        }
        $allRepos = $filteredRepos
    }

    $finalCount = $allRepos.Count
    Write-Log -Message ("Repositories after filtering: {0} (filtered out {1})" -f $finalCount, ($initialCount - $finalCount)) -Level 'INFO'

    return $allRepos
}

function GitHub-CodeQLDownload {
    <#
    .SYNOPSIS
        Downloads SARIF code scanning results for repositories across configured organizations.
    .PARAMETER Owners
        GitHub organization names. Uses config.GitHub.Orgs if not provided.
    .PARAMETER Limit
        Maximum repos and analyses per page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Owners,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 200
    )

    $context = Get-GitHubContext -Owners $Owners
    $repos = Get-GitHubRepos -Owners $context.Orgs -Limit $Limit
    $headers = New-GitHubHeaders -Token $context.ApiKey -Accept 'application/sarif+json'
    $downloadRoot = Ensure-DownloadRoot -FolderName 'GitHubCodeScanning'

    foreach ($repo in $repos) {
        $identity = Get-GitHubRepoIdentity -Repo $repo
        $repoFullName = $identity.FullName
        Write-Log -Message ("Processing repository {0} (Org: {1})" -f $repoFullName, $identity.OrgName) -Level 'INFO'
        try {
            $uriAnalyses = "{0}/repos/{1}/code-scanning/analyses?per_page={2}" -f $context.BaseUrl, $repoFullName, $Limit
            $analyses = Invoke-GitHubPagedJson -InitialUri $uriAnalyses -Headers $headers
        }
        catch {
            Write-Log -Message ("Failed to list analyses for {0}: {1}" -f $repoFullName, $_) -Level 'ERROR'
            continue
        }

        if (-not $analyses -or $analyses.Count -eq 0) {
            Write-Log -Message ("No analyses for {0}, skipping" -f $repoFullName) -Level 'INFO'
            continue
        }

        $latestAnalyses = $analyses | Group-Object -Property category | ForEach-Object {
            $_.Group | Sort-Object -Property created_at -Descending | Select-Object -First 1
        }

        foreach ($analysis in $latestAnalyses) {
            $analysisId = $analysis.id
            if ($analysis.results_count -lt 1) {
                Write-Log -Message ("No Results for analysis {0}, skipping" -f $analysisId) -Level 'INFO'
                continue
            }

            $sarifUrl = $analysis.url
            $repoName = $identity.RepoName
            $fileName = if ($identity.OrgName) { "{0}-{1}-{2}.sarif" -f $identity.OrgName, $repoName, $analysisId } else { "{0}-{1}.sarif" -f $repoName, $analysisId }
            $outFile = Join-Path $downloadRoot $fileName

            Write-Log -Message ("Downloading SARIF file {0} from {1}" -f $fileName, $sarifUrl) -Level 'INFO'
            try {
                Invoke-WebRequest -Uri $sarifUrl -Headers $headers -OutFile $outFile -UseBasicParsing
                Write-Log -Message ("Downloaded SARIF file to {0}" -f $outFile) -Level 'INFO'
            }
            catch {
                $errorContent = $_.Exception.Response.Content
                if ($errorContent -match 'Advanced Security must be enabled') {
                    Write-Log -Message ("Advanced Security not enabled for {0}/{1}, skipping download" -f $repoFullName, $analysisId) -Level 'WARNING'
                }
                else {
                    Write-Log -Message ("Failed to download SARIF for {0}/{1}: {2}" -f $repoFullName, $analysisId, $_) -Level 'ERROR'
                }
            }
        }
    }
}

function GitHub-SecretScanDownload {
    <#
    .SYNOPSIS
        Downloads JSON secret scanning results for repositories across configured organizations.
    .PARAMETER Owners
        GitHub organization names. Uses config.GitHub.Orgs if not provided.
    .PARAMETER Limit
        Maximum repos and analyses per page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Owners,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 200
    )

    $context = Get-GitHubContext -Owners $Owners
    $repos = Get-GitHubRepos -Owners $context.Orgs -Limit $Limit
    $headers = New-GitHubHeaders -Token $context.ApiKey
    $downloadRoot = Ensure-DownloadRoot -FolderName 'GitHubSecretScanning'

    foreach ($repo in $repos) {
        $identity = Get-GitHubRepoIdentity -Repo $repo
        $repoFullName = $identity.FullName
        Write-Log -Message ("Processing repository {0} for secret scanning alerts" -f $repoFullName) -Level 'INFO'

        try {
            $uriAlerts = "{0}/repos/{1}/secret-scanning/alerts?state=open&per_page={2}" -f $context.BaseUrl, $repoFullName, $Limit
            $alerts = Invoke-GitHubPagedJson -InitialUri $uriAlerts -Headers $headers

            if (-not $alerts -or $alerts.Count -eq 0) {
                Write-Log -Message ("No open secret scanning alerts for {0}" -f $repoFullName) -Level 'INFO'
                continue
            }

            $fileName = if ($identity.OrgName) { "{0}-{1}-secrets.json" -f $identity.OrgName, $identity.RepoName } else { "{0}-secrets.json" -f $identity.RepoName }
            $outFile = Join-Path $downloadRoot $fileName

            Write-Log -Message ("Saving {0} secret scanning alerts to {1}" -f $alerts.Count, $fileName) -Level 'INFO'
            $alerts | ConvertTo-Json -Depth 6 | Out-File -FilePath $outFile -Encoding UTF8
            Write-Log -Message ("Saved secret scanning alerts to {0}" -f $outFile) -Level 'INFO'
        }
        catch {
            $errorContent = $_.Exception.Response.Content
            if ($errorContent -match 'Secret Scanning is disabled') {
                Write-Log -Message ("Secret Scanning not enabled for {0}, skipping secret scanning" -f $repoFullName) -Level 'WARNING'
            }
            else {
                Write-Log -Message ("Failed to retrieve secret scanning alerts for {0}: {1}" -f $repoFullName, $_) -Level 'ERROR'
            }
        }
    }
}


function GitHub-DependabotDownload {
    <#
    .SYNOPSIS
        Retrieves open Dependabot alerts for configured GitHub repositories and writes each repo's alerts to JSON.
    .PARAMETER Owners
        Optional override list of org names; defaults to GitHub.Orgs from config when not supplied.
    .PARAMETER Limit
        Page size used for repository listing and alerts pagination; defaults to 100 per GitHub API call.
    .OUTPUTS
        string containing full paths to the JSON files saved under %TEMP%\GitHubDependabot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Owners,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )

    $context = Get-GitHubContext -Owners $Owners
    $repos = Get-GitHubRepos -Owners $context.Orgs -Limit $Limit
    $headers = New-GitHubHeaders -Token $context.ApiKey
    $downloadRoot = Ensure-DownloadRoot -FolderName 'GitHubDependabot'

    $outputFiles = @()

    foreach ($repo in $repos) {
        $identity = Get-GitHubRepoIdentity -Repo $repo
        $repoFullName = $identity.FullName
        Write-Log -Message ("Processing Dependabot alerts for {0}" -f $repoFullName) -Level 'INFO'

        $uri = "{0}/repos/{1}/dependabot/alerts?state=open&per_page={2}" -f $context.BaseUrl, $repoFullName, $Limit
        try {
            $repoAlerts = Invoke-GitHubPagedJson -InitialUri $uri -Headers $headers
        }
        catch {
            Write-Log -Message ("Failed to retrieve Dependabot alerts for {0}: {1}" -f $repoFullName, $_) -Level 'ERROR'
            continue
        }

        if ($repoAlerts.Count -eq 0) {
            Write-Log -Message ("No open Dependabot alerts for {0}" -f $repoFullName) -Level 'INFO'
            continue
        }

        $repoName = if ($identity.RepoName) { $identity.RepoName } else { $repoFullName }
        $fileName = if ($identity.OrgName) { "{0}-{1}-dependabot.json" -f $identity.OrgName, $repoName } else { "{0}-dependabot.json" -f $repoName }
        $outFile = Join-Path $downloadRoot $fileName
        $repoAlerts | ConvertTo-Json -Depth 6 | Out-File -FilePath $outFile -Encoding UTF8
        Write-Log -Message ("Saved {0} Dependabot alerts to {1}" -f $repoAlerts.Count, $outFile) -Level 'INFO'
        $outputFiles += $outFile
    }

    return $outputFiles
}

#To test:
#Get-GitHubRepos -Owners 'BAMTech-MyVector','BAMTechnologies' -Limit 10

#GitHub-CodeQLDownload -Owners 'BAMTech-MyVector' -Limit 10

#GitHub-SecretScanDownload -Owners 'BAMTech-SBIR-DTK' -Limit 50

#GitHub-DependabotDownload -Owners 'BAMTech-SBIR-DTK' -Limit 50