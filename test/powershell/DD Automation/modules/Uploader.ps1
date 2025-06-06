<#
.SYNOPSIS
    Uploads scan reports to DefectDojo via the import-scan API endpoint.
.DESCRIPTION
    Provides functions to upload scan report files to a specified DefectDojo test record,
    and a wrapper to re-import a file to the test IDs selected in the GUI configuration.
#>
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')
. (Join-Path $moduleRoot 'DefectDojo.ps1')

function Upload-DefectDojoScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [int]$TestId,

        [Parameter(Mandatory=$false)]
        [string]$ScanType = 'Tenable WAS Scan'
    )

    $config  = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey  = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $uri     = "$baseUrl/import-scan/"
    $headers = @{ Authorization = "Token $apiKey" }
    $form    = @{
        test      = $TestId
        scan_type = $ScanType
        file      = Get-Item -Path $FilePath
    }

    Write-Log -Message "Uploading file '$FilePath' to DefectDojo test $TestId (scan_type=$ScanType)" -Level 'INFO'
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form -UseBasicParsing
    Write-Log -Message "DefectDojo import-scan response: $($response | Out-String)" -Level 'DEBUG'
    return $response
}

function Import-DefectDojoScans {
    <#
    .SYNOPSIS
        Re-imports a scan report file to the DefectDojo test(s) selected in the GUI.
    .DESCRIPTION
        Loads the configured test IDs from the GUI settings and calls Upload-DefectDojoScan
        once per non-empty test ID, using the appropriate scan type for each tool.
    .PARAMETER FilePath
        The local path to the scan report file to import.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $config = Get-Config
    $map = @{
        'TenableWASTestId'  = 'Tenable WAS Scan'
        'SonarQubeTestId'   = 'SonarQube Scan'
        'BurpSuiteTestId'   = 'Burp Scan'
    }
    foreach ($key in $map.Keys) {
        if ($config.DefectDojo.ContainsKey($key) -and $config.DefectDojo[$key]) {
            $testId   = [int]$config.DefectDojo[$key]
            $scanType = $map[$key]
            Write-Log -Message "Re-importing '$FilePath' to DefectDojo test $testId (scan_type=$scanType)" -Level 'INFO'
            Upload-DefectDojoScan -FilePath $FilePath -TestId $testId -ScanType $scanType
        }
    }
}