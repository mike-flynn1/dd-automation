<#
.SYNOPSIS
    Re-imports a SonarQube scan configuration into DefectDojo via API.
.DESCRIPTION
    Uses the api_scan_configuration parameter instead of uploading a file.
    Posts to the DefectDojo reimport-scan endpoint with the given configuration.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')

function Invoke-SonarQubeProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiScanConfiguration,

        [Parameter(Mandatory = $true)]
        [int]$TestId
    )

    $config  = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }

    $uri     = "$baseUrl/reimport-scan/"
    $headers = @{
        Authorization = "Token $apiKey"
        accept        = 'application/json'
    }
    $form    = @{
        test                   = $TestId
        scan_type              = 'SonarQube API Import'
        api_scan_configuration = $ApiScanConfiguration
        minimum_severity       = $config.DefectDojo.MinimumSeverity
    }

    Write-Log -Message "Re-importing SonarQube configuration to DefectDojo test $TestId" -Level 'INFO'
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form -UseBasicParsing

    Write-Log -Message "DefectDojo reimport-scan response: $($response | Out-String)" -Level 'INFO'
    return $response
}

# DEBUG
#Invoke-SonarQubeProcessing -ApiScanConfiguration 1 -TestId 48
