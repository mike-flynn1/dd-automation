<#
.SYNOPSIS
    Module for sending notifications via Webhooks (Power Automate, Teams).
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
        [string]$Status = 'Info',

        [ValidateSet('PowerAutomate', 'Teams')]
        [string]$WebhookType = 'PowerAutomate'
    )

    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-Warning "Webhook URL is empty. Notification skipped."
        return
    }

    # Determine color/theme based on status
    $color = switch ($Status) {
        'Success' { '00FF00' } # Green
        'Error'   { 'FF0000' } # Red
        'Warning' { 'FFA500' } # Orange
        Default   { '0000FF' } # Blue
    }

    # Construct payload based on webhook type
    $payloadObject = switch ($WebhookType) {
        'PowerAutomate' {
            # Simple flat structure for Power Automate
            @{
                title = $Title
                message = $Message
                status = $Status
                color = "#$color"
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
        'Teams' {
            # Microsoft Teams MessageCard format
            @{
                '@type' = 'MessageCard'
                '@context' = 'https://schema.org/extensions'
                summary = $Title
                themeColor = $color
                title = $Title
                text = $Message
                sections = @(
                    @{
                        activityTitle = $Title
                        activitySubtitle = "Status: $Status"
                        text = $Message
                    }
                )
            }
        }
    }

    $payload = $payloadObject | ConvertTo-Json -Depth 4

    Write-Verbose "Sending $WebhookType webhook notification to $WebhookUrl"
    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
        Write-Verbose "Notification sent successfully."
        return $response
    } catch {
        Write-Error "Failed to send webhook notification: $_"
        Write-Verbose "Payload sent: $payload"
    }
}

