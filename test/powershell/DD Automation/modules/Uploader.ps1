<#
.SYNOPSIS
    Uploads scan reports to DefectDojo via the import-scan or reimport API endpoint.
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
    $uri     = "$baseUrl/reimport-scan/"
    $headers = @{ 
        Authorization = "Token $apiKey"
        accept        = 'application/json'
        #'Content-Type' = 'multipart/form-data'
    }
    $form    = @{
        test             = $TestId
        scan_type        = $ScanType
        file             = Get-Item -Path $FilePath
        minimum_severity = $config.DefectDojo.MinimumSeverity
    }


    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Form $form -UseBasicParsing
    Write-Log -Message "DefectDojo import-scan response: $($response | Out-String)" -Level 'INFO'
    return $response
}

function ProUpload-DefectDojoScan {
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
    # Build and invoke universal-importer for reimport
    $exePath = Join-Path $moduleRoot 'universal-importer.exe'
    $args    = @(
        'reimport',
        '-u', $baseUrl,
        '-s', $ScanType,
        '-r', $FilePath,
        '--test-id', $TestId
    )
    $output = & $exePath @args 2>&1 | Out-String
    Write-Log -Message "Universal importer reimport output: $output" -Level 'INFO'
    return $output
}

function Select-DefectDojoScans {
    <#
    .SYNOPSIS
        Calls Upload-DefectDojoScan based on selections made.
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
        'TenableWASTestId'  = 'Tenable Scan'
        'SonarQubeTestId'   = 'SonarQube Scan'
        'BurpSuiteTestId'   = 'Burp Scan'
        'GitHubTestID'      = 'SARIF'
    }
    foreach ($key in $map.Keys) {
        if ($config.DefectDojo.ContainsKey($key) -and $config.DefectDojo[$key]) {
            $testId   = [int]$config.DefectDojo[$key]
            $scanType = $map[$key]
            Write-Log -Message "Re-importing '$FilePath' to DefectDojo test $testId (scan_type=$scanType)" -Level 'INFO'
            Upload-DefectDojoScan -FilePath $FilePath -TestId $testId -ScanType $scanType
            #ProUpload-DefectDojoScan -FilePath $FilePath -TestId $testId -ScanType $scanType
        }
    }
}

#DEBUG
#Select-DefectDojoScans -FilePath  "C:\Users\michael.flynn\AppData\Local\Temp\316915dd-62e4-4989-b84f-867a97132d92-report.csv"
