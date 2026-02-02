<#
.SYNOPSIS
    Uploads scan reports to DefectDojo via the import-scan or reimport API endpoint.
.DESCRIPTION
    Provides functions to upload scan report files to a specified DefectDojo test record,
    and a wrapper to re-import a file to the test IDs selected in the GUI configuration.
#>
. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'DefectDojo.ps1')

function Upload-DefectDojoScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [int]$TestId,

        [Parameter(Mandatory=$false)]
        [string]$ScanType = 'Tenable WAS Scan',

        [Parameter(Mandatory=$false)]
        [bool]$CloseOldFindings = $false,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Tags = @(),
        
        [Parameter(Mandatory=$false)]
        [bool]$ApplyTagsToFindings = $false,
        
        [Parameter(Mandatory=$false)]
        [bool]$ApplyTagsToEndpoints = $false
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
        test                = $TestId
        scan_type            = $ScanType
        file                 = Get-Item -Path $FilePath
        minimum_severity     = $config.DefectDojo.MinimumSeverity
        close_old_findings   = $CloseOldFindings
    }
    
    # Add tags if provided
    if ($Tags -and $Tags.Count -gt 0) {
        # Filter out empty tags
        $validTags = @($Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($validTags.Count -gt 0) {
            $form['tags'] = $validTags
            $form['apply_tags_to_findings'] = $ApplyTagsToFindings
            $form['apply_tags_to_endpoints'] = $ApplyTagsToEndpoints
            Write-Log -Message "Uploading with tags: $($validTags -join ', ')" -Level 'INFO'
        }
    }

    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form -UseBasicParsing
    Write-Log -Message "DefectDojo import-scan response: $($response | Out-String)" -Level 'INFO'
    return $response
}
