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
    $requiredKeys = @('Tools', 'Paths', 'ApiBaseUrls', 'DefectDojo', 'GitHub')
    foreach ($key in $requiredKeys) {
        if (-not $Config.ContainsKey($key)) {
            $errors += "Missing required top-level configuration key: $key"
        }
    }

    # Validate Tools keys
    $requiredToolKeys = @('TenableWAS','SonarQube','BurpSuite','DefectDojo','GitHub')
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

    # Validate GitHub keys
    if ($Config.GitHub -isnot [hashtable] -or -not $Config.GitHub.ContainsKey('Orgs')) {
        $errors += "Configuration.GitHub missing key: Orgs"
    }
    else {
        $orgs = $Config.GitHub.Orgs
        if ($orgs -isnot [System.Collections.IEnumerable] -or $orgs -is [string]) {
            $errors += 'Configuration.GitHub.Orgs must be an array of organization names'
        }
        else {
            $orgList = @($orgs)
            if ($orgList.Count -eq 0) {
                $errors += 'Configuration.GitHub.Orgs must contain at least one organization'
            }
            elseif ($orgList | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
                $errors += 'Configuration.GitHub.Orgs contains blank organization names'
            }
        }
    }

    if ($errors.Count -gt 0) {
        Throw ($errors -join '; ')
    }

    Write-Verbose "Configuration validation passed."
    return $true
}

function Save-Config {
    <#
    .SYNOPSIS
        Saves the configuration hashtable to a PowerShell data file (.psd1).
    .DESCRIPTION
        Writes the provided configuration hashtable back to the config.psd1 file,
        preserving the PowerShell data file format. Overwrites any existing file.
    .PARAMETER Config
        The configuration hashtable to serialize and save.
    .PARAMETER ConfigPath
        The file path to write the configuration to. Defaults to config\config.psd1 in the repo root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [string]$ConfigPath = (Join-Path (Split-Path -Path $scriptDir -Parent) 'config\config.psd1')
    )

    # Build the PS data file content
    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine('@{') | Out-Null
    # Tools
    $sb.AppendLine('    Tools = @{') | Out-Null
    foreach ($tool in $Config.Tools.Keys) {
        $val = $Config.Tools[$tool].ToString().ToLower()
        $sb.AppendLine("        $tool = `$$val") | Out-Null
    }
    $sb.AppendLine('    }') | Out-Null
    $sb.AppendLine('') | Out-Null
    # Paths
    $sb.AppendLine('    Paths = @{') | Out-Null
    foreach ($pathKey in $Config.Paths.Keys) {
        $escaped = ($Config.Paths[$pathKey] -replace '\\','\')
        $sb.AppendLine("        $pathKey = '$escaped'") | Out-Null
    }
    $sb.AppendLine('    }') | Out-Null
    $sb.AppendLine('') | Out-Null
    # ApiBaseUrls
    $sb.AppendLine('    ApiBaseUrls = @{') | Out-Null
    foreach ($api in $Config.ApiBaseUrls.Keys) {
        $url = ($Config.ApiBaseUrls[$api] -replace '\\','\\')
        $sb.AppendLine("        $api = '$url'") | Out-Null
    }
    $sb.AppendLine('    }') | Out-Null
    #TenableWAS ScanId
    if ($Config.ContainsKey('TenableWASScanId')) {
        $sb.AppendLine('') | Out-Null
        $scanId = $Config.TenableWASScanId
        if ($null -ne $scanId) {
            $sb.AppendLine("    TenableWASScanId = '$scanId'") | Out-Null
        } else {
            $sb.AppendLine('    TenableWASScanId = $null') | Out-Null
        }
    }
    # DefectDojo selections
    if ($Config.ContainsKey('DefectDojo')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    DefectDojo = @{') | Out-Null
        foreach ($key in $Config.DefectDojo.Keys) {
            $val = $Config.DefectDojo[$key]
            if ($null -eq $val -or $val -is [string]) {
                $inner = if ($null -eq $val) { '' } else { $val }
                $sb.AppendLine("        $key = '$inner'") | Out-Null
            } else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }
        $sb.AppendLine('    }') | Out-Null
    }
    
    # GitHub configuration
    if ($Config.ContainsKey('GitHub')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    GitHub = @{') | Out-Null

        # Define preferred order for GitHub keys
        $preferredOrder = @('Orgs', 'SkipArchivedRepos', 'IncludeRepos', 'ExcludeRepos')

        # Process keys in preferred order first
        foreach ($key in $preferredOrder) {
            if (-not $Config.GitHub.ContainsKey($key)) { continue }

            $val = $Config.GitHub[$key]
            if ($null -eq $val) {
                $sb.AppendLine("        $key = @()") | Out-Null
                continue
            }

            if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($entry in $val) {
                    $sb.AppendLine("            '$entry'") | Out-Null
                }
                $sb.AppendLine('        )') | Out-Null
            }
            elseif ($val -is [string]) {
                $sb.AppendLine("        $key = '$val'") | Out-Null
            }
            elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
            }
            else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }

        # Process any remaining keys not in preferred order (for future extensibility)
        foreach ($key in $Config.GitHub.Keys | Sort-Object) {
            if ($key -in $preferredOrder) { continue }

            $val = $Config.GitHub[$key]
            if ($null -eq $val) {
                $sb.AppendLine("        $key = @()") | Out-Null
                continue
            }

            if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($entry in $val) {
                    $sb.AppendLine("            '$entry'") | Out-Null
                }
                $sb.AppendLine('        )') | Out-Null
            }
            elseif ($val -is [string]) {
                $sb.AppendLine("        $key = '$val'") | Out-Null
            }
            elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
            }
            else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }

        $sb.AppendLine('    }') | Out-Null
    }

    $sb.AppendLine('}') | Out-Null

    try {
        $sb.ToString() | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
        Write-Verbose "Configuration saved to $ConfigPath"
    } catch {
        Throw "Failed to save configuration to $ConfigPath. Error: $_"
    }
}

#Save-Config -Config (Get-Config) -ConfigPath (Join-Path (Split-Path -Path $scriptDir -Parent) 'config\config.psd1')
