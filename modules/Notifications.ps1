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
        [string]$WebhookType = 'PowerAutomate',

        [Parameter(Mandatory = $false)]
        [string]$Details
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
            # Power Automate format with attachments array for adaptive cards
            $bodyContent = @(
                @{
                    type = 'TextBlock'
                    text = $Title
                    weight = 'Bolder'
                    size = 'Large'
                    wrap = $true
                }
                @{
                    type = 'TextBlock'
                    text = $Message
                    wrap = $true
                    spacing = 'Medium'
                }
                @{
                    type = 'FactSet'
                    facts = @(
                        @{
                            title = 'Status'
                            value = $Status
                        }
                        @{
                            title = 'Timestamp'
                            value = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        }
                    )
                }
            )

            # Add details section if provided
            if (-not [string]::IsNullOrWhiteSpace($Details)) {
                $bodyContent += @{
                    type = 'TextBlock'
                    text = $Details
                    wrap = $true
                    spacing = 'Medium'
                    separator = $true
                }
            }

            @{
                title = $Title
                message = $Message
                status = $Status
                color = "#$color"
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                attachments = @(
                    @{
                        contentType = 'application/vnd.microsoft.card.adaptive'
                        content = @{
                            type = 'AdaptiveCard'
                            '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
                            version = '1.4'
                            body = $bodyContent
                            msteams = @{
                                width = 'Full'
                            }
                        }
                    }
                )
            }
        }
        'Teams' {
            # Microsoft Teams MessageCard format
            $sections = @(
                @{
                    activityTitle = $Title
                    activitySubtitle = "Status: $Status"
                    text = $Message
                }
            )

            # Add details section if provided
            if (-not [string]::IsNullOrWhiteSpace($Details)) {
                $sections += @{
                    title = 'Details'
                    text = $Details
                }
            }

            @{
                '@type' = 'MessageCard'
                '@context' = 'https://schema.org/extensions'
                summary = $Title
                themeColor = $color
                title = $Title
                text = $Message
                sections = $sections
            }
        }
    }

    $payload = $payloadObject | ConvertTo-Json -Depth 10

    # Redact sensitive parts of the webhook URL for logging purposes
    $redactedUrl = '<redacted>'
    try {
        $parsedUri = [Uri]$WebhookUrl
        if ($parsedUri -and $parsedUri.IsAbsoluteUri) {
            # Log only scheme, host, and path; omit query/fragment that may contain secrets
            $redactedUrl = '{0}://{1}{2}' -f $parsedUri.Scheme, $parsedUri.Host, $parsedUri.AbsolutePath
        }
    } catch {
        # If parsing fails, keep the placeholder rather than logging the raw URL
    }

    Write-Verbose "Sending $WebhookType webhook notification to $redactedUrl"
    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
        Write-Verbose "Notification sent successfully."
        return $response
    } catch {
        Write-Error "Failed to send webhook notification: $_"
        Write-Verbose "Payload sent: $payload"
    }
}

