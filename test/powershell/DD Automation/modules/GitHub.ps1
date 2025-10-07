<#
.SYNOPSIS
    GitHub API integration module for code scanning imports.
.DESCRIPTION
    Provides functions to retrieve GitHub repositories and download SARIF code scanning analyses.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')
. (Join-Path $moduleRoot 'Uploader.ps1')

#DEBUG
#Initialize-Log -LogDirectory (Join-Path $moduleRoot 'logs') -LogFileName 'GitHub.log' -Overwrite

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

    $config = Get-Config
    $targetOrgs = if ($Owners) { @($Owners) } else { @($config.GitHub.Orgs) }
    if (-not $targetOrgs -or $targetOrgs.Count -eq 0) {
        Throw 'GitHub organizations not specified.'
    }

    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) { Throw 'Missing GitHub API token (GITHUB_PAT).' }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept        = 'application/vnd.github.v3+json'
        'User-Agent'  = 'DefectDojo-Automation'
    }

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

    $config = Get-Config
    $targetOrgs = if ($Owners) { @($Owners) } else { @($config.GitHub.Orgs) }
    if (-not $targetOrgs -or $targetOrgs.Count -eq 0) { Throw 'GitHub organizations not specified.' }

    $repos   = Get-GitHubRepos -Owners $targetOrgs -Limit $Limit
    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) { Throw 'Missing GitHub API token (GITHUB_PAT).' }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept        = 'application/sarif+json'
    }

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubCodeScanning'
    if (-not (Test-Path $downloadRoot)) {
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }

    foreach ($repo in $repos) {
        $orgName = if ($repo.PSObject.Properties['ResolvedOrg']) { $repo.ResolvedOrg } elseif ($repo.owner -and $repo.owner.login) { $repo.owner.login } else { $null }
        $repoName = if ($repo.name) { $repo.name } else { $null }
        $repoFullName = if ($repo.full_name) { $repo.full_name } elseif ($orgName -and $repoName) { "{0}/{1}" -f $orgName, $repoName } else { $repoName }
        Write-Log -Message ("Processing repository {0} (Org: {1})" -f $repoFullName, $orgName) -Level 'INFO'
        try {
            $uriAnalyses = "{0}/repos/{1}/code-scanning/analyses?per_page={2}" -f $baseUrl, $repoFullName, $Limit
            $analyses    = Invoke-RestMethod -Method Get -Uri $uriAnalyses -Headers $headers -UseBasicParsing
        }
        catch {
            Write-Log -Message ("Failed to list analyses for {0}: {1}" -f $repoFullName, $_) -Level 'ERROR'
            continue
        }
        if (-not $analyses -or $analyses.Count -eq 0) {
            Write-Log -Message ("No analyses for {0}, skipping" -f $repoFullName) -Level 'INFO'
            continue
        }

    # Group analyses by category and select the latest one based on created_at
    $latestAnalyses = $analyses | Group-Object -Property category | ForEach-Object {
        $_.Group | Sort-Object -Property created_at -Descending | Select-Object -First 1
    }

    foreach ($analysis in $latestAnalyses) {
    $analysisId = $analysis.id

    # skip if no Results
    if ($analysis.results_count -lt 1) {
        Write-Log -Message ("No Results for analysis {0}, skipping" -f $analysisId) -Level 'INFO'
        continue
    }
    $sarifUrl   = $analysis.url
    $fileName   = if ($orgName) { "{0}-{1}-{2}.sarif" -f $orgName, $repo.name, $analysisId } else { "{0}-{1}.sarif" -f $repo.name, $analysisId }
    $outFile    = Join-Path $downloadRoot $fileName

    Write-Log -Message ("Downloading SARIF file {0} from {1}" -f $fileName, $sarifUrl) -Level 'INFO'
    try {
        Invoke-WebRequest -Uri $sarifUrl -Headers $headers -OutFile $outFile -UseBasicParsing
        Write-Log -Message ("Downloaded SARIF file to {0}" -f $outFile) -Level 'INFO'
    }
    catch {
        $errorContent = $_.Exception.Response.Content
        if ($errorContent -match "Advanced Security must be enabled") {
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

    $config = Get-Config
    $targetOrgs = if ($Owners) { @($Owners) } else { @($config.GitHub.Orgs) }
    if (-not $targetOrgs -or $targetOrgs.Count -eq 0) { Throw 'GitHub organizations not specified.' }

    $repos   = Get-GitHubRepos -Owners $targetOrgs -Limit $Limit
    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) { Throw 'Missing GitHub API token (GITHUB_PAT).' }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept        = 'application/vnd.github.v3+json'
        'User-Agent'  = 'DefectDojo-Automation'
    }

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubSecretScanning'
    if (-not (Test-Path $downloadRoot)) {
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }

    foreach ($repo in $repos) {
        $orgName = if ($repo.PSObject.Properties['ResolvedOrg']) { $repo.ResolvedOrg } elseif ($repo.owner -and $repo.owner.login) { $repo.owner.login } else { $null }
        $repoFullName = if ($repo.full_name) { $repo.full_name } elseif ($orgName -and $repo.name) { "{0}/{1}" -f $orgName, $repo.name } else { $repo.name }
        Write-Log -Message ("Processing repository {0} for secret scanning alerts" -f $repoFullName) -Level 'INFO'

        try {
            $uriAlerts = "{0}/repos/{1}/secret-scanning/alerts?state=open&per_page={2}" -f $baseUrl, $repoFullName, $Limit
            $response = Invoke-WebRequest -Method Get -Uri $uriAlerts -Headers $headers -UseBasicParsing

            $alerts = $response.Content | ConvertFrom-Json
            if (-not $alerts -or $alerts.Count -eq 0) {
                Write-Log -Message ("No open secret scanning alerts for {0}" -f $repoFullName) -Level 'INFO'
                continue
            }

            $fileName = if ($orgName) { "{0}-{1}-secrets.json" -f $orgName, $repo.name } else { "{0}-secrets.json" -f $repo.name }
            $outFile = Join-Path $downloadRoot $fileName

            Write-Log -Message ("Saving {0} secret scanning alerts to {1}" -f $alerts.Count, $fileName) -Level 'INFO'
            $response.Content | Out-File -FilePath $outFile -Encoding UTF8
            Write-Log -Message ("Saved secret scanning alerts to {0}" -f $outFile) -Level 'INFO'
        }
        catch {
            $errorContent = $_.Exception.Response.Content
            if ($errorContent -match "Secret Scanning is disabled") {
                Write-Log -Message ("Secret Scanning not enabled for {0}, skipping secret scanning" -f $repoFullName) -Level 'WARNING'
            }
            else {
                Write-Log -Message ("Failed to retrieve secret scanning alerts for {0}: {1}" -f $repoFullName, $_) -Level 'ERROR'
            }
        }
    }
}

#To test:
#Get-GitHubRepos -Owners 'BAMTech-MyVector','BAMTechnologies' -Limit 10

#GitHub-CodeQLDownload -Owners 'BAMTech-MyVector' -Limit 10

#GitHub-SecretScanDownload -Owners 'BAMTech-MyVector' -Limit 50
