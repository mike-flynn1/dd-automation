<#
.SYNOPSIS
    Module for loading and validating the automation tool configuration.
#>

# Global-scoped variable to track the active config path across all module instances
# Using global scope because Config.ps1 is dot-sourced by multiple modules,
# and script scope would be isolated per dot-source operation
if (-not $global:DDAutomation_ActiveConfigPath) {
    $global:DDAutomation_ActiveConfigPath = $null
}

function Set-ActiveConfigPath {
    <#
    .SYNOPSIS
        Sets the active configuration path for the current session.
    .DESCRIPTION
        Stores the configuration file path in a global variable so that
        internal Get-Config calls across all modules use the correct config file.
    .PARAMETER Path
        The configuration file path to use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $global:DDAutomation_ActiveConfigPath = $Path
    Write-Verbose "Active config path set to: $Path"
}

function Get-Config {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [string]$TemplatePath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1.example')
    )

    # Determine which config path to use:
    # 1. Explicit parameter (highest priority)
    # 2. Global active path (set by CLI/GUI at startup, shared across all modules)
    # 3. Default config.psd1 (fallback)
    if (-not $ConfigPath) {
        if ($global:DDAutomation_ActiveConfigPath) {
            $ConfigPath = $global:DDAutomation_ActiveConfigPath
            Write-Verbose "Using active config path: $ConfigPath"
        } else {
            $ConfigPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1')
            Write-Verbose "Using default config path: $ConfigPath"
        }
    }
    
    # Store the config path for future internal calls (if not already set)
    if (-not $global:DDAutomation_ActiveConfigPath) {
        $global:DDAutomation_ActiveConfigPath = $ConfigPath
    }

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

    Normalize-GitHubConfig -Config $config
    return $config
}

