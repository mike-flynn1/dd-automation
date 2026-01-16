<#
.SYNOPSIS
    Tests for the Notifications module.
#>

$scriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $scriptDir 'modules\Notifications.ps1')

Describe "Send-WebhookNotification" {
    
    Context "Input Validation" {
        It "Should warn and exit if WebhookUrl is empty" {
            Mock Write-Warning
            
            Send-WebhookNotification -WebhookUrl "" -Title "Test" -Message "Test"
            
            Assert-MockCalled Write-Warning -Times 1 -ParameterFilter { $Message -match "Webhook URL is empty" }
        }
    }

    Context "Payload Construction" {
        It "Should construct a valid JSON payload with 'Success' green color" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://hooks.slack.com/services/xxx" -Title "Success" -Message "Job Done" -Status 'Success'

            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"themeColor":\s*"00FF00"' -and
                $Body -match '"title":\s*"Success"'
            }
        }

        It "Should construct a valid JSON payload with 'Error' red color" {
            Mock Invoke-RestMethod
            Mock Write-Verbose

            Send-WebhookNotification -WebhookUrl "https://hooks.slack.com/services/xxx" -Title "Failed" -Message "Job Failed" -Status 'Error'

            Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter { 
                $Body -match '"themeColor":\s*"FF0000"' 
            }
        }
    }

    Context "Error Handling" {
        It "Should catch and log errors during API call" {
            Mock Invoke-RestMethod -Throw "API unreachable"
            Mock Write-Error

            Send-WebhookNotification -WebhookUrl "https://fake" -Title "T" -Message "M"

            Assert-MockCalled Write-Error -Times 1 -ParameterFilter { $_ -match "Failed to send webhook notification" }
        }
    }
}
