<#
 .SYNOPSIS
     API wrapper for DefectDojo interactions.

 .DESCRIPTION
     Provides functions to retrieve and list DefectDojo products, engagements, tests, and API scan configurations
     via the DefectDojo API v2. Functions return PSCustomObjects containing Id and Name.

     API endpoints and schemas are documented in the Examples/Defect Dojo API v2.json file.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $moduleRoot 'Logging.ps1')
. (Join-Path $moduleRoot 'Config.ps1')

function Get-DefectDojoProducts {
    <#
    .SYNOPSIS
        Retrieves a list of DefectDojo products.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/products/ endpoint and returns product Id/Name pairs.
    .PARAMETER Limit
        The maximum number of products to retrieve (API page size).
    .OUTPUTS
        PSCustomObject with properties Id and Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ Authorization = "Token $apiKey" }
    $uri = "$baseUrl/products/?limit=$Limit"

    Write-Log -Message "Retrieving DefectDojo products (limit=$Limit)" -Level 'INFO'
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing

    return $response.results | Select-Object @{Name='Id';Expression={$_.id}}, @{Name='Name';Expression={$_.name}}
}

function Get-DefectDojoEngagements {
    <#
    .SYNOPSIS
        Retrieves a list of DefectDojo engagements for a given product.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/engagements/ endpoint with a product filter
        and returns engagement Id/Name pairs.
    .PARAMETER ProductId
        The Id of the DefectDojo product to filter engagements.
    .PARAMETER Limit
        The maximum number of engagements to retrieve (API page size).
    .OUTPUTS
        PSCustomObject with properties Id and Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProductId,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ Authorization = "Token $apiKey" }
    $uri = "$baseUrl/engagements/?product=$ProductId&limit=$Limit"

    Write-Log -Message "Retrieving DefectDojo engagements for product $ProductId (limit=$Limit)" -Level 'INFO'
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing

    return $response.results | Select-Object @{Name='Id';Expression={$_.id}}, @{Name='Name';Expression={$_.name}}
}

function Get-DefectDojoTests {
    <#
    .SYNOPSIS
        Retrieves a list of DefectDojo tests for a given engagement.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/tests/ endpoint with an engagement filter
        and returns test Id/Name pairs.
    .PARAMETER EngagementId
        The Id of the DefectDojo engagement to filter tests.
    .PARAMETER Limit
        The maximum number of tests to retrieve (API page size).
    .OUTPUTS
        PSCustomObject with properties Id and Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$EngagementId,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ Authorization = "Token $apiKey" }
    $uri = "$baseUrl/tests/?engagement=$EngagementId&limit=$Limit"

    Write-Log -Message "Retrieving DefectDojo tests for engagement $EngagementId (limit=$Limit)" -Level 'INFO'
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing

    return $response.results | Select-Object @{Name='Id';Expression={$_.id}}, @{Name='Name';Expression={$_.test_type_name}}
}

function Get-DefectDojoApiScanConfigurations {
    <#
    .SYNOPSIS
        Retrieves a list of DefectDojo product API scan configurations for a given product.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/product_api_scan_configurations/ endpoint with a product filter
        and returns configuration Id and Name pairs.
    .PARAMETER ProductId
        The Id of the DefectDojo product to filter configurations.
    .PARAMETER Limit
        The maximum number of configurations to retrieve (API page size).
    .OUTPUTS
        PSCustomObject with properties Id and Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProductId,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 100
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ Authorization = "Token $apiKey" }
    $uri = "$baseUrl/product_api_scan_configurations/?product=$ProductId&limit=$Limit"

    Write-Log -Message "Retrieving DefectDojo product API scan configurations for product $ProductId (limit=$Limit)" -Level 'INFO'
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing

    return $response.results | Select-Object @{Name='Id';Expression={$_.id}}, @{Name='Name';Expression={$_.service_key_1}}
}

#DEBUG
# Get-DefectDojoProducts | ForEach-Object {
#     Write-Log -Message "Product: $($_.Name) (Id: $($_.Id))" -Level 'INFO'
# }

# Get-DefectDojoEngagements -ProductId 1 | ForEach-Object {
#     Write-Log -Message "Engagement: $($_.Name) (Id: $($_.Id))" -Level 'INFO'
# }

# Get-DefectDojoTests -EngagementId 11 | ForEach-Object {
#     Write-Log -Message "Test: $($_.Name) (Id: $($_.Id))" -Level 'INFO'
# }

# Get-DefectDojoApiScanConfigurations -ProductId 1 | ForEach-Object {
#     Write-Log -Message "API Scan Configuration: $($_.Name) (Id: $($_.Id))" -Level 'INFO'
# }
