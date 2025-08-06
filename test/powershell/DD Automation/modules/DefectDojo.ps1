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
        PSCustomObject with properties ID, Name and Title.
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

    return $response.results | Select-Object @{Name='Id';Expression={$_.id}}, @{Name='Name';Expression={$_.test_type_name}}, @{Name='Title';Expression={$_.title}}
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

function New-DefectDojoTest {
    <#
    .SYNOPSIS
        Creates a new DefectDojo test.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/tests/ endpoint to create a new test
        and returns the created test object.
    .PARAMETER EngagementId
        The Id of the DefectDojo engagement to create the test under.
    .PARAMETER TestName
        The name for the new test.
    .PARAMETER TestType
        The test type (e.g., "SARIF", "SonarQube Scan", etc.).
    .OUTPUTS
        PSCustomObject with properties Id and Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$EngagementId,

        [Parameter(Mandatory = $true)]
        [string]$TestName,

        [Parameter(Mandatory = $true)]
        [string]$TestType
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ 
        Authorization = "Token $apiKey"
        'Content-Type' = 'application/json'
    }
    $uri = "$baseUrl/tests/"

    $body = @{
        engagement = $EngagementId
        title = $TestName
        #environment = 1
        test_type = $TestType
        target_start = (Get-Date).ToString("yyyy-MM-dd")
        target_end = (Get-Date).ToString("yyyy-MM-dd")
    } | ConvertTo-Json

    Write-Log -Message "Creating DefectDojo test '$TestName' for engagement $EngagementId with name '$TestName'" -Level 'INFO'
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -UseBasicParsing
        Write-Log -Message "Test created successfully: ID $($response.id)" -Level 'INFO'
        return [PSCustomObject]@{
            Id = $response.id
            Name = $TestName
        }
    } catch {
        Write-Log -Message "Failed to create test '$TestName': $_" -Level 'ERROR'
        throw $_
    }
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
