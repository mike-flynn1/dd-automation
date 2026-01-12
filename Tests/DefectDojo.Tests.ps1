# Pester tests for DefectDojo module
BeforeAll {
    $moduleDir = Join-Path $PSScriptRoot '../modules'
    . (Join-Path $moduleDir 'Config.ps1')
    . (Join-Path $moduleDir 'Logging.ps1')
    . (Join-Path $moduleDir 'DefectDojo.ps1')

    Initialize-Log -LogFileName 'unit-tests.log' -Overwrite

    # Preserve original DOJO_API_KEY value
    $script:OriginalDojoApiKey = $env:DOJO_API_KEY
}

AfterAll {
    # Restore original DOJO_API_KEY value
    if ($null -ne $script:OriginalDojoApiKey) {
        $env:DOJO_API_KEY = $script:OriginalDojoApiKey
    } else {
        Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefectDojoProducts (Unit)' {
    Context 'When DOJO_API_KEY is set and API returns results' {
        BeforeAll {
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }
            $env:DOJO_API_KEY = 'dummy-key'
            Mock Invoke-RestMethod {
                return @{ results = @( @{ id = 10; name = 'Alpha' }, @{ id = 20; name = 'Beta' } ) }
            }
        }
        It 'Returns PSCustomObjects with Id and Name properties' {
            $items = Get-DefectDojoProducts -Limit 2
            $items | Should -Not -BeNullOrEmpty
            $items[0].Id | Should -Be 10
            $items[0].Name | Should -Be 'Alpha'
            $items.Count | Should -Be 2
        }
    }

    Context 'When DOJO_API_KEY is missing' {
        BeforeAll {
            $script:SavedKey = $env:DOJO_API_KEY
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($null -ne $script:SavedKey) {
                $env:DOJO_API_KEY = $script:SavedKey
            }
        }
        It 'Throws an error about missing API key' {
            { Get-DefectDojoProducts } | Should -Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
        }
    }
}

Describe 'Get-DefectDojoEngagements (Unit)' {
    Context 'When DOJO_API_KEY is set and API returns results' {
        BeforeAll {
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }
            $env:DOJO_API_KEY = 'dummy-key'
            Mock Invoke-RestMethod {
                return @{ results = @( @{ id = 100; name = 'Eng1' }, @{ id = 200; name = 'Eng2' } ) }
            }
        }
        It 'Returns PSCustomObjects with Id and Name properties' {
            $items = Get-DefectDojoEngagements -ProductId 123 -Limit 2
            $items | Should -Not -BeNullOrEmpty
            $items[1].Id | Should -Be 200
            $items[1].Name | Should -Be 'Eng2'
            $items.Count | Should -Be 2
        }
    }

    Context 'When DOJO_API_KEY is missing' {
        BeforeAll {
            $script:SavedKey = $env:DOJO_API_KEY
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($null -ne $script:SavedKey) {
                $env:DOJO_API_KEY = $script:SavedKey
            }
        }
        It 'Throws an error about missing API key' {
            { Get-DefectDojoEngagements -ProductId 1 } | Should -Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
        }
    }
}

Describe 'Get-DefectDojoTests (Unit)' {
    Context 'When DOJO_API_KEY is set and API returns results' {
        BeforeAll {
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }
            $env:DOJO_API_KEY = 'dummy-key'
            Mock Invoke-RestMethod {
                return @{ results = @( @{ id = 1000; test_type_name = 'Test1'; title = 'Title1' }, @{ id = 2000; test_type_name = 'Test2'; title = 'Title2' } ) }
            }
        }
        It 'Returns PSCustomObjects with Id and Name properties' {
            $items = Get-DefectDojoTests -EngagementId 321 -Limit 2
            $items | Should -Not -BeNullOrEmpty
            $items[0].Id | Should -Be 1000
            $items[0].Name | Should -Be 'Test1'
            $items.Count | Should -Be 2
        }
    }

    Context 'When DOJO_API_KEY is missing' {
        BeforeAll {
            $script:SavedKey = $env:DOJO_API_KEY
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($null -ne $script:SavedKey) {
                $env:DOJO_API_KEY = $script:SavedKey
            }
        }
        It 'Throws an error about missing API key' {
            { Get-DefectDojoTests -EngagementId 1 } | Should -Throw 'Missing DefectDojo API key (DOJO_API_KEY).'
        }
    }
}

