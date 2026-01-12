<#
.SYNOPSIS
    Generate and download a Tenable WAS scan report via API

.DESCRIPTION
    Uses the Tenable WAS v2 API to request generation of a scan report for a specified scan name,
    then downloads the resulting CSV file to a temporary location and returns its path.
    This is a two-step process: a PUT request to initiate report generation followed by
    a GET request to retrieve the report.

    The function looks up the scan ID from the latest scan configuration matching the provided
    scan name using Get-TenableWASScanConfigs.

.PARAMETER ScanName
    The display name of the scan configuration in Tenable WAS (required).
    The function will look up the corresponding scan ID from the most recent scan.

.OUTPUTS
    Returns the downloaded CSV report file in the temp directory.

.EXAMPLE
    Export-TenableWASScan -ScanName "Production Web App Scan"

    Downloads the report for the most recent scan with the name "Production Web App Scan".
    Output file: %TEMP%\Production Web App Scan.csv

.NOTES
    - Requires TENWAS_ACCESS_KEY and TENWAS_SECRET_KEY environment variables
    - Uses scan name for output filename for better readability
    - Reports are saved to system temp directory (%TEMP%)
    - Scan name lookup uses the most recent scan (last_scan.scan_id from API)
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')

function Export-TenableWASScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanName
    )

    # Load configuration
    $config = Get-Config

    # Look up scan ID by name
    Write-Log -Message "Looking up scan ID for scan name: $ScanName" -Level 'INFO'
    $scanConfigs = Get-TenableWASScanConfigs
    $matchedScan = $scanConfigs | Where-Object { $_.Name -eq $ScanName }

    if ($matchedScan) {
        $ScanId = $matchedScan.Id
        Write-Log -Message "Found scan ID $ScanId for scan name: $ScanName" -Level 'INFO'
    } else {
        Write-Log -Message "No scan found with name: $ScanName" -Level 'ERROR'
        Throw "No scan found with name: $ScanName"
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
    Start-Sleep -Seconds 2

    # Download the generated report via GET
    Write-Log -Message "Scan report URL: $reportUri" -Level 'INFO'
    Write-Log -Message "Downloading report for Tenable WAS scan ID $ScanId" -Level 'INFO'
    $tempPath = [System.IO.Path]::GetTempPath()
    
    # Use a sanitized version of the scan name for the filename to prevent path traversal
    $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeScanName = -join ($ScanName.ToCharArray() | ForEach-Object {
        if ($invalidFileNameChars -contains $_) { '_' } else { $_ }
    })
    if (-not $safeScanName) {
        $safeScanName = 'scan'
    }
    $fileName = "$safeScanName.csv"
    $outFile = Join-Path -Path $tempPath -ChildPath $fileName

    $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Accept"       = "application/json"
    }
    Invoke-RestMethod -Method GET -Uri $reportUri -Headers $headers -OutFile $outFile -ContentType 'text/csv' -UseBasicParsing

    Write-Log -Message "Tenable WAS report saved to $outFile" -Level 'INFO'
    return $outFile
}

<#
.SYNOPSIS
    Retrieves all active Tenable WAS scan configurations with their latest scan IDs

.DESCRIPTION
    Queries the Tenable WAS v2 API to retrieve all scan configurations, filtering out
    trashed scans and those without completed scans. Returns scan name and the ID
    of the most recent scan for each configuration.

    This function uses pagination to handle large result sets and implements deduplication
    to handle API pagination quirks. Results are sorted alphabetically by scan name.

    The function is used to populate the GUI scan selection list and to resolve scan
    names to scan IDs for the Export-TenableWASScan function.

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    Array of PSCustomObject with properties:
    - Name: Display name of the scan configuration
    - Id: Scan ID of the most recent completed scan (from last_scan.scan_id)

.EXAMPLE
    $scans = Get-TenableWASScanConfigs
    $scans | Format-Table Name, Id

    Retrieves all available scan configurations and displays them in a table

.EXAMPLE
    $scanId = (Get-TenableWASScanConfigs | Where-Object { $_.Name -eq "My Scan" }).Id
    Export-TenableWASScan -ScanId $scanId

    Looks up the scan ID for a specific scan configuration by name and exports it

