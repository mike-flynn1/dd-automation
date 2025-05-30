<#
.SYNOPSIS
    Module for loading and validating the automation tool configuration.
#>

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $scriptPath -Parent

function Get-Config {
    [CmdletBinding()]
    param(
        [string]$ConfigPath   = (Join-Path (Split-Path -Path $scriptDir -Parent) 'config\config.psd1'),
        [string]$TemplatePath = (Join-Path (Split-Path -Path $scriptDir -Parent) 'config\config.psd1.example')
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -Path $ConfigPath)) {
        Write-Verbose "Loading configuration from $ConfigPath"
        try {
            $config = Import-PowerShellDataFile -Path $ConfigPath
        } catch {
            Throw "Failed to import configuration from $ConfigPath. Error: $_"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TemplatePath) -and (Test-Path -Path $TemplatePath)) {
        Write-Warning "Configuration file not found at $ConfigPath. Loading example configuration from $TemplatePath."
        try {
            $config = Import-PowerShellDataFile -Path $TemplatePath
        } catch {
            Throw "Failed to import example configuration from $TemplatePath. Error: $_"
        }
    }
    else {
        Throw "No configuration file found at $ConfigPath or $TemplatePath"
    }

    return $config
}

function Validate-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $errors = @()

    # Required top-level keys
    $requiredKeys = @('Debug', 'Tools', 'Paths', 'ApiBaseUrls')
    foreach ($key in $requiredKeys) {
        if (-not $Config.ContainsKey($key)) {
            $errors += "Missing required top-level configuration key: $key"
        }
    }

    # Validate Tools keys
    $requiredToolKeys = @('TenableWAS','SonarQube','BurpSuite','DefectDojo')
    foreach ($t in $requiredToolKeys) {
        if ($Config.Tools -isnot [hashtable] -or -not $Config.Tools.ContainsKey($t)) {
            $errors += "Configuration.Tools missing key: $t"
        }
    }

    # Validate Paths keys
    if ($Config.Paths -isnot [hashtable] -or -not $Config.Paths.ContainsKey('BurpSuiteXmlFolder')) {
        $errors += "Configuration.Paths missing key: BurpSuiteXmlFolder"
    }

    # Validate ApiBaseUrls keys
    foreach ($api in $requiredToolKeys) {
        if ($Config.ApiBaseUrls -isnot [hashtable] -or -not $Config.ApiBaseUrls.ContainsKey($api)) {
            $errors += "Configuration.ApiBaseUrls missing key: $api"
        }
    }

    if ($errors.Count -gt 0) {
        Throw ($errors -join '; ')
    }

    Write-Verbose "Configuration validation passed."
    return $true
}
