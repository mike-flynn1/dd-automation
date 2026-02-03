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
Initialize-Log -LogDirectory (Join-Path $scriptDir 'logs') -LogFileName 'DDAutomation_CLI.log' -MaxLogFiles 3
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
    
    # Set the active config path so internal module calls use the same config
    Set-ActiveConfigPath -Path $ConfigPath
    
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
    $workflowResults = @()
    
    # Process TenableWAS
    if ($config.Tools.TenableWAS) {
        Write-Log -Message "Workflow: TenableWAS started."
        $result = Invoke-Workflow-TenableWAS -Config $config
        $workflowResults += $result
    }

    # Process SonarQube
    if ($config.Tools.SonarQube) {
        Write-Log -Message "Workflow: SonarQube started."
        $result = Invoke-Workflow-SonarQube -Config $config
        $workflowResults += $result
    }

    # Process BurpSuite
    if ($config.Tools.BurpSuite) {
        Write-Log -Message "Workflow: BurpSuite started."
        $result = Invoke-Workflow-BurpSuite -Config $config
        $workflowResults += $result
    }

    # Process GitHub Features
    if ($config.Tools.GitHub) {
        # Config structure normalization handles legacy keys, so we check the new structure
        if ($config.Tools.GitHub.CodeQL) {
            Write-Log -Message "Workflow: GitHub CodeQL started."
            $result = Invoke-Workflow-GitHubCodeQL -Config $config
            $workflowResults += $result
        }
        if ($config.Tools.GitHub.SecretScanning) {
            Write-Log -Message "Workflow: GitHub Secret Scanning started."
            $result = Invoke-Workflow-GitHubSecretScanning -Config $config
            $workflowResults += $result
        }
        if ($config.Tools.GitHub.Dependabot) {
            Write-Log -Message "Workflow: GitHub Dependabot started."
            $result = Invoke-Workflow-GitHubDependabot -Config $config
            $workflowResults += $result
        }
    }

    Write-Log -Message "Automation run completed."

    # 5. Aggregate Results
    $totalSuccess = ($workflowResults | Measure-Object -Property Success -Sum).Sum
    $totalFailed = ($workflowResults | Measure-Object -Property Failed -Sum).Sum
    $totalSkipped = ($workflowResults | Measure-Object -Property Skipped -Sum).Sum
    $totalProcessed = ($workflowResults | Measure-Object -Property Total -Sum).Sum

    # 6. Notifications
    if ($config.Notifications -and $config.Notifications.WebhookUrl) {
        $webhookType = if ($config.Notifications.WebhookType) { $config.Notifications.WebhookType } else { 'PowerAutomate' }
        
        # Determine overall status
        $overallStatus = 'Success'
        $title = "DDP Automation Run Completed"
        $message = "Scheduled PSScript automation run finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
        
        if ($totalFailed -gt 0) {
            $overallStatus = 'Warning'
            $title = "DDP Automation Run Completed (Warning)"
            $message = "Some PSScript scan imports completed with errors."
        }
        
        if ($totalFailed -eq $totalProcessed -and $totalProcessed -gt 0) {
            $overallStatus = 'Error'
            $title = "DDP Automation Run Failed"
            $message = "All PSScript scan imports failed."
        }
        
        # Build detailed status
        $detailsArray = @()
        foreach ($result in $workflowResults) {
            if (-not $result -or -not $result.Tool) { continue }

            $success = if ([string]::IsNullOrEmpty([string]$result.Success)) { 0 } else { [int]$result.Success }
            $failed  = if ([string]::IsNullOrEmpty([string]$result.Failed)) { 0 } else { [int]$result.Failed }
            $skipped = if ([string]::IsNullOrEmpty([string]$result.Skipped)) { 0 } else { [int]$result.Skipped }
            $total   = if ([string]::IsNullOrEmpty([string]$result.Total)) { 0 } else { [int]$result.Total }

            if ($total -eq 0 -and $skipped -eq 0 -and $failed -eq 0) {
                $detailsArray += "○ **$($result.Tool)**: No findings (0 files processed)"
            } else {
                $status = if ($failed -gt 0) { '⚠' } elseif ($success -gt 0) { '✓' } else { '⊘' }
                $detailsArray += "${status} **$($result.Tool)**: ${success} succeeded, ${failed} failed, ${skipped} skipped (Total: ${total})"
            }
        }
        $details = $detailsArray -join "`n`n"
        
        Send-WebhookNotification -WebhookUrl $config.Notifications.WebhookUrl `
                                 -Title $title `
                                 -Message $message `
                                 -Status $overallStatus `
                                 -WebhookType $webhookType `
                                 -Details $details
    }

} catch {
    $errorMsg = $_.Exception.Message
    Write-Log -Message "Critical Error: $errorMsg" -Level 'ERROR'
    
    # Try to send failure notification
    if ($config -and $config.Notifications -and $config.Notifications.WebhookUrl) {
        $webhookType = if ($config.Notifications.WebhookType) { $config.Notifications.WebhookType } else { 'PowerAutomate' }
        Send-WebhookNotification -WebhookUrl $config.Notifications.WebhookUrl `
                                 -Title "DD Automation Failed" `
                                 -Message "Automation run failed with critical error." `
                                 -Status 'Error' `
                                 -WebhookType $webhookType `
                                 -Details "**Error Details:**`n$errorMsg"
    }
    exit 1
}

