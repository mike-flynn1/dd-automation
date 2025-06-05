# Pester tests for DefectDojo module                                                                        
$moduleDir = Join-Path $PSScriptRoot '../modules'                                                           
. (Join-Path $moduleDir 'Config.ps1')                                                                       
. (Join-Path $moduleDir 'Logging.ps1')                                                                      
. (Join-Path $moduleDir 'DefectDojo.ps1')                                                                   
                                                                                                            
Describe 'Get-DefectDojoProducts (Unit)' {                                                                  
    Context 'When DOJO_API_KEY is missing' {                                                                
        BeforeAll {                                                                                         
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue                                      
        }                                                                                                   
        It 'Throws an error about missing API key' {                                                        
            { Get-DefectDojoProducts } | Should -Throw 'Missing DefectDojo API key (DOJO_API_KEY).'         
        }                                                                                                   
    }                                                                                                       
                                                                                                            
    Context 'When DOJO_API_KEY is set and API returns results' {                                            
        BeforeAll {                                                                                         
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }       
            $env:DOJO_API_KEY = 'dummy-key'                                                                 
            Mock Invoke-RestMethod {                                                                        
                return @{ results = @( @{ id = 10; name = 'Alpha' }, @{ id = 20; name = 'Beta' } ) }        
            }                                                                                               
        }                                                                                                   
        AfterAll {                                                                                          
            Remove-Item Env:DOJO_API_KEY                                                                    
        }                                                                                                   
        It 'Returns PSCustomObjects with Id and Name properties' {                                          
            $items = Get-DefectDojoProducts -Limit 2                                                        
            $items | Should -Not -BeNullOrEmpty                                                             
            $items[0].Id | Should -Be 10                                                                    
            $items[0].Name | Should -Be 'Alpha'                                                             
            $items.Count | Should -Be 2                                                                     
        }                                                                                                   
    }                                                                                                       
}                                                                                                           
                                                                                                            
Describe 'Get-DefectDojoEngagements (Unit)' {                                                               
    Context 'When DOJO_API_KEY is missing' {                                                                
        BeforeAll {                                                                                         
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue                                      
        }                                                                                                   
        It 'Throws an error about missing API key' {                                                        
            { Get-DefectDojoEngagements -ProductId 1 } | Should -Throw 'Missing DefectDojo API key          
(DOJO_API_KEY).'                                                                                            
        }                                                                                                   
    }                                                                                                       
                                                                                                            
    Context 'When DOJO_API_KEY is set and API returns results' {                                            
        BeforeAll {                                                                                         
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }       
            $env:DOJO_API_KEY = 'dummy-key'                                                                 
            Mock Invoke-RestMethod {                                                                        
                return @{ results = @( @{ id = 100; name = 'Eng1' }, @{ id = 200; name = 'Eng2' } ) }       
            }                                                                                               
        }                                                                                                   
        AfterAll {                                                                                          
            Remove-Item Env:DOJO_API_KEY                                                                    
        }                                                                                                   
        It 'Returns PSCustomObjects with Id and Name properties' {                                          
            $items = Get-DefectDojoEngagements -ProductId 123 -Limit 2                                      
            $items | Should -Not -BeNullOrEmpty                                                             
            $items[1].Id | Should -Be 200                                                                   
            $items[1].Name | Should -Be 'Eng2'                                                              
            $items.Count | Should -Be 2                                                                     
        }                                                                                                   
    }                                                                                                       
}                                                                                                           
                                                                                                            
Describe 'Get-DefectDojoTests (Unit)' {                                                                     
    Context 'When DOJO_API_KEY is missing' {                                                                
        BeforeAll {                                                                                         
            Remove-Item Env:DOJO_API_KEY -ErrorAction SilentlyContinue                                      
        }                                                                                                   
        It 'Throws an error about missing API key' {                                                        
            { Get-DefectDojoTests -EngagementId 1 } | Should -Throw 'Missing DefectDojo API key             
(DOJO_API_KEY).'                                                                                            
        }                                                                                                   
    }                                                                                                       
                                                                                                            
    Context 'When DOJO_API_KEY is set and API returns results' {                                            
        BeforeAll {                                                                                         
            Mock Get-Config { return @{ ApiBaseUrls = @{ DefectDojo = 'https://example.com/api' } } }       
            $env:DOJO_API_KEY = 'dummy-key'                                                                 
            Mock Invoke-RestMethod {                                                                        
                return @{ results = @( @{ id = 1000; name = 'Test1' }, @{ id = 2000; name = 'Test2' } ) }   
            }                                                                                               
        }                                                                                                   
        AfterAll {                                                                                          
            Remove-Item Env:DOJO_API_KEY                                                                    
        }                                                                                                   
        It 'Returns PSCustomObjects with Id and Name properties' {                                          
            $items = Get-DefectDojoTests -EngagementId 321 -Limit 2                                         
            $items | Should -Not -BeNullOrEmpty                                                             
            $items[0].Id | Should -Be 1000                                                                  
            $items[0].Name | Should -Be 'Test1'                                                             
            $items.Count | Should -Be 2                                                                     
        }                                                                                                   
    }                                                                                                       
}                                                                                                           
                                                                                                            
if (-not $env:DOJO_API_KEY) {                                                                               
    Write-Warning 'Skipping DefectDojo integration tests: DOJO_API_KEY environment variable must be set.'   
    return                                                                                                  
}                                                                                                           
                                                                                                            
# Integration tests require a live DefectDojo instance and valid DOJO_API_KEY                               
$config = Get-Config                                                                                        
if (-not $config.ApiBaseUrls.DefectDojo) {                                                                  
    Throw 'DefectDojo API base URL not set in configuration (ApiBaseUrls.DefectDojo).'                      
}                                                                                                           
                                                                                                            
$products = Get-DefectDojoProducts                                                                          
if (-not $products) {                                                                                       
    Throw 'No DefectDojo products found for integration tests.'                                             
}                                                                                                           
$productId = $products[0].Id                                                                                
                                                                                                            
$engagements = Get-DefectDojoEngagements -ProductId $productId                                              
if (-not $engagements) {                                                                                    
    Throw 'No DefectDojo engagements found for integration tests.'                                          
}                                                                                                           
$engagementId = $engagements[0].Id                                                                          
                                                                                                            
Describe 'Get-DefectDojoProducts (Integration)' {                                                           
    It 'Retrieves at least one product' {                                                                   
        $items = Get-DefectDojoProducts                                                                     
        $items.Count | Should -BeGreaterThan 0                                                              
    }                                                                                                       
}                                                                                                           
                                                                                                            
Describe 'Get-DefectDojoEngagements (Integration)' {                                                        
    It 'Retrieves at least one engagement for a product' {                                                  
        $items = Get-DefectDojoEngagements -ProductId $productId                                            
        $items.Count | Should -BeGreaterThan 0                                                              
    }                                                                                                       
}                                                                                                           
                                                                                                            
Describe 'Get-DefectDojoTests (Integration)' {                                                              
    It 'Retrieves at least one test for an engagement' {                                                    
        $items = Get-DefectDojoTests -EngagementId $engagementId                                            
        $items.Count | Should -BeGreaterThan 0                                                              
    }                                                                                                       
} 