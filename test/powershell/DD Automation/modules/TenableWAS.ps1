<#
.SYNOPSIS
    Generate and download a Tenable WAS scan report via API
.DESCRIPTION
    Uses the Tenable WAS v2 API to request generation of a scan report for a specified scan ID,
    then downloads the resulting CSV file to a temporary location and returns its path.
    This is a two-step process: a PUT request to initiate report generation followed by
    a GET request to retrieve the report.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')

function Export-TenableWASScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScanId
    )

    # Load configuration
    $config = Get-Config


    # Determine Scan ID from parameter or config
    if (-not $ScanId) {
        if ($config.TenableWAS -and $config.TenableWAS.ScanId) {
            $ScanId = $config.TenableWAS.ScanId
        } elseif ($config.TenableWASScanId) {
            $ScanId = $config.TenableWASScanId
        } else {
            Throw "No TenableWAS ScanId specified."
        }
    }

    # Prepare API connection
    $apiUrl = $config.ApiBaseUrls.TenableWAS.TrimEnd('/')
    $accessKey = [Environment]::GetEnvironmentVariable('TENWAS_ACCESS_KEY')
    $secretKey = [Environment]::GetEnvironmentVariable('TENWAS_SECRET_KEY')
    if (-not $accessKey -or -not $secretKey) {
        Write-Log -Message "Missing Tenable WAS API credentials (TENWAS_ACCESS_KEY or TENWAS_SECRET_KEY)." -Level 'ERROR'
        Throw "Missing Tenable WAS API credentials (TENWAS_ACCESS_KEY or TENWAS_SECRET_KEY)."
    }

    # Build report endpoint URI
    $reportUri = "$apiUrl/was/v2/scans/$ScanId/report"

    # Common request headers
    $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Content-Type" = "text/csv"
        "Accept"       = "application/json"
    }

    # Initiate report generation via PUT
    Write-Log -Message "Initiating report generation for Tenable WAS scan ID $ScanId" -Level 'INFO'
    Invoke-RestMethod -Method Put -Uri $reportUri -Headers $headers -UseBasicParsing

    # Allow time for report generation
    Start-Sleep -Seconds 5

    # Download the generated report via GET
    Write-Log -Message "Scan report URL: $reportUri" -Level 'INFO'
    Write-Log -Message "Downloading report for Tenable WAS scan ID $ScanId" -Level 'INFO'
    $tempPath = [System.IO.Path]::GetTempPath()
    $fileName = "$ScanId-report.csv"
    $outFile = Join-Path -Path $tempPath -ChildPath $fileName

    Invoke-RestMethod -Method GET -Uri $reportUri -Headers $headers -OutFile $outFile

    Write-Log -Message "Tenable WAS report saved to $outFile" -Level 'INFO'
    return $outFile
}

#DEBUG
#Export-TenableWASScan -ScanId $ScanId
