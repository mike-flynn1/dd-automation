<#
.SYNOPSIS
    Provides logging capabilities for scripts.

.DESCRIPTION
    Contains functions to initialize a log file and write timestamped log entries with severity levels.
#>

# Private variable to store the current log file path
#$script:LogFilePath = $null

function Invoke-LogRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [int]$MaxLogFiles
    )

    if ($MaxLogFiles -lt 2) { return }

    # Delete the oldest file first, then shift down the chain
    try {
        for ($i = $MaxLogFiles - 1; $i -ge 1; $i--) {
            $target = "$BasePath.$i"
            $sourceIndex = $i - 1
            $source = if ($sourceIndex -eq 0) { $BasePath } else { "$BasePath.$sourceIndex" }

            if (Test-Path -Path $target) {
                Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
            }

            if (Test-Path -Path $source) {
                Move-Item -Path $source -Destination $target -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Host "Warning: Log rotation encountered an error (file may be locked): $_" -ForegroundColor Yellow
        # Continue with logging initialization despite rotation failure
    }
}

function Initialize-Log {
    [CmdletBinding()]
    param(
        [string]$LogDirectory = (Join-Path $PSScriptRoot '..\logs'),
        [string]$LogFileName = 'log.txt',
        [switch]$Overwrite,
        [int]$MaxLogFiles = 1
    )

    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    $script:LogFilePath = Join-Path -Path $LogDirectory -ChildPath $LogFileName
    if ($Overwrite) {
        if (Test-Path -Path $script:LogFilePath) {
            Remove-Item -Path $script:LogFilePath -Force
        }
    } elseif ($MaxLogFiles -gt 1) {
        Invoke-LogRotation -BasePath $script:LogFilePath -MaxLogFiles $MaxLogFiles
    }
    $header = "===== Log started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
    Add-Content -Path $script:LogFilePath -Value $header
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    if (-not $script:LogFilePath) {
        Write-Host "Log file not initialized. Call Initialize-Log before writing logs." 
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"
    # Append entry to log file
    Add-Content -Path $script:LogFilePath -Value $entry
    # Also output to console
    switch ($Level) {
        'INFO'    { Write-Host $entry }
        'WARNING' { Write-Warning $Message }
        'ERROR'   { Write-Error $Message }
    }
}

