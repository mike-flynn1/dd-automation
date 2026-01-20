<#
.SYNOPSIS
    Headless CLI entry point for DD Automation.
    Designed for Task Scheduler, Cron, or CI/CD usage.

.DESCRIPTION
    Loads configuration, executes enabled automation workflows, and supports webhook notifications.

.PARAMETER ConfigPath
    Path to the configuration file (default: config/config.psd1).
.PARAMETER WebhookUrl
    Optional URL for webhook notifications (overrides config).
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$WebhookUrl
)

# Enforce PowerShell 7.2+
$minVersion = [version]"7.2"
if ($PSVersionTable.PSVersion -lt $minVersion) {
    Write-Error "PowerShell 7.2+ is required."
    exit 1
}

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'modules\Logging.ps1')
. (Join-Path $scriptDir 'modules\Config.ps1')
. (Join-Path $scriptDir 'modules\AutomationWorkflows.ps1')
. (Join-Path $scriptDir 'modules\Notifications.ps1')

# Initialize Logging
Initialize-Log -LogDirectory (Join-Path $scriptDir 'logs') -LogFileName 'DDAutomation_CLI.log'
Write-Log -Message "DD Automation CLI started." -Level 'INFO'

try {
    # 1. Load Configuration
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $scriptDir 'config\config.psd1'
    }
    
    Write-Log -Message "Loading configuration from: $ConfigPath"
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at $ConfigPath"
    }
    
    $config = Get-Config -ConfigPath $ConfigPath
    
    # Validate Configuration
    Write-Log -Message "Validating configuration..."
    try {
        Validate-Config -Config $config
    } catch {
        throw "Configuration validation failed: $_"
    }
    
    # Merge CLI parameters (e.g. WebhookUrl)
    if ($WebhookUrl) {
        if (-not $config.ContainsKey('Notifications')) { $config.Notifications = @{} }
        $config.Notifications.WebhookUrl = $WebhookUrl
    }

    # 2. Validate Environment
    . (Join-Path $scriptDir 'modules\EnvValidator.ps1')
    Write-Log -Message "Validating environment variables..." -Level 'INFO'
    try {
        Validate-Environment -NonInteractive
    } catch {
        Write-Log -Message "Environment validation failed: $_" -Level 'ERROR'
        exit 1
    }

    # 3. Prepare configuration for workflows (resolve scan selections)
    if ($config.Tools.TenableWAS -and $config.TenableWASScanNames) {
        Write-Log -Message "Resolving TenableWAS scan configurations..." -Level 'INFO'
        $config.TenableWASSelectedScans = Resolve-TenableWASScans -Config $config
        Write-Log -Message "Resolved $(@($config.TenableWASSelectedScans).Count) TenableWAS scan(s) for processing" -Level 'INFO'
    }

    # 4. Execute Workflows
    $errorsOccurred = $false
    
    # Process TenableWAS
    if ($config.Tools.TenableWAS) {
        Write-Log -Message "Workflow: TenableWAS started."
        Invoke-Workflow-TenableWAS -Config $config
    }

    # Process SonarQube
    if ($config.Tools.SonarQube) {
        Write-Log -Message "Workflow: SonarQube started."
        Invoke-Workflow-SonarQube -Config $config
    }

    # Process BurpSuite
    if ($config.Tools.BurpSuite) {
        Write-Log -Message "Workflow: BurpSuite started."
        Invoke-Workflow-BurpSuite -Config $config
    }

    # Process GitHub Features
    if ($config.Tools.GitHub) {
        # Config structure normalization handles legacy keys, so we check the new structure
        if ($config.Tools.GitHub.CodeQL) {
            Write-Log -Message "Workflow: GitHub CodeQL started."
            Invoke-Workflow-GitHubCodeQL -Config $config
        }
        if ($config.Tools.GitHub.SecretScanning) {
            Write-Log -Message "Workflow: GitHub Secret Scanning started."
            Invoke-Workflow-GitHubSecretScanning -Config $config
        }
        if ($config.Tools.GitHub.Dependabot) {
            Write-Log -Message "Workflow: GitHub Dependabot started."
            Invoke-Workflow-GitHubDependabot -Config $config
        }
    }

    Write-Log -Message "Automation run completed."

    # 4. Notifications
    if ($config.Notifications -and $config.Notifications.WebhookUrl) {
        # Simple success notification - could be enhanced to report specific failures
        # For now, we just report completion.
        Send-WebhookNotification -WebhookUrl $config.Notifications.WebhookUrl `
                                 -Title "DD Automation Completed" `
                                 -Message "Scheduled automation run finished successfully at $(Get-Date)." `
                                 -Status 'Success'
    }

} catch {
    $errorMsg = $_.Exception.Message
    Write-Log -Message "Critical Error: $errorMsg" -Level 'ERROR'
    
    # Try to send failure notification
    if ($config -and $config.Notifications -and $config.Notifications.WebhookUrl) {
        Send-WebhookNotification -WebhookUrl $config.Notifications.WebhookUrl `
                                 -Title "DD Automation Failed" `
                                 -Message "Run failed with error: $errorMsg" `
                                 -Status 'Error'
    }
    exit 1
}