# Integration tests require a live DefectDojo instance and valid DOJO_API_KEY
Describe 'Get-DefectDojoProducts (Integration)' {
    It 'Retrieves at least one product' {
        $env:DOJO_API_KEY = 'integration-key'
        Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://dojo.integration.test/api/v2' } } }
        Mock Invoke-RestMethod {
            return @{
                results = @(
                    @{ id = 11; name = 'Integration Product A' },
                    @{ id = 22; name = 'Integration Product B' }
                )
            }
        } -ParameterFilter { $Uri -match '/products/' }

        $items = Get-DefectDojoProducts
        $items.Count | Should -BeGreaterThan 0
        $items[0].Name | Should -Be 'Integration Product A'
    }
}

Describe 'Get-DefectDojoEngagements (Integration)' {
    It 'Retrieves at least one engagement for a product' {
        $env:DOJO_API_KEY = 'integration-key'
        Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://dojo.integration.test/api/v2' } } }
        Mock Invoke-RestMethod {
            if ($Uri -match '/products/') {
                return @{ results = @( @{ id = 101; name = 'Integration Product' } ) }
            }
            elseif ($Uri -match '/engagements/') {
                return @{ results = @( @{ id = 501; name = 'Integration Engagement 1' }, @{ id = 502; name = 'Integration Engagement 2' } ) }
            }
        }

        $productId = (Get-DefectDojoProducts)[0].Id
        $items = Get-DefectDojoEngagements -ProductId $productId
        $items.Count | Should -BeGreaterThan 0
        $items[0].Name | Should -Be 'Integration Engagement 1'
    }
}

Describe 'Get-DefectDojoTests (Integration)' {
    It 'Retrieves at least one test for an engagement' {
        $env:DOJO_API_KEY = 'integration-key'
        Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://dojo.integration.test/api/v2' } } }
        Mock Invoke-RestMethod {
            if ($Uri -match '/products/') {
                return @{ results = @( @{ id = 201; name = 'Integration Product' } ) }
            }
            elseif ($Uri -match '/engagements/') {
                return @{ results = @( @{ id = 801; name = 'Integration Engagement' } ) }
            }
            elseif ($Uri -match '/tests/') {
                return @{ results = @( @{ id = 9001; test_type_name = 'Integration Test Alpha'; title = 'Integration Suite Alpha' }) }
            }
        }

        $productId = (Get-DefectDojoProducts)[0].Id
        $engagementId = (Get-DefectDojoEngagements -ProductId $productId)[0].Id
        $items = Get-DefectDojoTests -EngagementId $engagementId
        $items.Count | Should -BeGreaterThan 0
        $items[0].Title | Should -Be 'Integration Suite Alpha'
    }
}

Describe 'Get-DefectDojoTestType' {
    Context 'When test type exists' {
        BeforeAll {
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }
            $env:DOJO_API_KEY = 'dummy-key'
            Mock Invoke-RestMethod {
                return @{ 
                    results = @( 
                        @{ id = 89; name = 'Tenable Scan' },
                        @{ id = 123; name = 'SARIF' }
                    ) 
                }
            }
        }
        It 'Returns test type ID for exact name match' {
            $id = Get-DefectDojoTestType -TestTypeName 'Tenable Scan'
            $id | Should -Be 89
        }
        It 'Handles case-insensitive matching' {
            $id = Get-DefectDojoTestType -TestTypeName 'tenable scan'
            $id | Should -Be 89
        }
    }

    Context 'When test type does not exist' {
        BeforeAll {
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }
            $env:DOJO_API_KEY = 'dummy-key'
            Mock Invoke-RestMethod {
                return @{ results = @() }
            }
        }
        It 'Throws error with helpful message' {
            { Get-DefectDojoTestType -TestTypeName 'NonExistent Scan' } | 
                Should -Throw -ExpectedMessage "*not found*"
        }
    }

    Context 'When DOJO_API_KEY is missing' {
        BeforeAll {
            $script:SavedKey = $env:DOJO_API_KEY
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue
        }
        AfterAll {
            if ($null -ne $script:SavedKey) {
                $env:DOJO_API_KEY = $script:SavedKey
            }
        }
        It 'Throws error about missing API key' {
            { Get-DefectDojoTestType -TestTypeName 'Tenable Scan' } | 
                Should -Throw -ExpectedMessage "*Missing DefectDojo API key*"
        }
    }
}
