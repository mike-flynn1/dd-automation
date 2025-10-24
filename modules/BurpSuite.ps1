<#
.SYNOPSIS
    Process BurpSuite XML reports for DefectDojo upload
.DESCRIPTION
    Scans a specified directory for BurpSuite XML report files and returns their paths
    for upload to DefectDojo. This module handles local file discovery rather than
    API-based export, as BurpSuite reports are typically generated manually or via
    BurpSuite Enterprise API.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')

function Get-BurpSuiteReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FolderPath
    )

    # Load configuration
    $config = Get-Config

    # Determine folder path from parameter or config
    if (-not $FolderPath) {
        if ($config.Paths -and $config.Paths.BurpSuiteXmlFolder) {
            $FolderPath = $config.Paths.BurpSuiteXmlFolder
        } else {
            Write-Log -Message "No BurpSuite XML folder path specified." -Level 'ERROR'
            Throw "No BurpSuite XML folder path specified."
        }
    }

    # Validate folder exists
    if (-not (Test-Path -Path $FolderPath -PathType Container)) {
        Write-Log -Message "BurpSuite XML folder does not exist: $FolderPath" -Level 'ERROR'
        Throw "BurpSuite XML folder does not exist: $FolderPath"
    }

    # Search for XML files
    Write-Log -Message "Scanning for BurpSuite XML reports in: $FolderPath" -Level 'INFO'
    $xmlFiles = Get-ChildItem -Path $FolderPath -Filter '*.xml' -File -ErrorAction SilentlyContinue

    if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
        Write-Log -Message "No XML files found in folder: $FolderPath" -Level 'WARNING'
        return @()
    }

    Write-Log -Message "Found $($xmlFiles.Count) XML file(s) in BurpSuite folder" -Level 'INFO'

    # Return array of file paths
    $filePaths = @($xmlFiles | ForEach-Object { $_.FullName })

    foreach ($file in $filePaths) {
        Write-Log -Message "BurpSuite XML report: $file" -Level 'INFO'
    }

    return $filePaths
}

#DEBUG
#Get-BurpSuiteReports -FolderPath "C:\path\to\burp\reports"
