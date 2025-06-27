<#
.SYNOPSIS
    GitHub API integration module for code scanning and secret scanning imports.
.DESCRIPTION
    Provides functions to retrieve GitHub repositories and import code scanning/secret scanning
    results into DefectDojo via the uploader module.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')
. (Join-Path $moduleRoot 'Uploader.ps1')

#DEBUG
Initialize-Log -LogFilePath (Join-Path $moduleRoot 'logs/GitHub.log') -LogLevel 'DEBUG'

function Get-GitHubRepos {
    <#
    .SYNOPSIS
        Retrieves a list of repositories from a GitHub organization.
    .DESCRIPTION
        Calls the GitHub API to get all repositories for the specified organization.
    .PARAMETER Owner
        The GitHub organization name. If not provided, uses the value from config.
    .PARAMETER Limit
        The maximum number of repositories to retrieve per page (default: 100).
    .OUTPUTS
        Array of repository objects with name, full_name, and other properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Owner,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    
    if (-not $Owner) {
        $Owner = $config.GitHub.org
        if (-not $Owner) {
            Throw 'GitHub organization not specified in parameters or config file.'
        }
    }

    $baseUrl = $config.ApiBaseUrls.GitHub.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('GITHUB_PAT')
    if (-not $apiKey) {
        Throw 'Missing GitHub API token (GITHUB_PAT).'
    }

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept = 'application/vnd.github.v3+json'
        'User-Agent' = 'DefectDojo-Automation'
    }

    $uri = "$baseUrl/orgs/$Owner/repos?per_page=$Limit"
    
    Write-Log -Message "Retrieving GitHub repositories for organization: $Owner" -Level 'INFO'
    
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing
        Write-Log -Message "Retrieved $($response.Count) repositories from GitHub" -Level 'INFO'
        return $response
    }
    catch {
        #Write-Host -ForegroundColor Red "Failed to retrieve GitHub repositories: $_"
        Write-Log -Message "Failed to retrieve GitHub repositories: $_" -Level 'ERROR'
        throw
    }
}


#DEBUG / Examples - Uncomment to test individual functions

# Example 1: List all repositories for the configured organization
$repos = Get-GitHubRepos
$repos | ForEach-Object {
    Write-Host "Repository: $($_.name) - $($_.full_name)" 
}
