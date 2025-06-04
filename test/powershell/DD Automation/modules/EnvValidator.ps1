
<#
.SYNOPSIS
    Validates that required environment variables are set for enabled tools.

.DESCRIPTION
    Checks for presence of required environment variables based on which tools are enabled in the configuration.
    Only validates environment variables for tools that are enabled.
    The `$Test` switch can be used to enable debug logging, providing additional details about the validation process.
#>

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'Logging.ps1')
. (Join-Path $scriptDir 'Config.ps1')

# Define tool-specific environment variable requirements
$TOOL_ENV_VARS = @{
    'DefectDojo' = @('DOJO_API_KEY')
    'TenableWAS' = @('TENWAS_ACCESS_KEY', 'TENWAS_SECRET_KEY')
    'SonarQube'  = @('SONARQUBE_API_TOKEN')
    'BurpSuite'  = @('BURP_API_KEY')
}

#TODO: Possibly needed for pester tests. Validate when Pester working
#Initialize-Log -LogDirectory (Join-Path $scriptDir '..\logs') -LogFileName 'EnvValidator.log' -Overwrite

function Get-EnvVariables {
    [CmdletBinding()]
    param()

    $config = Get-Config
    $requiredVars = @()

    foreach ($tool in $TOOL_ENV_VARS.Keys) {
        if ($config.Tools[$tool] -eq $true) {
            $requiredVars += $TOOL_ENV_VARS[$tool]
        }
    }

    return $requiredVars
}

function Validate-Environment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredVariables = (Get-EnvVariables),
        [switch]$Test
    )

    if ($Test) {
        Write-Log -Message "Checking environment variables for enabled tools..." -Level 'INFO'
    }

    $missing = @()
    foreach ($var in $RequiredVariables) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if (-not $value) {
            $missing += $var
        }
        elseif ($Test) {
            Write-Log -Message "Environment variable '$var' is set." -Level 'INFO'
        }
    }

    if ($missing.Count -gt 0) {
        $msg = "Required environment variables missing: $($missing -join ', ')"
        Write-Log -Message $msg -Level 'ERROR'
        Write-Host $msg -ForegroundColor Red
        Throw $msg
    }
    
    Write-Log -Message 'All required environment variables are set.' -Level 'INFO'
}
