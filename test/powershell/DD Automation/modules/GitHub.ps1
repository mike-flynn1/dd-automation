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
        Retrieves a list of repositories from a GitHub organization.
    .PARAMETER Owner
        GitHub organization name. Uses config.GitHub.org if not provided.
    .PARAMETER Limit
        Maximum number of repositories per page.
    .OUTPUTS
        Array of repository objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Owner,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    if (-not $Owner) {
        $Owner = $config.GitHub.org
        if (-not $Owner) { Throw 'GitHub organization not specified.' }
    }

    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) { Throw 'Missing GitHub API token (GITHUB_PAT).' }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept        = 'application/vnd.github.v3+json'
        'User-Agent'  = 'DefectDojo-Automation'
    }

    $uri = "{0}/orgs/{1}/repos?per_page={2}" -f $baseUrl, $Owner, $Limit
    Write-Log -Message ("Retrieving GitHub repositories for organization {0}" -f $Owner) -Level 'INFO'
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing
        Write-Log -Message ("Retrieved {0} repositories" -f $response.Count) -Level 'INFO'
        return $response
    }
    catch {
        Write-Log -Message ("Failed to retrieve repositories: {0}" -f $_) -Level 'ERROR'
        throw
    }
}

function GitHub-CodeQLDownload {
    <#
    .SYNOPSIS
        Downloads SARIF code scanning results for all repositories.
    .PARAMETER Owner
        GitHub organization name.
    .PARAMETER Limit
        Maximum repos and analyses per page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Owner,
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    if (-not $Owner) {
        $Owner = $config.GitHub.org
        if (-not $Owner) { Throw 'GitHub organization not specified.' }
    }

    $repos   = Get-GitHubRepos -Owner $Owner -Limit $Limit
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
        $repoFullName = $repo.full_name
        Write-Log -Message ("Processing repository {0}" -f $repoFullName) -Level 'INFO'
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
            foreach ($analysis in $analyses) {
                $analysisId = $analysis.id

                # skip if no Results
                if ($analysis.results_count -lt 1) {
                    Write-Log -Message ("No Results for analysis {0}, skipping" -f $analysisId) -Level 'INFO'
                    continue
                }
                $sarifUrl   = $analysis.url
                $fileName   = "{0}-{1}.sarif" -f $repo.name, $analysisId
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

#To test:
#GitHub-CodeQLDownload {-Owner 'BAMTech-MyVector' -Limit 25

