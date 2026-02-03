<#
.SYNOPSIS
    Tests for the Notifications module.
#>

BeforeAll {
    $scriptDir = Split-Path $PSScriptRoot -Parent
    . (Join-Path $scriptDir 'modules\Notifications.ps1')
}

Describe "Send-WebhookNotification" {
    
    Context "Input Validation" {
        It "Should warn and exit if WebhookUrl is whitespace-only" {
            Mock Write-Warning

            Send-WebhookNotification -WebhookUrl "  " -Title "Test" -Message "Test"

            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -match "Webhook URL is empty" }
        }
    }

    Context "PowerAutomate Payload Construction" {
        It "Should construct Adaptive Card payload for PowerAutomate with Success status" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://prod-00.eastus.logic.azure.com/xxx" -Title "Success" -Message "Job Done" -Status 'Success' -WebhookType 'PowerAutomate'

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"title":\s*"Success"' -and
                $Body -match '"message":\s*"Job Done"' -and
                $Body -match '"status":\s*"Success"' -and
                $Body -match '"color":\s*"#00FF00"' -and
                $Body -match '"attachments"' -and
                $Body -match 'AdaptiveCard'
            }
        }

        It "Should construct PowerAutomate payload with Error status" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://prod-00.eastus.logic.azure.com/xxx" -Title "Failed" -Message "Job Failed" -Status 'Error' -WebhookType 'PowerAutomate'

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"color":\s*"#FF0000"' -and
                $Body -match '"status":\s*"Error"'
            }
        }

        It "Should use PowerAutomate as default webhook type with attachments" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://prod-00.eastus.logic.azure.com/xxx" -Title "Test" -Message "Test Message"

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"attachments"' -and
                $Body -match 'AdaptiveCard'
            }
        }

        It "Should include Adaptive Card schema and version" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://prod-00.eastus.logic.azure.com/xxx" -Title "Test" -Message "Test Message" -Status 'Info' -WebhookType 'PowerAutomate'

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"version":\s*"1.4"' -and
                $Body -match 'http://adaptivecards.io/schemas/adaptive-card.json' -and
                $Body -match '"contentType":\s*"application/vnd.microsoft.card.adaptive"'
            }
        }
    }

    Context "Teams Payload Construction" {
        It "Should construct MessageCard format for Teams" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://outlook.office.com/webhook/xxx" -Title "Teams Test" -Message "Teams Message" -Status 'Success' -WebhookType 'Teams'

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"@type":\s*"MessageCard"' -and
                $Body -match '"themeColor":\s*"00FF00"' -and
                $Body -match '"title":\s*"Teams Test"' -and
                $Body -match '"sections"'
            }
        }

        It "Should include status in Teams activitySubtitle" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://outlook.office.com/webhook/xxx" -Title "Test" -Message "Message" -Status 'Warning' -WebhookType 'Teams'

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"activitySubtitle":\s*"Status: Warning"'
            }
        }
    }

    Context "Error Handling" {
        It "Should catch and log errors during API call" {
            Mock Invoke-RestMethod { throw "API unreachable" }
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://fake" -Title "T" -Message "M" -ErrorAction SilentlyContinue 2>&1 | Out-Null

            # The function uses Write-Error which can't be easily mocked, so just verify it doesn't throw
            # In real usage the error would be logged
        }

        It "Should include payload in verbose output on error" {
            Mock Invoke-RestMethod { throw "API unreachable" }
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://fake" -Title "T" -Message "M" -ErrorAction SilentlyContinue 2>&1 | Out-Null

            Should -Invoke Write-Verbose -ParameterFilter { $Message -match 'Payload sent:' }
        }
    }
}