.NOTES
    - Requires TENWAS_ACCESS_KEY and TENWAS_SECRET_KEY environment variables
    - Only returns scans that have been completed at least once (must have last_scan.scan_id)
    - Filters out scans in the trash (in_trash = true)
    - Implements pagination with duplicate detection to handle API inconsistencies
    - Page size is set to 200 items per request
    - Stops pagination after 3 consecutive pages with only duplicate items
#>
function Get-TenableWASScanConfigs {
    [CmdletBinding()]
    param()

    $config = Get-Config
    $apiUrl = $config.ApiBaseUrls.TenableWAS.TrimEnd('/')
    $accessKey = [Environment]::GetEnvironmentVariable('TENWAS_ACCESS_KEY')
    $secretKey = [Environment]::GetEnvironmentVariable('TENWAS_SECRET_KEY')

    if (-not $accessKey -or -not $secretKey) {
        Write-Log -Message "Missing Tenable WAS API credentials." -Level 'ERROR'
        return [object[]]@()
    }

    $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Content-Type" = "application/json"
        "Accept"       = "application/json"
    }

    $pageSize = 200
    $offset = 0

    try {
        Write-Log -Message "Fetching Tenable WAS scan configurations..." -Level 'INFO'

        $results = @()
        $seenIds = [System.Collections.Generic.HashSet[string]]::new()
        $consecutiveDuplicatePages = 0
        $maxConsecutiveDuplicatePages = 3
        
        do {
            $searchUri = "$apiUrl/was/v2/configs/search?limit=$pageSize&offset=$offset"
            $response = Invoke-RestMethod -Method Post -Uri $searchUri -Headers $headers -UseBasicParsing

            $items = @()
            if ($null -ne $response.items) {
                $items = $response.items
            } elseif ($null -ne $response.data) {
                $items = $response.data
            }

            $addedThisPage = 0
            foreach ($item in $items) {
                # Skip trashed scans
                if ($item.in_trash) {
                    continue
                }

                # Skip configurations that have no last_scan
                if (-not $item.last_scan -or -not $item.last_scan.scan_id) {
                    continue
                }

                $idStr = [string]$item.last_scan.scan_id
                if ($idStr -and $seenIds.Add($idStr)) {
                    $results += [PSCustomObject]@{
                        Name = $item.name
                        Id   = $item.last_scan.scan_id
                    }
                    $addedThisPage++
                }
            }

            # Track consecutive pages with no new items
            if ($addedThisPage -eq 0) {
                $consecutiveDuplicatePages++
            } else {
                $consecutiveDuplicatePages = 0
            }

            # Read pagination metadata from response
            $total = $null
            $limitFromResponse = $null
            if ($null -ne $response.pagination) {
                $total = $response.pagination.total
                $limitFromResponse = $response.pagination.limit
            }

            # If no limit returned, use actual items count or fallback
            if (-not $limitFromResponse) { $limitFromResponse = ($items.Count -gt 0 ? $items.Count : $pageSize) }
            
            # Stop conditions:
            # 1. No items returned
            # 2. Multiple consecutive pages with only duplicates (broken pagination)
            # 3. Reached the reported total
            if ($items.Count -eq 0) { break }
            if ($consecutiveDuplicatePages -ge $maxConsecutiveDuplicatePages) { 
                Write-Log -Message "Stopping pagination: API returning duplicate items (possible pagination issue)" -Level 'WARNING'
                break 
            }
            
            # Advance offset by the API's reported limit (actual page size)
            $offset += [int]$limitFromResponse
            
            # Stop if we've reached the total
            if ($null -ne $total -and $offset -ge [int]$total) { break }
        } while ($true)

        return ($results | Sort-Object -Property Name, Id)
    } catch {
        Write-Log -Message "Failed to fetch Tenable WAS configs: $_" -Level 'ERROR'
        return [object[]]@()
    }
}

#DEBUG
#Export-TenableWASScan -ScanId 06f8c725-d9ed-4473-a063-be73b5ace9ca