function Validate-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Normalize-GitHubConfig -Config $Config

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

    $gitHubFeatureKeys = @('CodeQL','SecretScanning','Dependabot')
    if ($Config.Tools.ContainsKey('GitHub')) {
        if ($Config.Tools.GitHub -isnot [hashtable]) {
            $errors += 'Configuration.Tools.GitHub must be a hashtable with feature toggles (CodeQL, SecretScanning, Dependabot).'
        }
        else {
            foreach ($feature in $gitHubFeatureKeys) {
                if (-not $Config.Tools.GitHub.ContainsKey($feature)) {
                    $errors += "Configuration.Tools.GitHub missing key: $feature"
                }
            }
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

    # Validate DefectDojo tags if present
    if ($Config.DefectDojo -isnot [hashtable]) {
        $errors += 'Configuration.DefectDojo must be a hashtable of DefectDojo settings'
    }
        else {
        if ($Config.DefectDojo -and $Config.DefectDojo.ContainsKey('Tags')) {
            $tags = $Config.DefectDojo.Tags
            if ($null -ne $tags) {
                # Tags must be an array (or enumerable), not a single string
                if ($tags -isnot [System.Collections.IEnumerable] -or $tags -is [string]) {
                    $errors += 'Configuration.DefectDojo.Tags must be an array of strings'
                }
                elseif ($tags -is [System.Collections.IEnumerable]) {
                    # Validate each tag is non-empty string
                    foreach ($tag in $tags) {
                        if ($tag -isnot [string] -or [string]::IsNullOrWhiteSpace($tag)) {
                            $errors += 'Configuration.DefectDojo.Tags contains empty or non-string tag values'
                            break
                        }
                    }
                }
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

        [string]$ConfigPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1')
    )

    Normalize-GitHubConfig -Config $Config

    # Build the PS data file content
    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine('@{') | Out-Null
    # Tools
    $sb.AppendLine('    Tools = @{') | Out-Null
    foreach ($tool in $Config.Tools.Keys) {
        $val = $Config.Tools[$tool]
        if ($val -is [hashtable]) {
            $sb.AppendLine("        $tool = @{") | Out-Null
            foreach ($feature in $val.Keys) {
                $featureValue = if ($val[$feature]) { '$true' } else { '$false' }
                $sb.AppendLine("            $feature = $featureValue") | Out-Null
            }
            $sb.AppendLine('        }') | Out-Null
        }
        else {
            $boolStr = if ($val) { '$true' } else { '$false' }
            $sb.AppendLine("        $tool = $boolStr") | Out-Null
        }
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
    # TenableWAS ScanNames
    if ($Config.ContainsKey('TenableWASScanNames')) {
        $sb.AppendLine('') | Out-Null
        $scanNames = $Config.TenableWASScanNames
        if ($null -ne $scanNames -and $scanNames.Count -gt 0) {
            $sb.AppendLine('    TenableWASScanNames = @(') | Out-Null
            foreach ($name in $scanNames) {
                $escapedName = $name -replace "'","''"
                $sb.AppendLine("        '$escapedName'") | Out-Null
            }
            $sb.AppendLine('    )') | Out-Null
        } else {
            $sb.AppendLine('    TenableWASScanNames = @()') | Out-Null
        }
    }
    # DefectDojo selections
    if ($Config.ContainsKey('DefectDojo')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    DefectDojo = @{') | Out-Null
        foreach ($key in $Config.DefectDojo.Keys) {
            $val = $Config.DefectDojo[$key]
            # Handle Tags array specifically
            if ($key -eq 'Tags' -and $val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($tag in $val) {
                    if (-not [string]::IsNullOrWhiteSpace($tag)) {
                        $escapedTag = $tag -replace "'","''"
                        $sb.AppendLine("            '$escapedTag'") | Out-Null
                    }
                }
                $sb.AppendLine('        )') | Out-Null
            }
            elseif ($null -eq $val -or $val -is [string]) {
                $inner = if ($null -eq $val) { '' } else { $val }
                $sb.AppendLine("        $key = '$inner'") | Out-Null
            } elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
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

    # Notifications configuration
    if ($Config.ContainsKey('Notifications')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    Notifications = @{') | Out-Null
        
        foreach ($key in $Config.Notifications.Keys | Sort-Object) {
            $val = $Config.Notifications[$key]
            
            if ($null -eq $val -or [string]::IsNullOrWhiteSpace($val)) {
                # Skip empty values but preserve the key structure
                $sb.AppendLine("        # $key = ''") | Out-Null
            }
            elseif ($val -is [string]) {
                $escapedVal = $val -replace "'","''"
                $sb.AppendLine("        $key = '$escapedVal'") | Out-Null
            }
            elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
            }
            elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($entry in $val) {
                    $escapedEntry = $entry -replace "'","''"
                    $sb.AppendLine("            '$escapedEntry'") | Out-Null
                }
                $sb.AppendLine('        )') | Out-Null
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

function Normalize-GitHubConfig {
    param([hashtable]$Config)

    if (-not $Config) { return }

    if (-not $Config.ContainsKey('Tools') -or $Config.Tools -isnot [hashtable]) {
        $Config.Tools = @{}
    }

    if (-not $Config.Tools.ContainsKey('GitHub') -or $Config.Tools.GitHub -isnot [hashtable]) {
        $Config.Tools.GitHub = @{}
    }

    $githubFeatures = @('CodeQL','SecretScanning','Dependabot')
    $legacyToolKeyMap = @{
        GitHubCodeQL         = 'CodeQL'
        GitHubSecret         = 'SecretScanning'
        GitHubSecretScanning = 'SecretScanning'
        GitHubDependabot     = 'Dependabot'
    }

    foreach ($legacyKey in $legacyToolKeyMap.Keys) {
        if ($Config.Tools.ContainsKey($legacyKey)) {
            $feature = $legacyToolKeyMap[$legacyKey]
            $Config.Tools.GitHub[$feature] = [bool]$Config.Tools[$legacyKey]
            $null = $Config.Tools.Remove($legacyKey)
        }
    }

    foreach ($feature in $githubFeatures) {
        if (-not $Config.Tools.GitHub.ContainsKey($feature)) {
            $Config.Tools.GitHub[$feature] = $false
        }
        else {
            $Config.Tools.GitHub[$feature] = [bool]$Config.Tools.GitHub[$feature]
        }
    }

    if (-not $Config.ContainsKey('ApiBaseUrls') -or $Config.ApiBaseUrls -isnot [hashtable]) {
        $Config.ApiBaseUrls = @{}
    }

    if (-not $Config.ApiBaseUrls.ContainsKey('GitHub')) {
        $Config.ApiBaseUrls.GitHub = 'https://api.github.com'
    }

    $legacyApiKeyMap = @{
        GitHubCodeQL         = 'CodeQL'
        GitHubSecret         = 'SecretScanning'
        GitHubSecretScanning = 'SecretScanning'
        GitHubDependabot     = 'Dependabot'
    }

    foreach ($legacyKey in $legacyApiKeyMap.Keys) {
        if ($Config.ApiBaseUrls.ContainsKey($legacyKey)) {
            $target = "GitHub$($legacyApiKeyMap[$legacyKey])"
            if (-not $Config.ApiBaseUrls.ContainsKey($target)) {
                $Config.ApiBaseUrls[$target] = $Config.ApiBaseUrls[$legacyKey]
            }
            $null = $Config.ApiBaseUrls.Remove($legacyKey)
        }
    }
}

function Resolve-TenableWASScans {
    <#
    .SYNOPSIS
        Resolves configured TenableWAS scan names to scan objects.
    .PARAMETER Config
        Configuration hashtable containing TenableWASScanNames.
    .OUTPUTS
        [object[]] Array of scan objects with Name/Id properties. Returns empty array on error.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if (-not $Config.ContainsKey('TenableWASScanNames') -or -not $Config.TenableWASScanNames) {
        Write-Verbose 'No TenableWAS scan names configured; skipping resolution.'
        return @()
    }

    if (-not (Get-Command Get-TenableWASScanConfigs -ErrorAction SilentlyContinue)) {
        $tenableModulePath = Join-Path $PSScriptRoot 'TenableWAS.ps1'
        if (Test-Path $tenableModulePath) {
            try {
                . $tenableModulePath
            } catch {
                Write-Verbose "Failed to load TenableWAS module from $($tenableModulePath): $($_)"
            }
        }
    }

    if (-not (Get-Command Get-TenableWASScanConfigs -ErrorAction SilentlyContinue)) {
        Write-Verbose 'Get-TenableWASScanConfigs is not available; skipping TenableWAS scan resolution.'
        return @()
    }

    try {
        $allScans = Get-TenableWASScanConfigs
    } catch {
        Write-Verbose "Failed to retrieve TenableWAS scan configurations: $($_)"
        return @()
    }

    if (-not $allScans) {
        Write-Verbose 'No TenableWAS scans were returned from the API.'
        return @()
    }

    $requestedNames = @($Config.TenableWASScanNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedNames.Count -eq 0) {
        Write-Verbose 'All configured TenableWAS scan names were empty after trimming.'
        return @()
    }

    $resolved = @($allScans | Where-Object { $_.Name -in $requestedNames })
    if ($resolved.Count -lt $requestedNames.Count) {
        $missing = $requestedNames | Where-Object { $_ -notin $resolved.Name }
        if ($missing.Count -gt 0) {
            Write-Warning ("TenableWAS scans not found: {0}" -f ($missing -join ', '))
        }
    }

    return $resolved
}

#Save-Config -Config (Get-Config) -ConfigPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1')
