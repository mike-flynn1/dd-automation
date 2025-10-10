
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
    #'SonarQube'  = @('SONARQUBE_API_TOKEN')
    'BurpSuite'  = @('BURP_API_KEY')
    'GitHub'     = @('GITHUB_PAT')
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
        Add-Type -AssemblyName System.Windows.Forms
        $response = [System.Windows.Forms.MessageBox]::Show(
            "Missing API keys: $($missing -join ', ')`n`nWould you like to enter them now? They will be saved to your user environment.", 
            "Missing Environment Variables", 
            [System.Windows.Forms.MessageBoxButtons]::YesNo, 
            [System.Windows.Forms.MessageBoxIcon]::Question)
        
        if ($response -eq 'Yes') {
            Request-MissingApiKeys -MissingVars $missing
        } else {
            $msg = "Required environment variables missing: $($missing -join ', ')"
            Write-Log -Message $msg -Level 'ERROR'
            Write-Host $msg -ForegroundColor Red
            Throw $msg
        }
    }
    
    Write-Log -Message 'All required environment variables are set.' -Level 'INFO'
}

function Request-MissingApiKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$MissingVars
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    
    foreach ($var in $MissingVars) {
        try {
            # Use Visual Basic InputBox for secure-looking input
            $value = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter API key for $var",
                "API Key Input",
                ""
            )
            
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Log -Message "No value provided for $var, skipping..." -Level 'WARNING'
                continue
            }
            
            # Set environment variable at User scope for persistence
            [Environment]::SetEnvironmentVariable($var, $value, [EnvironmentVariableTarget]::User)
            # Also set for current process so it's immediately available
            [Environment]::SetEnvironmentVariable($var, $value, [EnvironmentVariableTarget]::Process)
            
            Write-Log -Message "Successfully set environment variable: $var" -Level 'INFO'
            Write-Host "✓ Set $var" -ForegroundColor Green
            
        } catch {
            Write-Log -Message "Failed to set environment variable $var`: $_" -Level 'ERROR'
            Write-Host "✗ Failed to set $var" -ForegroundColor Red
        }
    }
    
    Write-Host "`nEnvironment variables have been saved to your user profile and will persist across sessions." -ForegroundColor Cyan
}
