<#
.SYNOPSIS
    Module for sending notifications via Webhooks (e.g., Slack, Teams).
#>

function Send-WebhookNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Error', 'Warning')]
        [string]$Status = 'Info'
    )

    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-Warning "Webhook URL is empty. Notification skipped."
        return
    }

    # Determine color/theme based on status (Slack/Teams friendly)
    $color = switch ($Status) {
        'Success' { '00FF00' } # Green
        'Error'   { 'FF0000' } # Red
        'Warning' { 'FFA500' } # Orange
        Default   { '0000FF' } # Blue
    }

    # Construct payload (Simple JSON card format - generic adaptation)
    $payload = @{
        title = $Title
        text = $Message
        themeColor = $color
        attachments = @(
            @{
                color = "#$color"
                title = $Title
                text = $Message
                fallback = "$Title - $Message"
                mrkdwn_in = @("text")
            }
        )
    } | ConvertTo-Json -Depth 4

    Write-Verbose "Sending webhook notification to $WebhookUrl"
    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
        Write-Verbose "Notification sent successfully."
    } catch {
        Write-Error "Failed to send webhook notification: $_"
    }
}
