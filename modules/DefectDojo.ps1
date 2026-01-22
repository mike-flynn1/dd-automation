<#
 .SYNOPSIS
     API wrapper for DefectDojo interactions.

 .DESCRIPTION
     Provides functions to retrieve and list DefectDojo products, engagements, tests, and API scan configurations
     via the DefectDojo API v2. Functions return PSCustomObjects containing Id and Name.

     API endpoints and schemas are documented in the Examples/Defect Dojo API v2.json file.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')

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

function Get-DefectDojoTestType {
    <#
    .SYNOPSIS
        Retrieves a DefectDojo test type ID by name.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/test_types/ endpoint to find a test type by name.
        Returns the test type ID if found, throws an error if not found.
    .PARAMETER TestTypeName
        The name of the test type (e.g., 'Tenable Scan', 'SARIF', 'Burp Scan').
    .OUTPUTS
        Integer test type ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestTypeName
    )

    $config = Get-Config
    $baseUrl = $config.ApiBaseUrls.DefectDojo.TrimEnd('/')
    $apiKey = [Environment]::GetEnvironmentVariable('DOJO_API_KEY')
    if (-not $apiKey) {
        Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
    }
    $headers = @{ Authorization = "Token $apiKey" }
    # Use name filter to search for exact match
    $encodedName = [System.Web.HttpUtility]::UrlEncode($TestTypeName)
    $uri = "$baseUrl/test_types/?name=$encodedName&limit=100"

    Write-Log -Message "Looking up DefectDojo test type: $TestTypeName" -Level 'INFO'
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing
        
        # Find exact match (case-insensitive)
        $testType = $response.results | Where-Object { $_.name -eq $TestTypeName } | Select-Object -First 1
        
        if (-not $testType) {
            throw "Test type '$TestTypeName' not found in DefectDojo. Available test types can be found at: $baseUrl/test_types/"
        }
        
        Write-Log -Message "Found test type '$TestTypeName' with ID: $($testType.id)" -Level 'INFO'
        return $testType.id
    } catch {
        Write-Log -Message "Failed to lookup test type '$TestTypeName': $_" -Level 'ERROR'
        throw $_
    }
}

function New-DefectDojoTest {
    <#
    .SYNOPSIS
        Creates a new DefectDojo test.
    .DESCRIPTION
        Calls the DefectDojo API /api/v2/tests/ endpoint to create a new test
        and returns the created test object. Can accept either a test type ID or name.
    .PARAMETER EngagementId
        The Id of the DefectDojo engagement to create the test under.
    .PARAMETER TestName
        The name for the new test.
    .PARAMETER TestType
        The test type ID (integer) or name (string) (e.g., 89, "SARIF", "Tenable Scan", etc.).
        If a string name is provided, it will be automatically looked up via the API.
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
        $TestType  # Can be int or string
    )

    # If TestType is a string (test type name), look up the ID
    if ($TestType -is [string]) {
        try {
            $testTypeId = Get-DefectDojoTestType -TestTypeName $TestType
        } catch {
            throw "Failed to resolve test type '$TestType': $_"
        }
    } else {
        $testTypeId = $TestType
    }

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
        test_type = $testTypeId
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

function Get-EngagementIdForTool {
    <#
    .SYNOPSIS
        Returns the appropriate EngagementId for a given tool, with fallback to default.
    .DESCRIPTION
        Checks for a tool-specific engagement ID override in the config. If not found
        or if the value is 0/empty, falls back to the default EngagementId.
        This enables CLI/config-based automation to route different tools to different
        engagements (e.g., separate SAST and DAST engagements).
    .PARAMETER Config
        Configuration hashtable containing DefectDojo settings.
    .PARAMETER Tool
        Tool name: TenableWAS, BurpSuite, CodeQL, SecretScan, Dependabot
    .OUTPUTS
        Integer engagement ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [ValidateSet('TenableWAS', 'BurpSuite', 'CodeQL', 'SecretScan', 'Dependabot')]
        [string]$Tool
    )
    
    $toolEngagementKey = "${Tool}EngagementId"
    
    # Check for tool-specific override (must exist and be non-zero)
    if ($Config.DefectDojo.ContainsKey($toolEngagementKey) -and $Config.DefectDojo[$toolEngagementKey]) {
        Write-Log -Message "Using tool-specific engagement ID for ${Tool}: $($Config.DefectDojo[$toolEngagementKey])" -Level 'INFO'
        return $Config.DefectDojo[$toolEngagementKey]
    }
    
    # Fall back to default EngagementId
    return $Config.DefectDojo.EngagementId
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
